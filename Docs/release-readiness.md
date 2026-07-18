# PicoKit release readiness

A release is more than a successful host build. The image, board selection,
SDK revision, generated project, dependencies, and claimed hardware evidence
must describe the same result. Use this checklist before publishing a PicoKit
change or accepting a firmware image for a specific board.

## Define the release claim first

Write the claim in one sentence and choose evidence that matches it:

| Claim | Minimum evidence |
| --- | --- |
| Portable PicoKit API change | host build, host executable, API reference, bridge/source gates |
| Firmware image builds | generated or direct firmware build for the selected board and toolchain |
| Template works across supported boards | generated blink/template matrix for Pico, Pico W, Pico 2, and Pico 2 W |
| USB CDC works on one board | physical flash plus exact byte echo, with board identity and image revision recorded |
| External peripheral works | physical device response or captured waveform for the exact wiring and image |

Do not promote a lower row to a higher row. A passing USB echo does not prove
UART, I2C, SPI, ADC, PWM, or GPIO-interrupt behavior.

## Freeze reproducible inputs

Before the release build, record or commit the inputs that affect the image:

- PicoKit commit and package revision;
- selected `PICO_BOARD` and resulting `PicoChip`;
- Pico SDK revision and SDK cache path or direct CMake path;
- Embedded Swift compiler and cross-compiler versions;
- `Package.swift` and any package resolution state;
- `Firmware/dependencies.json`, `dependencies.lock`, and generated dependency
  CMake when application libraries are present;
- CMake USB options and compiler overrides;
- application source, interop adapters, and the resolved UF2 path.

`Dependencies.local.cmake` and machine-local cache paths are inputs to a local
run, not reproducible release metadata. Keep them out of the committed
dependency record and make any required override explicit in the release log.

## Run the safe gates

From the PicoKit checkout, run the package and source gates before any board
is flashed:

```sh
swift build
swift run PicoKitHostTests
sh Tests/api-reference.sh
sh Tests/docs-links.sh
sh Tests/docs-consistency.sh
sh Tests/peripheral-pin-mux-validation.sh
sh Tests/bridge-validation.sh
sh Tests/bridge-atomic.sh
```

These checks cover portable API behavior, documentation coverage, alternate-
function maps, C bridge invariants, and atomic GPIO/interrupt paths. They do
not require a board and do not prove the final UF2 boots.

## Run the firmware matrix that matches the change

Use the narrowest additional matrix that covers the changed boundary, then
include the full board matrix for a release candidate:

```sh
sh Tests/integration/generated-project.sh
sh Tests/integration/generated-blink.sh
sh Tests/integration/generated-templates.sh
sh Tests/integration/usb-disabled.sh
sh Tests/integration/direct-cmake.sh
sh Tests/integration/compiler-discovery.sh
sh Tests/integration/cmake-options.sh
```

The generated-project check uses a temporary project and fake flashing, so it
is safe without a connected board. The board-aware and template checks catch
wireless LED assumptions, target-module drift, and board-family source errors.
The USB-disabled, direct-CMake, compiler, and option checks cover alternate
build configurations rather than physical behavior.

For a release that changes the firmware bridge, board map, USB startup, DMA,
or generated project, also run the relevant focused gates:

```sh
sh Tests/peripheral-pin-mux-validation.sh
sh Tests/bridge-module.sh
sh Tests/bridge-surface.sh
sh Tests/bridge-warnings.sh
sh Tests/bridge-validation.sh
sh Tests/gpio-facade-host.sh
```

If a prerequisite is missing, record the gate as blocked or not run. Do not
report it as passed because another host-only command succeeded.

## Build and identify the artifact

Build from a clean generated project or an explicitly documented direct-CMake
checkout. Inspect the selected board and output before flashing:

```sh
swiftpico doctor
swiftpico info
swiftpico build
swiftpico devices
```

The project configuration should identify the board, firmware product, UF2
path, PicoKit source or version, and SDK/tool overrides. Verify that the UF2
being flashed is the one just built; a successful copy of an older image is
still a failed release process.

Record at least:

```text
PicoKit commit: <commit>
board: <pico|pico_w|pico2|pico2_w>
chip: <RP2040|RP2350>
SDK revision: <revision>
firmware product: <product>
UF2: <absolute or resolved path>
build result: pass/fail
```

## Physical acceptance is opt-in

Physical flashing changes the selected board. Run it only when the board,
BOOTSEL state, and destructive scope are explicitly owned:

```sh
PICO_TEST_BOARD=pico2_w \
PICO_HARDWARE_TEST=1 \
PICO_HARDWARE_REQUIRE_CDC=1 \
sh Tests/integration/generated-project.sh
```

This gate checks the BOOTSEL chip identity before flashing, waits for CDC
re-enumeration, and performs the exact byte echo fixture. Record the sent and
received bytes, serial path, board identity, and image commit. If no single
device is present, the physical section may report `SKIPPED`; that is honest
evidence, not a pass.

For external peripherals, run the [hardware validation](hardware-validation.md)
matrix separately. Capture power, ground, pin map, voltage levels, protocol
settings, and device response. A board boot and USB echo are not a substitute
for a sensor ACK, UART loopback, SPI identity response, ADC calibration, PWM
waveform, or watchdog reset test.

## Review the final report

Before publishing, check that the report distinguishes:

1. commands that passed and commands that were not run;
2. host, firmware-build, fake-flash, USB, and peripheral evidence;
3. the exact board and firmware image for every physical result;
4. known warnings or environment limitations that did not fail the gate;
5. the next diagnostic step for every failed or skipped layer.

Use [failure diagnosis](failure-diagnosis.md) when a layer fails and
[hardware validation](hardware-validation.md) when a physical claim is needed.
The result should be reproducible by another developer from the recorded
commit, board, SDK, toolchain, commands, and artifact path.

## Related documents

- [Hardware validation](hardware-validation.md) — evidence levels and physical
  run records.
- [Firmware build and bridge](firmware-build-and-bridge.md) — host/firmware
  boundaries and CMake inputs.
- [Peripheral pin validation](peripheral-pin-validation.md) — SDK, Swift, and
  bridge map agreement.
- [External libraries](external-libraries.md) — dependency locks and adapter
  reproducibility.
- [Failure diagnosis](failure-diagnosis.md) — layer-by-layer triage.
