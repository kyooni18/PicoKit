# PicoKit Documentation

## Chapter 12: Core value types


### `PicoChip`

```swift
public enum PicoChip {
    case rp2040
    case rp2350
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
