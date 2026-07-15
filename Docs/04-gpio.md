# PicoKit Documentation

## GPIO, board LED, and timing


### Low-level GPIO

Use this layer when GPIO setup is part of a larger driver or when you need to
handle an error instead of trapping. When one source targets whichever chip
the firmware build selects, use the inferred controller:

```swift
let gpio = PicoGPIO.compiled
let pin = try PicoPin(15)

try gpio.setMode(pin, mode: .output)
try gpio.write(pin, state: .high)
let state = try gpio.read(pin)
try gpio.toggle(pin)
```

Use `PicoGPIO.rp2040` or `PicoGPIO.rp2350` when a driver intentionally names
its target chip.

If the chip is already known, the static convenience constructors keep that
setup short:

```swift
let rp2040GPIO = PicoGPIO.rp2040
let rp2350GPIO = PicoGPIO.rp2350
```

`PicoGPIO` implements `DigitalIO`, allowing alternate implementations and test doubles.

### Coordinated GPIO fast path

For a preconfigured group of pins, use the mask methods to update all selected
pins with one SDK register operation. Bit `n` addresses GPION; bits above 29
are ignored by PicoKit.

```swift
try gpio.configure(.gpio2, mode: .output)
try gpio.configure(.gpio3, mode: .output)
let dataBus: UInt32 = (1 << 2) | (1 << 3)

try gpio.set(mask: dataBus)
try gpio.clear(mask: dataBus)
try gpio.toggle(mask: dataBus)
```

This is the right low-level form for coordinated control-pin changes. For a
cycle-exact protocol or waveform, use PIO or a focused C implementation.

### Throwing Arduino-style GPIO helpers

```swift
try pinMode(15, .output, using: gpio)
try digitalWrite(15, .high, using: gpio)
let state = try digitalRead(15, using: gpio)
```

These helpers validate the integer pin before forwarding to `DigitalIO`, so you
get the Arduino-style call site without losing an error path.

### High-level GPIO facade

For a small, fixed sketch, the high-level facade is more direct:

```swift
pinMode(15, .output)
digitalWrite(15, .high)
let state = digitalRead(15)
```

The high-level API is non-throwing. An error triggers `preconditionFailure`, because invalid setup is treated as a firmware programming or configuration error.

Use the low-level API when the firmware must recover from an error or when the
pin number comes from data outside the sketch.

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

This is useful for host tests and GPIO expanders. Your sketch can stay the same
while the implementation behind it changes.

### Board LED and timing

Use the board-aware SDK status LED when the firmware should not assume a fixed
GPIO number:

```swift
let led = try BoardLED(board: .pico2W)
try led.set(.high)
try led.toggle()
```

When the same source must work with whichever board the firmware build
selects, use `try BoardLED()` to infer the exact compiled board. The explicit
initializer remains useful when a driver intentionally declares its target.

`board` records which target the application expects; the actual LED wiring
and implementation are selected by the firmware build's `PICO_BOARD` setting.
The constructor rejects declarations whose RP2040/RP2350 chip does not match
that firmware target, so keep the board declaration aligned when using a
custom SDK board.

Initialization is shared and safe when more than one `BoardLED` value is
constructed, although one logical owner is still recommended.

For time, `Clock.now()` returns monotonic microseconds and
`try Clock.sleep(for: .milliseconds(500))` blocks the current core. Low-level
helpers are `try delay(500)`, `try delayMicroseconds(10)`, `millis()`, and
`micros()`. Sketch helpers are `sleep(500)` and `sleepMicroseconds(10)`.
Keep every blocking delay out of interrupt handlers.
