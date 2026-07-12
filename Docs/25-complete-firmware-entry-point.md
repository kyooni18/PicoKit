# PicoKit Documentation

## Chapter 25: Complete firmware entry point


Embedded Swift firmware starts from an `@main` type. This lower-level example
shows the shape to use when setup failures need to be handled explicitly:

```swift
import PicoKit

@main
struct Blink {
    static func main() {
        do {
            let serial = try USBSerial()
            let led = try BoardLED(board: .pico2W)
            let interval = try Duration.milliseconds(500)

            while true {
                try led.set(.high)
                try serial.write("LED on")
                try Clock.sleep(for: interval)

                try led.set(.low)
                try serial.write("LED off")
                try Clock.sleep(for: interval)
            }
        } catch {
            while true {}
        }
    }
}
```

For a smaller fail-fast sketch, the high-level API removes the setup `do`/`catch`
and keeps the loop in view:

```swift
import PicoKit

@main
struct App {
    static func main() {
        pinMode(15, .output)
        Serial.println("starting")

        while true {
            digitalWrite(15, .high)
            sleep(500)
            digitalWrite(15, .low)
            sleep(500)
        }
    }
}
```
