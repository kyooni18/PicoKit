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
| `PicoChip` | `.rp2040`, `.rp2350` | Chip family. |
| `PicoBoard` | `.pico`, `.picoW`, `.pico2`, `.pico2W` | `chip`, `cmakeName`, `onboardLEDPin`, `onboardLED`, and `init?(configurationName:)`. Configuration also accepts `pico-w` and `pico2-w`. |
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
    let chip: PicoChip
    init(chip: PicoChip = .rp2040)
    func setMode(_ pin: PicoPin, mode: PinMode) throws
    func configure(_ pin: PicoPin, mode: PinMode, initialState: PinState,
                   pull: PinPull, driveStrength: PinDriveStrength,
                   slewRate: PinSlewRate) throws
    func resetPulse(_ pin: PicoPin, activeState: PinState, duration: Duration) throws
    func write(_ pin: PicoPin, state: PinState) throws
    func read(_ pin: PicoPin) throws -> PinState
    func toggle(_ pin: PicoPin) throws
    func pinMode(_ pin: Int, _ mode: PinMode) throws
    func digitalWrite(_ pin: Int, _ state: PinState) throws
    func digitalRead(_ pin: Int) throws -> PinState
    func digitalToggle(_ pin: Int) throws
}

final class BoardLED {
    init(board: PicoBoard) throws
    func set(_ state: PinState) throws
    func toggle() throws
}

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
    func sleep(_ milliseconds: UInt64)
    func sleepMicroseconds(_ microseconds: UInt64)
}

let pico: Pico
func pinMode(_ pin: Int, _ mode: PinMode)
func digitalWrite(_ pin: Int, _ state: PinState)
func digitalRead(_ pin: Int) -> PinState
func sleep(_ milliseconds: UInt64)
func sleepMicroseconds(_ microseconds: UInt64)
```

`Pico` and the global helpers are non-throwing and fail fast if their low-level
operation fails.

## USB CDC serial

```swift
final class USBSerial {
    init() throws
    func write(_ text: String) throws
    func write(_ bytes: [UInt8]) throws
    func read() throws -> UInt8?
    func read(timeout: Duration) throws -> UInt8
}

final class PicoSerial {
    init()
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
does not discard input. Byte-array writes preserve NUL and non-UTF-8 data.

## UART and PWM

```swift
enum UARTInstance: UInt32 { case uart0, uart1 }

final class PicoUART {
    init(_ instance: UARTInstance, baudRate: Frequency, tx: PicoPin, rx: PicoPin) throws
    let instance: UARTInstance
    func write(_ bytes: [UInt8], timeout: Duration) throws -> Int
    func read(timeout: Duration) throws -> UInt8
}

enum PWMChannel { case a, b }

final class PicoPWM {
    init(pin: PicoPin, frequency: Frequency) throws
    let pin: PicoPin
    func setDutyCycle(_ fraction: UInt16) throws
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

UART reads and writes are bounded by `Duration`. PWM `UInt8` writes map
`0...255` onto the full `UInt16` duty range; `UInt16` writes use the raw range.
The global PWM helpers require the supplied pin to match `pwm.pin`.

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
    func write(address: UInt8, bytes: [UInt8], timeout: Duration) throws -> Int
    func read(address: UInt8, count: Int, timeout: Duration) throws -> [UInt8]
}

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
    let chipSelect: PicoPin?
    func select() throws
    func deselect() throws
    func write(_ bytes: [UInt8]) throws
    func write(_ bytes: [UInt8], timeout: Duration) throws
    func write(_ words: [UInt16]) throws
    func transfer(_ bytes: [UInt8], timeout: Duration) throws -> [UInt8]
}
```

`analogRead(pin:using:)` accepts GPIO26 through GPIO29. I2C validates 7-bit
addresses in `0x08...0x77`, rejects a negative count, and reports
`invalidTimeout` if a duration exceeds the SDK's `UInt32`-microsecond limit.
SPI supports write-only operation without MISO, modes 0 through 3, both bit
orders, 8/16-bit formats, actual-baud reporting, and explicit chip-select.
Blocking writes use the SDK bulk path without an RX allocation; timed writes
report `partialTransfer`. Full-duplex deadline failures use `timedOut`.

## Interrupts and watchdog

```swift
enum GPIOInterruptEdge: UInt32 { case rising = 1, falling = 2, either = 3 }

final class PicoInterrupts {
    init()
    func enable(_ pin: PicoPin, edge: GPIOInterruptEdge) throws
    func takeEvents(for pin: PicoPin) -> UInt32
}

final class PicoWatchdog {
    init()
    func enable(timeout: Duration, pauseOnDebug: Bool = true) throws
    func update()
}
```

GPIO interrupt handlers only coalesce edge bits in the C bridge; call
`takeEvents(for:)` from foreground code. The watchdog timeout must fit whole
milliseconds in a `UInt32`; call `update()` before it expires.

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
| Helper used with the wrong peripheral-owned pin | `ownershipConflict` |
