# PicoKit Documentation

## Chapter 14: GPIO


### Low-level GPIO

Create a GPIO controller for the target chip:

```swift
let gpio = PicoGPIO(chip: .rp2350)
let pin = try PicoPin(15)

try gpio.setMode(pin, mode: .output)
try gpio.write(pin, state: .high)
let state = try gpio.read(pin)
try gpio.toggle(pin)
```

Static convenience constructors are also available:

```swift
let rp2040GPIO = PicoGPIO.rp2040
let rp2350GPIO = PicoGPIO.rp2350
```

`PicoGPIO` implements `DigitalIO`, allowing alternate implementations and test doubles.

### Throwing Arduino-style GPIO helpers

```swift
try pinMode(15, .output, using: gpio)
try digitalWrite(15, .high, using: gpio)
let state = try digitalRead(15, using: gpio)
```

These functions validate the integer pin before forwarding to `DigitalIO`.

### High-level GPIO facade

For small firmware sketches:

```swift
pinMode(15, .output)
digitalWrite(15, .high)
let state = digitalRead(15)
```

The high-level API is non-throwing. An error triggers `preconditionFailure`, because invalid setup is treated as a firmware programming or configuration error.

Use the low-level API when the firmware must recover from an error.

### Custom `DigitalIO`

A custom implementation can be injected into `Pico`:

```swift
final class MockGPIO: DigitalIO {
    func setMode(_ pin: PicoPin, mode: PinMode) throws {}
    func write(_ pin: PicoPin, state: PinState) throws {}
    func read(_ pin: PicoPin) throws -> PinState { .low }
}

let runtime = Pico(gpio: MockGPIO())
runtime.pinMode(3, .output)
runtime.digitalWrite(3, .high)
```

This is useful for host tests and alternate GPIO devices.
