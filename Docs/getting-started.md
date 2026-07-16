# PicoKit getting started

## Overview, boards, and architecture


PicoKit is an Embedded Swift library and a small command-line workflow for
Raspberry Pi Pico boards. It covers the RP2040-based Pico and Pico W as well as
the RP2350-based Pico 2 and Pico 2 W.

You write Swift; PicoKit takes care of crossing into the official Pico SDK when
hardware work is needed. That boundary is deliberately narrow, so application
code gets a typed API without inheriting the SDK's macros, inline functions, or
register details.

Out of the box, PicoKit gives you:

- Validated GPIO pin, duration, and frequency types
- Digital GPIO
- Board status LED control
- USB serial output
- Hardware UART
- Timing and blocking delays
- PWM output
- ADC input
- I2C
- SPI
- GPIO interrupt event collection
- Watchdog control
- High-level Arduino-style convenience functions
- Low-level throwing APIs for recoverable failures

Start with the high-level facade for a small blinking or serial sketch. Reach
for the lower-level types when you need explicit ownership, timeouts, or a way
to recover from an error. For project setup and flashing, use the separate
SwiftPico command-line tool.

The package exports the `PicoKit` library. Project creation, build, flash, and
monitor commands live in the separate
[SwiftPico repository](https://github.com/kyooni18/swiftpico).

### Boards and requirements

| Board | Configuration | Chip |
|---|---|---|
| Pico | `pico` | RP2040 |
| Pico W | `pico_w` | RP2040 |
| Pico 2 | `pico2` | RP2350 |
| Pico 2 W | `pico2_w` | RP2350 |

`pico-w` and `pico2-w` are accepted configuration aliases. Use `BoardLED`
for an onboard LED: unlike a fixed GPIO25 assumption, it uses the SDK's
board-aware status-LED support.

You need a Swift 6-compatible Embedded Swift toolchain, CMake 3.29+, Ninja,
the Pico SDK, and the matching cross compiler (`arm-none-eabi-gcc` for the ARM
targets). SwiftPico host tools require macOS 13+. Run `swiftpico doctor` to
check the toolchain, SDK bridge, boot volumes, and serial devices.

### Layers

`PicoKitCore` contains Foundation-free values, validation, errors, and the
`DigitalIO` protocol. `PicoKitHAL` exposes hardware operations. `PicoKit` is
the umbrella module imported by applications. `Firmware/PicoKitSDKBridge.c` is
the sole Pico SDK boundary; it keeps SDK macros and inline functions out of
Swift code. Host builds compile the API without that bridge, so hardware calls
report `PicoKitError.unavailable` instead of pretending a board exists.

## Create, build, flash, and monitor

Install the companion SwiftPico CLI, check the host toolchain, then create a
standalone firmware package:

```sh
brew tap kyooni18/swiftpico https://github.com/kyooni18/swiftpico
brew install swiftpico
swiftpico doctor
swiftpico init --board pico2_w --name Blink --template blink
cd Blink
./swiftpico build
./swiftpico flash
./swiftpico monitor --reconnect
```

The supported board names are `pico`, `pico_w`, `pico2`, and `pico2_w`
(`pico-w` and `pico2-w` are accepted aliases). Templates include `blink`,
`serial`, `adc`, `pwm`, `i2c`, `spi`, `interrupt`, and `watchdog`.

`swiftpico.json` records the board, firmware directory, PicoKit source or
version, build product, UF2 path, and optional SDK/tool overrides. Use
`./swiftpico info` to inspect resolved configuration. `build` discovers Swift
sources below `Sources/<App>/`; `flash` accepts `--uf2` and `--volume` when
automatic detection is not suitable; `debug` starts OpenOCD.

PicoKit pins its required Pico SDK revision. SwiftPico keeps it in its shared
cache; set `SWIFTPICO_CACHE_DIR` for CI or a shared disk. Direct CMake builds
can instead pass `-DPICO_SDK_PATH=/path/to/pico-sdk`.

## First firmware

The sketch facade is the shortest path to a blink program:

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

Use the lower-level API when setup failures need normal error handling:

```swift
import PicoKit

@main
struct App {
    static func main() {
        do {
            let led = try BoardLED()
            let interval = try Duration.milliseconds(500)
            while true {
                try led.toggle()
                try Clock.sleep(for: interval)
            }
        } catch {
            while true {}
        }
    }
}
```

For in-tree work, run `swift build`, `swift run PicoKitHostTests`, and
`sh Tests/api-reference.sh`. The disposable firmware gate is
`sh Tests/integration/generated-project.sh`.
