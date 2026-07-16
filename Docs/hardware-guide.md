# PicoKit hardware guide

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
    static var compiled: PicoBoard? { get }
}
```

The properties you will reach for most often are:

```swift
board.chip
board.cmakeName
board.onboardLEDPin
board.onboardLED
```

Use `init?(configurationName:)` when a board name comes from configuration or a
command line. It accepts the canonical spellings and the historical hyphenated
aliases.

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

For preconfigured groups of pins, `PicoGPIO.set(mask:)`, `clear(mask:)`, and
`toggle(mask:)` perform one SDK register operation. Bits above GPIO29 are
ignored. Use PIO or focused C for cycle-exact protocols.

## Serial and UART

`Serial` is a lazy, non-throwing USB CDC facade. `write` and `print` preserve
their text; `println` appends a newline. `available` and `read()` poll exact
raw bytes without blocking. Use a reusable `USBSerial` instance and
`read(timeout:)` when the application needs throwing error handling.

Use `./swiftpico monitor --reconnect` for an interactive CDC terminal. The
CMake option `PICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS` is `0` by default, accepts a
positive millisecond bound, and accepts `-1` for an indefinite wait.
`PICOKIT_USB_POST_CONNECT_WAIT_DELAY_MS` defaults to `50` ms for an additional settle delay.
`PICOKIT_USB_CONNECTION_WITHOUT_DTR=ON` is the default, so CDC readiness does
not require a host to assert DTR.

`PicoUART` owns one UART controller, explicit TX/RX pins, and a baud rate.
Polling `read()` returns `nil` for an empty FIFO; bounded reads and writes use
`Duration`. UART0 supports TX/RX pairs `0/1, 2/3, 12/13, 14/15, 16/17, 18/19, 28/29`.
UART1 supports `4/5, 6/7, 8/9, 10/11, 20/21, 22/23, 24/25, 26/27` on
RP2350. `writeDMA(_:timeout:)` aborts its active channel before reporting a
timeout; call `releaseDMAChannel()` when DMA is no longer needed.

## PWM, ADC, I2C, and SPI

Create one `PicoPWM` per output pin. `setDutyCycle` uses the full `UInt16`
range; `setCounterLevel` is the fast path for already-scaled PWM units;
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
