# PicoKit documentation

PicoKit is a small embedded Swift hardware layer. The fastest way to learn it
is to make one firmware image run, then choose the narrow guide that matches
the hardware you are adding. The repository [README](../README.md) explains the
boundary between PicoKit and the SwiftPico host CLI; this directory explains
the firmware API and the evidence needed to trust it.

## How to read this documentation

Every guide answers four questions:

1. What problem does this layer solve?
2. What is the smallest valid Swift program?
3. What does the API validate or refuse before touching hardware?
4. Which host, integration, or physical test proves the behavior?

The [API reference](api-reference.md) is the declaration index. The guides add
the decisions and failure modes that a declaration alone cannot express.

## Start here

1. [Getting started](getting-started.md) — boards, installation, project
   layout, build, flash, monitor, API-level choice, and troubleshooting.
2. [Explained examples](examples.md) — complete blink, button, serial, PWM,
   ADC, I2C, SPI, interrupt, watchdog, and host-test programs.
3. [Hardware guide](hardware-guide.md) — core values, GPIO, timing, ownership,
   interrupts, watchdog, and an overview of every peripheral.

## Focused guides

4. [USB serial and UART](serial-and-uart.md) — byte I/O, connection behavior,
   timeouts, pin mappings, DMA, and monitor workflow.
5. [PWM, ADC, I2C, and SPI](buses-and-analog.md) — configuration, transactions,
   repeated START, frame widths, chip select, and DMA transfers.
6. [Runtime and testing](runtime-and-testing.md) — ownership, host behavior,
   fakes, validation gates, hardware tests, and deliberate limits.
7. [External libraries](external-libraries.md) — dependency files, Clang
   modules, C/C++ adapters, callbacks, migration, and reproducibility.
8. [Performance](performance.md) — fast paths, benchmark fixture, measurement
   method, DMA interpretation, and physical validation.

## Reference

9. [API reference](api-reference.md) — complete public declaration surface.
10. [Integration notes](integration.md) — upgrade-oriented map of the C/C++
   boundary, lockfiles, migration, DMA, and measurement.

## Source-of-truth rule

The Swift declarations under `Sources/PicoKitCore` and `Sources/PicoKitHAL`
define the public API. `Firmware/PicoKitSDKBridge.c` defines the hardware
boundary and status conversion. If a guide and the source disagree, the source
and the executable validation scripts win; update the guide and its validation
string in the same change.

The documentation gates are intentionally visible:

```sh
sh Tests/docs-links.sh
sh Tests/docs-consistency.sh
sh Tests/api-reference.sh
```

For a new public declaration, update the API reference first, then add an
explained example or a focused guide section when the behavior needs wiring,
timing, ownership, or recovery context.
