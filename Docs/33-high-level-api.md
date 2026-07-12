# PicoKit Documentation

## Chapter 33: High-level API

The high-level API is for compact firmware sketches. It avoids `try`, optional
unwrapping, and peripheral setup objects for GPIO, timing, and USB serial.

```swift
import PicoKit

@main
struct Blink {
    static func main() {
        pinMode(15, .output)
        Serial.println("Blink started")

        while true {
            digitalWrite(15, .high)
            sleep(500)
            digitalWrite(15, .low)
            sleep(500)
        }
    }
}
```

## Global sketch API

Importing `PicoKit` provides a default `pico` runtime and these global helpers:

```swift
pinMode(15, .output)
digitalWrite(15, .high)

let state = digitalRead(16)
if state.isHigh {
    Serial.println("GPIO16 is high")
}

sleep(1_000)
sleepMicroseconds(25)
```

`sleep(0)` and `sleepMicroseconds(0)` are valid no-ops. All nonzero delays
block the calling core, so do not use them in interrupt handlers.

## Serial output

`Serial` initializes USB stdio lazily on its first write. It is ready to use
without a `begin`, constructor, or `try`:

```swift
Serial.write("booting")
Serial.print("count = ")
Serial.println(42)
Serial.println()
```

`write` and `print` do not append a newline. `println` appends one after its
value. Values passed to `print` and `println` are converted with
`String(describing:)`.

```swift
var counter = 0

while true {
    Serial.println("loop #\(counter)")
    counter += 1
    sleep(1_000)
}
```

## Explicit runtime

Use `Pico` when a sketch should own its runtime explicitly or when GPIO needs
to be substituted in a host test. The same non-throwing operations are
available as instance methods.

```swift
let board = Pico()

board.pinMode(15, .output)
board.digitalWrite(15, .high)
board.sleep(500)
board.digitalWrite(15, .low)
board.sleepMicroseconds(50)

board.serial.println("done")
```

For example, a test double can be injected without changing sketch logic:

```swift
final class FakeGPIO: DigitalIO {
    var state: PinState = .low

    func setMode(_ pin: PicoPin, mode: PinMode) throws {}
    func write(_ pin: PicoPin, state: PinState) throws { self.state = state }
    func read(_ pin: PicoPin) throws -> PinState { state }
}

let fake = FakeGPIO()
let sketch = Pico(gpio: fake)

sketch.pinMode(7, .output)
sketch.digitalWrite(7, .high)
assert(sketch.digitalRead(7) == .high)
```

## High-level versus low-level

Use the high-level API when pins and hardware configuration are known to be
valid at development time:

```swift
pinMode(15, .output)
digitalWrite(15, .high)
sleep(100)
```

Use low-level APIs when the application must handle invalid input or hardware
failures itself:

```swift
let gpio = PicoGPIO(chip: .rp2040)
let pin = try PicoPin(15)

try gpio.setMode(pin, mode: .output)
try gpio.write(pin, state: .high)
try Clock.sleep(for: .milliseconds(100))
```

The high-level facade deliberately fails fast with `preconditionFailure` when
the corresponding low-level operation throws. It is therefore appropriate for
fixed firmware sketches, but not for inputs received from a user, a network,
or an untrusted configuration file.

The high-level API does not replace the specialized low-level APIs. Continue to
use `BoardLED`, `PicoPWM`, `PicoADC`, `PicoUART`, `PicoI2C`, and `PicoSPI` when
the sketch needs those peripherals.
