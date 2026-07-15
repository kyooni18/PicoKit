# PicoKit API reference

Import one module:

```swift
import PicoKit
```

This reference covers every public PicoKit declaration. APIs that touch
hardware throw `PicoKitError.unavailable("Pico SDK bridge")` in a normal host
SwiftPM build unless noted otherwise.

## Core types

| API | Surface | Notes |
|---|---|---|
| `PicoChip` | `.rp2040`, `.rp2350`, `.compiled` | Chip family; `.compiled` follows the firmware target and uses RP2040 on host builds. |
| `PicoBoard` | `.pico`, `.picoW`, `.pico2`, `.pico2W` | `compiled`, `chip`, `cmakeName`, `onboardLEDPin`, `onboardLED`, and `init?(configurationName:)`. Configuration also accepts `pico-w` and `pico2-w`; `compiled` is optional for custom boards. |
| `PicoKitError` | `invalidPin`, `invalidPeripheralPin`, `invalidFrequency`, `invalidTimeout`, `invalidAddress`, `unavailable`, `timedOut`, `partialTransfer`, `ioFailure`, `ownershipConflict` | All throwing APIs use this error type. `description` is public. |
| `PicoPin` | `init(_:) throws`, `init?(rawValue:)`, `.gpio0` ... `.gpio29` | GPIO `0...29`; exposes `rawValue` and `description`; comparable. |
| `Duration` | `.microseconds(_)`, `.milliseconds(_)`, `.seconds(_)` | Positive duration factories; exposes `microseconds`; comparable. |
| `Frequency` | `.hertz(_)`, `.kilohertz(_)`, `.megahertz(_)` | Positive frequency factories; exposes `hertz`; comparable. |
| `PinMode` | `.input`, `.output` | GPIO direction. |
| `PinState` | `.low`, `.high` | Also exposes `isHigh` and `toggled`. |
| `PinPull` | `.none`, `.up`, `.down` | GPIO pull resistor. |
| `PinDriveStrength` | `.milliamps2`, `.milliamps4`, `.milliamps8`, `.milliamps12` | GPIO output drive. |
| `PinSlewRate` | `.slow`, `.fast` | GPIO edge slew rate. |

### Testable GPIO protocol

```swift
protocol DigitalIO: AnyObject {
    func setMode(_ pin: PicoPin, mode: PinMode) throws
    func write(_ pin: PicoPin, state: PinState) throws
    func read(_ pin: PicoPin) throws -> PinState
}

func pinMode(_ pin: Int, _ mode: PinMode, using gpio: some DigitalIO) throws
func digitalWrite(_ pin: Int, _ state: PinState, using gpio: some DigitalIO) throws
func digitalRead(_ pin: Int, using gpio: some DigitalIO) throws -> PinState
```

These helpers validate the integer pin before calling the supplied object.

## Sketch facade, GPIO, and time

```swift
final class PicoGPIO: DigitalIO {
    static var rp2040: PicoGPIO { get }
    static var rp2350: PicoGPIO { get }
    static var compiled: PicoGPIO { get }
    let chip: PicoChip
    init(chip: PicoChip = .compiled)
    func setMode(_ pin: PicoPin, mode: PinMode) throws
    func configure(_ pin: PicoPin, mode: PinMode, initialState: PinState,
                   pull: PinPull, driveStrength: PinDriveStrength,
                   slewRate: PinSlewRate) throws
    func resetPulse(_ pin: PicoPin, activeState: PinState, duration: Duration) throws
    func write(_ pin: PicoPin, state: PinState) throws
    func read(_ pin: PicoPin) throws -> PinState
    func toggle(_ pin: PicoPin) throws
    func set(mask: UInt32) throws
    func clear(mask: UInt32) throws
    func toggle(mask: UInt32) throws
    func pinMode(_ pin: Int, _ mode: PinMode) throws
    func digitalWrite(_ pin: Int, _ state: PinState) throws
    func digitalRead(_ pin: Int) throws -> PinState
    func digitalToggle(_ pin: Int) throws
}

`PicoGPIO(chip:)` keeps the selected chip as an explicit declaration. Its
firmware operations reject a declaration that differs from the compiled Pico
target; use `PicoGPIO.rp2040` or `PicoGPIO.rp2350` to make that choice explicit.

final class BoardLED {
    init() throws
    init(board: PicoBoard) throws
    let board: PicoBoard
    func set(_ state: PinState) throws
    func toggle() throws
}

`BoardLED` rejects a board declaration whose RP2040/RP2350 chip does not
match the firmware target selected by `PICO_BOARD`.

enum Clock {
    static func now() -> UInt64
    static func sleep(for duration: Duration) throws
}

func delay(_ milliseconds: UInt64) throws
func delayMicroseconds(_ microseconds: UInt64) throws
func millis() -> UInt64
func micros() -> UInt64
```

`delay(0)` and `delayMicroseconds(0)` are no-ops. Nonzero delays and
`Clock.sleep` block the calling core.

```swift
final class Pico {
    let gpio: any DigitalIO
    let serial: PicoSerial
    init(gpio: any DigitalIO = PicoGPIO(), serial: PicoSerial = PicoSerial())
    func pinMode(_ pin: Int, _ mode: PinMode)
    func digitalWrite(_ pin: Int, _ state: PinState)
    func digitalRead(_ pin: Int) -> PinState
    func digitalToggle(_ pin: Int)
    func sleep(_ milliseconds: UInt64)
    func sleepMicroseconds(_ microseconds: UInt64)
}

let pico: Pico
func pinMode(_ pin: Int, _ mode: PinMode)
func digitalWrite(_ pin: Int, _ state: PinState)
func digitalRead(_ pin: Int) -> PinState
func digitalToggle(_ pin: Int)
func sleep(_ milliseconds: UInt64)
func sleepMicroseconds(_ microseconds: UInt64)
```

`Pico` and the global helpers are non-throwing and fail fast if their low-level
operation fails.

## USB CDC serial

```swift
final class USBSerial {
    init() throws
    var isConnected: Bool { get }
    func write(_ text: String) throws
    func write(_ bytes: [UInt8]) throws
    func read() throws -> UInt8?
    func read(timeout: Duration) throws -> UInt8
}

final class PicoSerial {
    init()
    var connected: Bool { get }
    func write(_ text: String)
    func write(_ bytes: [UInt8])
    func print(_ text: String)
    func println(_ text: String = "")
    var available: Bool { get }
    func read() -> UInt8?
}

let Serial: PicoSerial
```

Create `USBSerial` once when errors must be handled. Its nonblocking `read()`
returns `nil` when no byte is waiting; its timeout overload throws
`PicoKitError.timedOut`. `Serial.available` and `Serial.read()` are the
non-throwing sketch form. `available` retains one lookahead byte, so testing it
does not discard input. Byte-array writes preserve NUL and non-UTF-8 data. The
CMake option `PICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS` accepts `0` (no wait), a
positive millisecond bound, or `-1` for the Pico SDK's indefinite wait.
`PICOKIT_USB_POST_CONNECT_WAIT_DELAY_MS` defaults to `50` ms and controls the
additional settle delay after CDC connection; `0` disables that delay.
For hosts that enumerate CDC without asserting DTR, set
`PICOKIT_USB_CONNECTION_WITHOUT_DTR=ON`; the default is `OFF`.

## UART and PWM

```swift
enum UARTInstance: UInt32 { case uart0, uart1 }

final class PicoUART {
    init(_ instance: UARTInstance, baudRate: Frequency, tx: PicoPin, rx: PicoPin,
         chip: PicoChip = .compiled) throws
    let instance: UARTInstance
    let chip: PicoChip
    let actualBaudRate: Frequency
    func write(_ bytes: [UInt8], timeout: Duration) throws -> Int
    func writeDMA(_ bytes: [UInt8]) throws
    func writeDMA(_ bytes: [UInt8], timeout: Duration) throws
    func releaseDMAChannel()
    func read() throws -> UInt8?
    func read(timeout: Duration) throws -> UInt8
}

enum PWMChannel { case a, b }

final class PicoPWM {
    init(pin: PicoPin, frequency: Frequency) throws
    let pin: PicoPin
    let counterTop: UInt16
    let actualFrequency: Frequency
    func setDutyCycle(_ fraction: UInt16) throws
    func setCounterLevel(_ level: UInt16) throws
    func analogWrite(_ duty: UInt8) throws
    func analogWrite(_ duty: UInt16) throws
}

final class PicoBacklight {
    init(pin: PicoPin, frequency: Frequency = .kilohertz(20), activeHigh: Bool = true) throws
    func setBrightness(_ value: UInt8) throws
    func setBrightness(_ value: UInt16) throws
    func off() throws
    func fullOn() throws
}

func analogWrite(_ pin: Int, _ duty: UInt8, using pwm: PicoPWM) throws
func analogWrite(_ pin: Int, _ duty: UInt16, using pwm: PicoPWM) throws
```

UART reads and writes are bounded by `Duration`; a UART write that expires
after accepting only part of its buffer reports `partialTransfer`. PWM `UInt8` writes map
`0...255` onto the full `UInt16` duty range; `UInt16` writes use the raw range.
Transfer counts are limited to `Int32.max` elements because the SDK bridge
reports counts as signed 32-bit values; an oversized buffer is rejected before
the hardware call with `PicoKitError.ioFailure`.
The global PWM helpers require the supplied pin to match `pwm.pin`.
UART construction validates TX/RX pin muxing for the selected chip, including
the RP2350 auxiliary UART mux positions, and firmware rejects a chip
declaration that differs from its compiled Pico target. The existing
initializer behavior defaults to RP2040; pass `chip: .rp2350` for Pico 2
configurations. TX and RX must be different physical pins. I2C rejects
shared SDA/SCL pins, and SPI rejects shared SCK/MOSI/MISO roles in addition to
its chip-select conflict check.

## ADC, I2C, and SPI

```swift
enum ADCChannel: UInt32 { case gpio26, gpio27, gpio28, gpio29, temperature }

final class PicoADC {
    init() throws
    func read(_ channel: ADCChannel) throws -> UInt16
}

func analogRead(_ channel: ADCChannel, using adc: PicoADC) throws -> UInt16
func analogRead(_ pin: Int, using adc: PicoADC) throws -> UInt16

enum I2CInstance: UInt32 { case i2c0, i2c1 }

final class PicoI2C {
    init(_ instance: I2CInstance, frequency: Frequency, sda: PicoPin, scl: PicoPin) throws
    let instance: I2CInstance
    let actualFrequency: Frequency
    func write(address: UInt8, bytes: [UInt8], timeout: Duration, stop: Bool = true) throws -> Int
    func read(address: UInt8, count: Int, timeout: Duration, stop: Bool = true) throws -> [UInt8]
    func writeRead(address: UInt8, bytes: [UInt8], count: Int, timeout: Duration) throws -> [UInt8]
}

Both I2C methods issue STOP by default. Pass `stop: false` to retain the bus
for a repeated START before the next operation.

enum SPIInstance: UInt32 { case spi0, spi1 }
enum SPIMode: UInt32 { case mode0, mode1, mode2, mode3 }
enum SPIBitOrder: UInt32 { case mostSignificantBitFirst, leastSignificantBitFirst }
enum SPIDataBits: UInt32 { case eight = 8, sixteen = 16 }

final class PicoSPI {
    init(_ instance: SPIInstance, frequency: Frequency, sck: PicoPin,
         mosi: PicoPin, miso: PicoPin? = nil, mode: SPIMode = .mode0,
         bitOrder: SPIBitOrder = .mostSignificantBitFirst,
         dataBits: SPIDataBits = .eight, chipSelect: PicoPin? = nil,
         gpio: PicoGPIO? = nil) throws
    let instance: SPIInstance
    let actualFrequency: Frequency
    let dataBits: SPIDataBits
    let miso: PicoPin?
    let chipSelect: PicoPin?
    func select() throws
    func deselect() throws
    func write(_ bytes: [UInt8]) throws
    func read(count: Int, repeatedByte: UInt8 = 0) throws -> [UInt8]
    func read(count: Int, repeatedByte: UInt8 = 0, timeout: Duration) throws -> [UInt8]
    func read(_ count: Int, repeatedWord: UInt16 = 0) throws -> [UInt16]
    func read(_ count: Int, repeatedWord: UInt16 = 0, timeout: Duration) throws -> [UInt16]
    func write(_ bytes: [UInt8], timeout: Duration) throws
    func write(_ words: [UInt16]) throws
    func write(_ words: [UInt16], timeout: Duration) throws
    func writeDMA(_ bytes: [UInt8]) throws
    func writeDMA(_ bytes: [UInt8], timeout: Duration) throws
    func writeDMA(_ words: [UInt16]) throws
    func writeDMA(_ words: [UInt16], timeout: Duration) throws
    func transferDMA(_ bytes: [UInt8]) throws -> [UInt8]
    func transferDMA(_ bytes: [UInt8], timeout: Duration) throws -> [UInt8]
    func transferDMA(_ words: [UInt16]) throws -> [UInt16]
    func transferDMA(_ words: [UInt16], timeout: Duration) throws -> [UInt16]
    func releaseDMAChannels()
    func transfer(_ bytes: [UInt8], timeout: Duration) throws -> [UInt8]
    func transfer(_ words: [UInt16], timeout: Duration) throws -> [UInt16]
}
```

When `chipSelect` is supplied without `gpio`, firmware creates the GPIO
controller for the compiled RP2040 or RP2350 target. Pass `gpio` explicitly
when the application owns a configured GPIO controller.

ADC conversions are serialized in the bridge because channel selection and
temperature-sensor mode are shared by the ADC peripheral. Separate
`PicoADC` values may therefore be used safely from concurrent callers.

`analogRead(pin:using:)` accepts GPIO26 through GPIO29. I2C validates 7-bit
addresses in `0x08...0x77`, rejects a negative count, and reports
`invalidTimeout` if a duration exceeds the SDK's `UInt32`-microsecond limit.
I2C writes issue STOP by default; pass `stop: false` for a repeated-START
register transaction before a following read. `writeRead` validates the
complete composed operation before issuing either transaction.
SPI supports write-only operation without MISO, modes 0 through 3, both bit
orders, 8/16-bit formats, full-duplex transfers for both frame widths,
actual-frequency reporting, and explicit chip-select.
`transfer(_:timeout:)` and `transferDMA(_:)` are full-duplex and require `miso`
to be configured; write-only instances remain valid for blocking and DMA writes.
The chip-select
pin must be distinct from SCK, MOSI, and MISO; SCK, MOSI, and MISO must also be
distinct from one another.
`read(count:repeatedByte:)` is a blocking 8-bit receive operation that clocks
the repeated byte on MOSI and also requires `miso`. In 16-bit mode,
`read(_:repeatedWord:)` provides the corresponding repeated-word operation.
Both receive-only operations also accept `timeout:` to bound the complete
operation; the overloads without a timeout remain blocking.
The 16-bit `write` overload also accepts `timeout:` and reports
`partialTransfer` when output cannot complete before the deadline.
Blocking writes use the SDK bulk path without an RX allocation; timed writes
report `partialTransfer`. DMA writes and DMA transfers synchronously claim and
wait for their paired DMA channels, retain no caller buffer, and keep the
channels for reuse until the
matching `releaseDMA...()` method is called or the owning object deinitializes.
Bounded DMA calls clean up and abort retained channels before returning
`timedOut`; DMA hardware faults are reported as `ioFailure`.

I2C operations report a positive short transfer as `partialTransfer`; negative
bridge statuses remain `timedOut` or `ioFailure` according to the operation.

## Interrupts and watchdog

```swift
enum GPIOInterruptEdge: UInt32 { case rising = 1, falling = 2, either = 3 }

final class PicoInterrupts {
    init()
    func enable(_ pin: PicoPin, edge: GPIOInterruptEdge) throws
    func disable(_ pin: PicoPin)
    func takeEvents(for pin: PicoPin) -> UInt32
}

final class PicoWatchdog {
    init()
    func enable(timeout: Duration, pauseOnDebug: Bool = true) throws
    func update()
}
```

The watchdog hardware uses milliseconds. PicoKit rounds positive sub-millisecond
durations up to 1 ms and rejects values above the board-specific SDK limit:
8,388 ms on RP2040 and 16,777 ms on RP2350.

GPIO interrupt handlers only coalesce edge bits in the C bridge; call
`takeEvents(for:)` from foreground code. The watchdog timeout must stay within
the board-specific limits above; call `update()` before it expires.

## Error behavior

| Condition | Error or behavior |
|---|---|
| Invalid GPIO number | `invalidPin` |
| Zero or overflowing frequency | `invalidFrequency` |
| Zero/overflowing duration, oversized I2C timeout, or oversized watchdog timeout | `invalidTimeout` |
| I2C address outside `0x08...0x77` | `invalidAddress` |
| Missing SDK bridge or unsupported feature | `unavailable` |
| Bounded operation made no progress before its deadline | `timedOut` |
| Other Pico SDK failure | `ioFailure` |
| Helper or peripheral configuration has a pin/instance conflict | `ownershipConflict` |
