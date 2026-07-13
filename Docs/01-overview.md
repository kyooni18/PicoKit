# PicoKit Documentation

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
