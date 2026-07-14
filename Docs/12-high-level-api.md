# PicoKit Documentation

## High-level API

The high-level API is the place to start when the firmware is a small sketch:
an LED, a button, a sensor, and a serial log. It avoids `try`, optional
unwrapping, and setup objects for GPIO, timing, and USB serial, so the important
part of the loop stays easy to see.

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

Importing `PicoKit` gives you a default `pico` runtime and these global helpers.
You do not need to create a controller just to turn a pin on:

```swift
pinMode(15, .output)
digitalWrite(15, .high)

// One atomic hardware XOR on firmware builds; useful for tight blink loops.
digitalToggle(15)

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
without a `begin`, constructor, or `try`, which makes it a good fit for bring-up
messages:

```swift
Serial.write("booting")
Serial.print("count = ")
Serial.println("42")
Serial.println()
```

`write` and `print` do not append a newline. `println` appends one after its
string value. Convert other values explicitly, for example
`Serial.println("count = \(count)")`.

```swift
var counter = 0

while true {
    Serial.println("loop #\(counter)")
    counter += 1
    sleep(1_000)
}
```

## Serial input

`Serial` can also receive bytes from the host USB CDC connection. It is
nonblocking, so a sketch can poll it without stalling its main loop:

```swift
while true {
    if let byte = Serial.read() {
        Serial.write([byte]) // Echo one exact byte.
    }
}
```

`Serial.read()` returns `UInt8?`: `nil` means no byte is currently available.
`Serial.available` is useful when the loop has other work to do, and checking
it does not consume the pending byte:

```swift
if Serial.available {
    let commandByte = Serial.read()!
    // Dispatch commandByte without a hidden blocking read.
}
```

This is raw byte input; PicoKit does not add a line parser or command protocol.
For a bounded, throwing read use `USBSerial.read(timeout:)`.

## Explicit runtime

Use `Pico` when a sketch should own its runtime explicitly or when GPIO needs
to be substituted in a host test. The same non-throwing operations are
available as instance methods, and the code still reads like a sketch.

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
valid at development time. This is the version you would normally write first:

```swift
pinMode(15, .output)
digitalWrite(15, .high)
sleep(100)
```

On firmware builds, these sketch calls validate the integer pin once and then
call the SDK bridge directly. They avoid constructing low-level pin and
duration values on every GPIO or delay call, while retaining the same fail-fast
behavior for invalid pins and overflowing millisecond delays. The injected
`Pico(gpio:)` facade remains available to host tests.

`digitalToggle` maps to the RP-series atomic GPIO XOR operation in firmware.
That avoids a `digitalRead`/`digitalWrite` round trip and is the preferred
high-level operation when a loop only needs to flip an output. An injected host
GPIO fake uses a read/write fallback so it remains easy to test.

Use low-level APIs when the application must handle invalid input or hardware
failures itself. It is more ceremony, but it gives the caller a real error path:

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
the sketch needs those peripherals. It is fine to mix the two styles: use
`Serial.println` for logging while a dedicated `PicoI2C` instance talks to a
sensor, for example.
