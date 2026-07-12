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

The repository includes the same pattern as a dedicated USB serial smoke test
at `Sources/Serial/main.swift`. Build it by overriding the application source
and product, then monitor the board at 115200 baud:

```sh
cmake -S Firmware -B Firmware/build-serial -G Ninja \
  -DPICO_BOARD=pico2_w \
  -DPICOKIT_PRODUCT=Serial \
  -DPICOKIT_SOURCE="$PWD/Sources/Serial/main.swift"
cmake --build Firmware/build-serial --parallel
```

After flashing `Firmware/build-serial/Serial.uf2`, the USB serial output is:

```text
PicoKit Serial example: ready
serial heartbeat 0
serial heartbeat 1
```
