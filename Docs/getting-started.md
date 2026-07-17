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

Configuration names are case-insensitive and trim surrounding whitespace;
`pico-w` and `pico2-w` are accepted aliases. Use `BoardLED`
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

### Everyday commands

Run these from the generated project directory:

| Command | What it does |
|---|---|
| `./swiftpico info` | Show the resolved board, SDK, PicoKit, build, and UF2 paths. |
| `./swiftpico build` | Configure CMake when needed and build the firmware UF2. |
| `./swiftpico flash` | Copy the resolved UF2 to the detected BOOTSEL volume. |
| `./swiftpico make` | Build and flash in one command. |
| `./swiftpico monitor --reconnect` | Open USB CDC and reconnect after resets. |
| `./swiftpico clean` | Remove generated firmware build products. |
| `./swiftpico devices` | List BOOTSEL volumes and serial devices. |

Use `swiftpico init --skip-resolve` only for an intentionally offline
scaffold. A normal project should resolve its dependencies before its first
build. If a board is not discovered for flashing, put it in BOOTSEL mode, run
`./swiftpico devices`, and pass `--volume` only when more than one candidate is
present. `monitor` is an interactive byte terminal: board output remains
visible while bytes typed at the terminal are sent to USB CDC.

### Project layout

The initializer creates an ordinary Swift package, not a special editor
project. Keep application source under `Sources/<App>/`; every Swift file in
that tree is compiled, and `main.swift` supplies the `@main` entry point.

```text
Blink/
  Package.swift
  swiftpico.json
  swiftpico
  Sources/
    Blink/
      main.swift
      Sensor.swift
  Firmware/
    CMakeLists.txt
    Interop/
```

Do not edit generated build output below `Firmware/build`. Put stable CMake or
interop additions in the project-owned `Firmware` files. For a custom board,
keep `PICO_BOARD`, the selected SwiftPico board configuration, and any
explicit `PicoBoard`/`PicoChip` values aligned.

## First firmware

The sketch facade is the shortest path to a blink program:

```swift
import PicoKit

@main
struct Blink {
    static func main() {
        pinMode(15, .output)
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

## Choosing the API level

The sketch facade is for constants you control in firmware source. It keeps
simple programs compact, but calls `preconditionFailure` when a lower-level
operation would throw. Use it for board bring-up, a button/LED loop, or simple
logging.

The low-level API is better for reusable drivers and data-derived settings. It
uses `PicoPin`, `Duration`, `Frequency`, peripheral instances, and
`PicoKitError`, so an application can report a bad configuration or retry a
timeout instead of trapping. The two levels can be mixed: `Serial.println` is
fine for logging while a `PicoI2C` instance owns a sensor bus.

## Troubleshooting

Start with `swiftpico doctor`; it reports the Embedded Swift toolchain, CMake,
Ninja, cross compiler, SDK cache, BOOTSEL volumes, and serial devices. When a
build has already been configured and only source changed, `./swiftpico build`
is the preferred path. For a direct CMake investigation, use the generated
project's `Firmware` directory and retain its configured SDK path:

```sh
cmake -S Firmware -B Firmware/build -G Ninja
cmake --build Firmware/build --parallel
```

The resulting UF2 path is recorded by `./swiftpico info`; do not assume every
project uses the same product name. A host-side `swift build` validates public
Swift APIs but does not emulate peripherals—hardware calls correctly report
`PicoKitError.unavailable("Pico SDK bridge")` on that path.
