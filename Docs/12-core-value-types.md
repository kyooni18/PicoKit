# PicoKit Documentation

## Chapter 12: Core value types


### `PicoChip`

```swift
public enum PicoChip {
    case rp2040
    case rp2350
}
```

This identifies the MCU family.

### `PicoBoard`

```swift
public enum PicoBoard {
    case pico
    case picoW
    case pico2
    case pico2W
}
```

Important properties:

```swift
board.chip
board.cmakeName
board.onboardLEDPin
board.onboardLED
```

Use `init?(configurationName:)` when decoding board names from user configuration.

### `PicoPin`

`PicoPin` validates a GPIO number before hardware access:

```swift
let pin = try PicoPin(15)
```

Valid values are `0...29`. Invalid values throw:

```swift
PicoKitError.invalidPin
```

The raw SDK-compatible number is available as:

```swift
pin.rawValue
```

### `Duration`

A `Duration` stores a positive number of microseconds:

```swift
let shortDelay = try Duration.microseconds(10)
let interval = try Duration.milliseconds(500)
let timeout = try Duration.seconds(2)
```

Zero is not accepted by the type factories. The standalone `delay`, `sleep`, and related convenience functions treat zero as a valid no-op.

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
