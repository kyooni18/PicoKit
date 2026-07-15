# PicoKit Documentation

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
