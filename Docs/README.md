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
3. [Application design](application-design.md) — structure a growing firmware
   loop, choose failure policies, own peripherals, and verify behavior.
4. [Board and pin planning](board-and-pin-planning.md) — current RP2040/RP2350
   board mapping, UART/I2C/SPI pin tables, conflicts, and physical verification.
5. [Hardware guide](hardware-guide.md) — core values, GPIO, timing, ownership,
   interrupts, watchdog, and an overview of every peripheral.

## Focused guides

1. [USB serial and UART](serial-and-uart.md) — byte I/O, connection behavior,
   timeouts, pin mappings, DMA, and monitor workflow.
2. [PWM, ADC, I2C, and SPI](buses-and-analog.md) — configuration, transactions,
   repeated START, frame widths, chip select, and DMA transfers.
3. [Runtime and testing](runtime-and-testing.md) — ownership, host behavior,
   fakes, validation gates, hardware tests, and deliberate limits.
4. [External libraries](external-libraries.md) — dependency files, Clang
   modules, C/C++ adapters, callbacks, migration, and reproducibility.
5. [Performance](performance.md) — fast paths, benchmark fixture, measurement
   method, DMA interpretation, and physical validation.
6. [Failure diagnosis](failure-diagnosis.md) — classify configuration, build,
   flash, USB, and peripheral failures by the strongest available evidence.
7. [DMA and buffer lifecycle](dma-and-buffer-lifecycle.md) — synchronous
   prepared-buffer transfers, channel ownership, timeout cleanup, and sizing.
8. [GPIO and reset sequencing](gpio-and-reset-sequencing.md) — electrical
   settings, glitch-free startup, active-level pulses, and physical verification.
9. [Interrupts and watchdog](interrupts-and-watchdog.md) — coalesced edge
   delivery, foreground debounce, healthy-loop feeding, and board limits.
10. [ADC and PWM](analog-and-pwm.md) — raw sampling, frequency quantization,
   counter units, duty scaling, and backlight polarity.
11. [Firmware build and bridge](firmware-build-and-bridge.md) — host versus
   firmware builds, CMake inputs, SDK/compiler selection, USB options, and evidence.
12. [I2C and SPI transactions](i2c-and-spi-transactions.md) — bus framing,
   chip-select lifetime, transfer formats, timeouts, and physical proof.
13. [Hardware validation](hardware-validation.md) — host, firmware, fake-flash,
   USB-echo, and physical-peripheral evidence with safety boundaries.
14. [Typed API and errors](typed-api-and-errors.md) — board identity, validated
   pins, explicit units, failure categories, and API-level choice.
15. [Driver testing](driver-testing.md) — injected GPIO fakes, typed failures,
   serial buffering, host-only seams, and evidence boundaries.
16. [Peripheral pin validation](peripheral-pin-validation.md) — SDK-header,
   Swift, and C-bridge map agreement, chip-family differences, and diagnosis.
17. [Timing and deadlines](timing-and-deadlines.md) — delays, operation
   timeouts, application budgets, watchdog windows, and host timing limits.
18. [Peripheral recovery](peripheral-recovery.md) — typed failure policy,
   bounded retries, reset sequencing, safe outputs, and bus resynchronization.
19. [Release readiness](release-readiness.md) — reproducible inputs, board
   matrix gates, artifact identity, and evidence-accurate release claims.
20. [Observability and diagnostics](observability-and-diagnostics.md) —
   connection-independent reporting, byte protocols, bounded logging, and
   evidence capture.
21. [Custom-board support](custom-board-support.md) — recognized versus custom
   metadata, explicit LED handling, chip selection, and validation boundaries.
22. [CI validation](ci-validation.md) — host architectures, firmware matrix,
   safe fake-flash gates, hardware boundaries, and failure interpretation.
23. [Public API evolution](public-api-evolution.md) — layer placement,
   compatibility, typed errors, bridge synchronization, and contributor gates.
24. [Resource ownership](resource-ownership.md) — pins, buses, DMA, USB,
   interrupts, watchdogs, concurrency, and handoff order.

## Reference

1. [API reference](api-reference.md) — complete public declaration surface.
2. [Integration notes](integration.md) — upgrade-oriented map of the C/C++
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
