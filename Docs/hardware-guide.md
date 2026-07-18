# PicoKit hardware guide

## Hardware contract before wiring

Before connecting a peripheral, record the compiled board, selected chip, pin
function, voltage level, pull state, bus frequency, and timeout. Constructors
validate digital pin maps and the bridge validates chip-specific mux rules; no
software check can detect a swapped wire, missing common ground, incorrect
voltage, or an address conflict. Treat `PicoKitError` as a software diagnostic,
not as an electrical test.

## Core types and errors


### `PicoChip`

```swift
public enum PicoChip {
    case rp2040
    case rp2350
    static var compiled: PicoChip { get }
}
```

This tells PicoKit which MCU family a board belongs to.

### `PicoBoard`

```swift
public enum PicoBoard {
    case pico
    case picoW
    case pico2
    case pico2W
    public static var compiled: PicoBoard? { get }
    public var chip: PicoChip { get }
    public var cmakeName: String { get }
    public var isWireless: Bool { get }
    public var onboardLEDPin: PicoPin? { get }
    public var onboardLED: Int? { get }
    public init?(configurationName: String)
}
```

The properties you will reach for most often are:

```swift
board.chip
board.cmakeName
board.isWireless
board.onboardLEDPin
board.onboardLED
```

Use `init?(configurationName:)` when a board name comes from configuration or a
command line. It accepts the canonical spellings and the historical hyphenated
aliases.

Configuration matching trims surrounding whitespace and is case-insensitive,
so values such as ` PICO2_W\n` are accepted as well.

`PicoBoard.compiled` reports the exact board selected by firmware's
`PICO_BOARD`. It is `nil` for a custom board that PicoKit does not recognize;
host builds use `.pico` as their validation default.

### `PicoPin`

`PicoPin` is the low-level API's answer to "is this actually a usable GPIO?" It
validates the number before anything touches hardware:

```swift
let pin = try PicoPin(15)
```

Valid values are `0...29`; an invalid value throws:

```swift
PicoKitError.invalidPin
```

The raw SDK-compatible number is available as:

```swift
pin.rawValue
```

### `Duration`

A `Duration` stores a positive number of microseconds. Construct one when an
operation needs an explicit delay or timeout:

```swift
let shortDelay = try Duration.microseconds(10)
let interval = try Duration.milliseconds(500)
let timeout = try Duration.seconds(2)
```

Zero is not accepted by these factories, because a low-level timeout of zero is
usually a bug. The standalone `delay`, `sleep`, and related convenience
functions deliberately treat zero as a no-op.

### `Frequency`

A `Frequency` stores a positive number of hertz:

```swift
let uartRate = try Frequency.hertz(115_200)
let pwmRate = try Frequency.kilohertz(1)
let spiRate = try Frequency.megahertz(8)
```

Conversion overflow and zero values throw `PicoKitError.invalidFrequency`.

### `PinMode`

```swift
.input
.output
```

### `PinState`

```swift
.low
.high
```

Additional properties:

```swift
state.toggled
state.isHigh
```

### Errors

Low-level APIs report `PicoKitError`:

| Error | Meaning |
|---|---|
| `invalidPin` | GPIO is outside `0...29` |
| `invalidFrequency` | Frequency is zero or overflowed |
| `invalidTimeout` | Duration is zero, overflowed, or unsupported |
| `invalidAddress` | I2C address is outside `0x08...0x77` |
| `unavailable` | Hardware bridge or board feature is unavailable |
| `timedOut` | A bounded operation made no progress before its deadline |
| `partialTransfer` | A transfer completed only part of the requested elements |
| `ioFailure` | Pico SDK returned another failure |
| `ownershipConflict` | A peripheral pin or instance conflicts with the requested operation; `description` preserves the specific conflict reason |

`PicoKitError.description` is suitable for logs during board bring-up.

### A useful error-handling pattern

Construct long-lived values once, then keep the recovery decision close to the
operation that can fail. For example, a timeout can be logged and retried while
an invalid pin should usually stop configuration:

```swift
let serial = try USBSerial()
let gpio = PicoGPIO.compiled
let input = try PicoPin(15)
try gpio.setMode(input, mode: .input)

do {
    if let byte = try serial.read() {
        try serial.write(byte)
    }
} catch PicoKitError.timedOut {
    // A bounded operation may be retried by application policy.
} catch {
    // Record or handle the hardware failure appropriate to this firmware.
}
```

## Sketch facade, GPIO, and time

Use the global helpers for a small fixed sketch:

```swift
pinMode(15, .output)
digitalWrite(15, .high)
digitalToggle(15)
let state = digitalRead(16)
sleep(1_000)
sleepMicroseconds(25)
```

They fail fast if configuration is invalid. Use `PicoGPIO`, `PicoPin`, and the
throwing `pinMode`, `digitalWrite`, and `digitalRead` overloads when input or
hardware errors must be handled. `Pico(gpio:)` accepts a `DigitalIO` fake for
host tests. `BoardLED()` uses board-aware SDK status-LED support. Blocking
delays must not be called from an interrupt handler.

For code that explicitly records its target board, keep the declaration next to
the LED setup so a mismatched firmware configuration fails immediately:

```swift
func blinkLED(for board: PicoBoard) throws {
    let led = try BoardLED(board: board)
    try led.set(.high)
    try led.toggle()
}
```

The wireless variants (`.picoW` and `.pico2W`) do not expose a GPIO-number LED;
`BoardLED` uses the board's SDK status-LED implementation instead.

For preconfigured groups of pins, `PicoGPIO.set(mask:)`, `clear(mask:)`, and
`toggle(mask:)` perform one SDK register operation. Bits above GPIO29 are
ignored. Use PIO or focused C for cycle-exact protocols.

`PicoGPIO` is intentionally a thin Swift API over PicoKit's operation-level C
facade. Chip matching, argument validation, glitch-free configuration, atomic
mask updates, and reset-pulse sequencing execute on the C side. Application
code and the Arduino-style `Pico` convenience API both use this same path.

Single-pin writes and toggles and the three mask operations use the SDK's
atomic set, clear, or XOR register paths, so they do not perform a lossy
read-modify-write. This does not make a `PicoGPIO` controller concurrently
usable: configuration and reset pulses are multi-step sequences. Keep one
logical owner per pin and do not operate the same controller from multiple
tasks, cores, or interrupt handlers.

`PicoGPIO.configure` is the lower-level setup form when pull, drive strength,
slew rate, and initial level all matter. The bridge writes the output latch
before enabling output direction, avoiding an unwanted low pulse on active-low
reset or chip-select lines:

```swift
try gpio.configure(
    .gpio17,
    mode: .output,
    initialState: .high,
    pull: .none,
    driveStrength: .milliamps8,
    slewRate: .fast
)
try gpio.resetPulse(.gpio20, activeState: .low, duration: .milliseconds(10))
```

For host tests, inject a `DigitalIO` implementation rather than branching on
the platform in the sketch:

```swift
final class FakeGPIO: DigitalIO {
    var state: PinState = .low
    func setMode(_ pin: PicoPin, mode: PinMode) throws {}
    func write(_ pin: PicoPin, state: PinState) throws { self.state = state }
    func read(_ pin: PicoPin) throws -> PinState { state }
}

let app = Pico(gpio: FakeGPIO())
app.pinMode(7, .output)
app.digitalWrite(7, .high)
```

## Serial and UART

`Serial` is a lazy, non-throwing USB CDC facade. `write` and `print` preserve
their text; `println` appends a newline. `available` and `read()` poll exact
raw bytes without blocking. Use a reusable `USBSerial` instance and
`read(timeout:)` when the application needs throwing error handling.

Use `./swiftpico monitor --reconnect` for an interactive CDC terminal. The
CMake option `PICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS` is `0` by default, accepts a
positive millisecond bound, and accepts `-1` for an indefinite wait.
`PICOKIT_USB_POST_CONNECT_WAIT_DELAY_MS` defaults to `50` ms for an additional settle delay.
`PICOKIT_USB_CONNECTION_WITHOUT_DTR=OFF` is the default, so connection probes
and writes wait for the host to open CDC and assert DTR. Enable the option only
for a host that opens CDC without asserting DTR; USB enumeration and the
1200-baud reset path remain available either way.

`PicoUART` owns one UART controller, explicit TX/RX pins, and a baud rate.
Polling `read()` returns `nil` for an empty FIFO; bounded reads and writes use
`Duration`. UART0 supports TX/RX pairs `0/1, 2/3, 12/13, 14/15, 16/17, 18/19, 28/29`.
UART1 supports `4/5, 6/7, 8/9, 10/11, 20/21, 22/23, 24/25, 26/27` on
RP2350. `writeDMA(_:timeout:)` aborts its active channel before reporting a
timeout; call `releaseDMAChannel()` when DMA is no longer needed.

### USB CDC example

`Serial` preserves bytes, including values that are not valid UTF-8. This makes
the following a useful bring-up echo without imposing a line protocol:

```swift
while !Serial.connected { sleep(10) }
Serial.println("ready")
while true {
    if let byte = Serial.read() {
        Serial.write(byte)
    }
}
```

With the default DTR-dependent connection check, waiting for `connected`
prevents the one-shot readiness line from being discarded before a monitor
opens the CDC device.

For a command that must arrive within a bounded time, use `USBSerial` instead.
An empty connected FIFO throws `PicoKitError.timedOut`; a disconnected host
throws `PicoKitError.unavailable("USB serial host is not connected")`:

```swift
let serial = try USBSerial()
let command = try serial.read(timeout: .seconds(5))
try serial.write(command)
```

`isConnected` is a snapshot, not a delivery guarantee; still handle a failed
write. PicoKit intentionally provides no line buffer, framing, parity setup,
or concurrent-access control. Those policies belong to the firmware protocol.

### UART example

Keep UART construction in one owner and reuse it for all I/O:

```swift
let uart = try PicoUART(
    .uart0,
    baudRate: .hertz(115_200),
    tx: .gpio0,
    rx: .gpio1,
    chip: .compiled
)
try uart.write(Array("hello\\r\\n".utf8), timeout: .milliseconds(100))
if let byte = try uart.read() {
    // Process a currently available byte.
}
```

`actualBaudRate` reports the divider-quantized rate selected by the SDK. A
write that makes partial progress before its deadline reports
`PicoKitError.partialTransfer`; framing and buffering remain application work.

## PWM, ADC, I2C, and SPI

Create one `PicoPWM` per output pin. GPIOs sharing a PWM slice may coexist only
when they use the same quantized carrier frequency, and a second owner of the
same slice channel is rejected. `setDutyCycle` uses the full `UInt16` range;
`setCounterLevel` is the fast path for already-scaled PWM units;
`analogWrite(0, UInt8(128), using: pwm)` is the convenient 8-bit form.
`PicoADC` reads `.gpio26` through `.gpio29` or `.temperature` as raw `UInt16`
values; voltage conversion remains application policy.

`PicoI2C` validates 7-bit addresses (`0x08...0x77`) and distinct SDA/SCL pins.
Calls issue STOP by default. Use `PicoI2C.write(..., stop: false)` followed by
`PicoI2C.read(..., stop: false)` or `writeRead` for repeated-start sequences.
I2C reads and writes report a positive short result as `partialTransfer`.

`PicoSPI` owns its selected pins and optional active-low chip select (high
while idle), driven with `select()` and `deselect()`. It supports mode, bit
order, and 8/16-bit frame width. `read(count:repeatedByte:)` and
`read(_:repeatedWord:)` require configured MISO; `transferDMA` does too.
`writeDMA` and `transferDMA` are synchronous prepared-buffer fast paths;
call `releaseDMAChannels()` when they are no longer needed.

### PWM and ADC examples

Create PWM once and update only the duty cycle in the loop. `counterTop` tells
you the maximum hardware counter level for the selected frequency; values above
it saturate at full duty:

```swift
let pwm = try PicoPWM(pin: .gpio0, frequency: .kilohertz(1))
try pwm.setDutyCycle(32_768)
try pwm.setCounterLevel(pwm.counterTop / 4)
try analogWrite(0, UInt8(128), using: pwm)
```

Likewise, reuse an ADC instance for repeated samples:

```swift
let adc = try PicoADC()
let sample = try adc.read(.gpio26)
let temperatureRaw = try adc.read(.temperature)
```

Raw readings are intentionally not converted to volts or degrees: reference
voltage, board calibration, and sensor policy differ by application.

### I2C and SPI examples

An I2C register read normally uses a write without STOP followed by a read:

```swift
let i2c = try PicoI2C(.i2c0, frequency: .kilohertz(400), sda: .gpio4, scl: .gpio5)
let bytes = try i2c.writeRead(
    address: 0x3C,
    bytes: [0x10],
    count: 4,
    timeout: .milliseconds(100)
)
```

Empty writes and direct zero-length reads are safe validated no-ops.
`writeRead` requires a nonzero response count and rejects an empty response
before it sends a no-STOP prefix. `actualFrequency` reports the
divider-quantized bus speed. Keep device-specific register and transaction
policy in a focused driver above the bus instance.

SPI is full duplex when MISO is present. A typical device-owner sequence is:

```swift
let spi = try PicoSPI(
    .spi0, frequency: .megahertz(8), sck: .gpio18, mosi: .gpio19,
    miso: .gpio16, chipSelect: .gpio17
)
try spi.select()
let identifier = try spi.transfer([0x9F, 0, 0, 0], timeout: .milliseconds(100))
try spi.deselect()
```

Use `writeDMA` for a sufficiently large prepared display buffer, not for
single-byte commands. It reduces CPU work but not a peripheral's clock-limited
transfer time.

## Interrupts, ownership, tests, and limits

`PicoInterrupts` records selected edges in the C bridge; foreground Swift
retrieves and clears them with `takeEvents(for:)`. Events are bit-coalesced,
not an exact edge count. Never call Swift from an IRQ handler. Enable
`PicoWatchdog` only after the main loop is healthy; its maximum timeout is
8,388 ms on RP2040 and 16,777 ms on RP2350.

Give each UART, I2C, SPI, PWM slice, watchdog, and USB state one logical
owner. Peripheral instances are not thread-safe. Host builds report unavailable
hardware rather than emulating it. PicoKit has no async scheduler, PIO,
Wi-Fi/Bluetooth, multicore coordination, or general ownership registry.

### Test and firmware boundaries

Host validation covers value checks, errors, fake GPIO, serial buffering, and
the public API surface. It does not require a board. Firmware validation builds
the Embedded Swift target and is the place to verify pin muxing, timing, USB
enumeration, and physical wiring. Useful in-tree gates are:

```sh
swift build
swift run PicoKitHostTests
sh Tests/api-reference.sh
sh Tests/docs-consistency.sh
sh Tests/integration/generated-project.sh
sh Tests/integration/generated-templates.sh
```

Set `PICO_HARDWARE_TEST=1` only when a connected board should be flashed and
byte-echo tested. Hardware events should be processed on foreground Swift code:
interrupt handlers only accumulate edge flags, and no peripheral instance is
safe for concurrent use from tasks, cores, or IRQ context.
