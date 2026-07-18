# PicoKit validation and hardware evidence

PicoKit has several validation layers, and each proves a different claim. Keep
them separate in reports, release notes, and debugging notes:

| Layer | Command or evidence | Proves | Does not prove |
| --- | --- | --- | --- |
| Host package | `swift build`, `swift run PicoKitHostTests` | Portable Swift, errors, fakes, and API behavior | SDK linkage or wiring |
| C facade | `sh Tests/gpio-facade-host.sh` | C-side validation and operation ordering with a fake SDK | A real GPIO voltage |
| Firmware integration | generated/direct CMake scripts | Embedded compiler, bridge, board symbols, and ELF/UF2 production | A connected device response |
| Template contract | `sh Tests/integration/generated-templates.sh` | Templates typecheck against the exact built Embedded Swift module | Flash or runtime output |
| Fake flash | default `generated-project.sh` | UF2 selection and CLI flash argument shape | A board received the image |
| USB hardware | `PICO_HARDWARE_TEST=1` | A selected board flashed and exchanged exact CDC bytes | I2C/SPI/UART correctness |
| Peripheral hardware | scope, logic analyzer, or device response | Electrical waveform or device-specific protocol | Every board/configuration |

A green lower layer is not evidence for a higher layer. In particular, a host
build or USB echo must not be reported as proof that an external sensor bus is
wired correctly.

## Run the safe host gates first

From the PicoKit checkout:

```sh
swift build
swift run PicoKitHostTests
sh Tests/gpio-facade-host.sh
sh Tests/api-reference.sh
sh Tests/docs-links.sh
sh Tests/docs-consistency.sh
```

`PicoKitHostTests` is an executable rather than an XCTest target so the
Foundation-free checks can run with the same toolchain family used for
firmware. Hardware constructors report
`PicoKitError.unavailable("Pico SDK bridge")` on this path; that is intentional
and prevents host tests from pretending physical I/O occurred.

The GPIO facade host fixture uses fake SDK headers and records calls. It can
prove that invalid pins and arguments are rejected before hardware calls, that
the output latch is set before direction, and that mask/toggle/reset operations
use the intended order. It cannot measure an actual edge, pull, drive current,
or reset voltage.

## Disposable firmware integration

The normal generated-project gate creates a temporary SwiftPico project whose
PicoKit dependency points at the current checkout:

```sh
sh Tests/integration/generated-project.sh
```

The script verifies that the generated project contains the expected PicoKit
path, replaces its entry point with the tracked split-source fixture, builds a
real release ELF and UF2, checks USB startup symbols when `nm` is available,
and invokes SwiftPico with a fake picotool. The fake tool records the expected
`load -f <uf2>` arguments; it does not touch a board.

This makes the default command safe on a development machine without a Pico.
It proves the generated project, CMake bridge, selected compiler, linker, and
CLI artifact path agree. It does not prove that an image was accepted by a
bootloader or that the firmware emitted bytes.

Use the board-family template and typecheck gates as separate evidence:

```sh
# Inspect board-aware Blink generation for Pico, Pico W, Pico 2, and Pico 2 W.
sh Tests/integration/generated-blink.sh

# Build one real Embedded Swift module, then typecheck all templates against it.
sh Tests/integration/generated-templates.sh
```

`generated-blink.sh` checks that wireless templates use `BoardLED(board:)`
instead of assuming GPIO25, while non-wireless templates retain the GPIO25
sketch path. `generated-templates.sh` builds a Pico anchor project once and
typechecks the blink, serial, ADC, PWM, I2C, SPI, interrupt, and watchdog
templates with its exact `armv6m-none-none-eabi` module.

## Additional firmware gates

Use these when the change touches their boundary:

```sh
sh Tests/integration/usb-disabled.sh
sh Tests/integration/direct-cmake.sh
sh Tests/integration/compiler-discovery.sh
sh Tests/integration/cmake-options.sh
sh Tests/integration/usb-serial-status-firmware.sh
sh Tests/bridge-validation.sh
sh Tests/bridge-atomic.sh
```

Their scopes are deliberately narrow:

- `usb-disabled.sh` builds each board family with the CDC path disabled and
  checks the expected compiled-board messages and UF2 output.
- `direct-cmake.sh` verifies that the in-tree CMake path can discover the
  Embedded Swift compiler and SDK without relying on the CLI wrapper.
- `compiler-discovery.sh` checks explicit compiler environment overrides and
  rejects invalid paths rather than silently selecting a host compiler.
- `cmake-options.sh` checks USB timeout spelling, bounds, and DTR-independent
  connection settings during configure.
- `usb-serial-status-firmware.sh` compiles the throwing USB status probe for
  RP2040 and RP2350.
- `bridge-validation.sh` checks source-level C bridge invariants, including
  validation-before-mux behavior, DMA cleanup, board mappings, and watchdog
  bounds.
- `bridge-atomic.sh` checks atomic GPIO and interrupt producer/consumer paths.

These gates may require the SwiftPico checkout, SDK cache, Embedded Swift
toolchain, or cross compiler. A missing prerequisite is a blocked validation
environment, not evidence that firmware behavior failed.

## Optional physical flash and CDC echo

Physical flashing is opt-in because it is destructive to the selected board.
Run it only when exactly one intended device is connected or a board is
explicitly in BOOTSEL mode and its identity is owned:

```sh
PICO_HARDWARE_TEST=1 sh Tests/integration/generated-project.sh
```

Select the expected family when it is not the default Pico:

```sh
PICO_TEST_BOARD=pico2_w \
PICO_HARDWARE_TEST=1 \
sh Tests/integration/generated-project.sh
```

Before flashing, the script checks a detected BOOTSEL chip identity against
`PICO_TEST_BOARD`. It builds the temporary release image, checks the expected
USB startup/TinyUSB symbols when available, flashes the UF2 through SwiftPico,
waits for CDC re-enumeration, and runs the exact byte echo fixture.

The echo includes NUL, `0x7F`, and `0xFF`, so it proves that the path preserves
binary input rather than only printable text. The fixture also verifies the
line-ending behavior produced by the firmware's echo program. It is evidence
for that image, board, USB path, and moment—not for UART, I2C, SPI, or an
unrelated application.

By default, if no single serial device is present, the optional physical
section reports `SKIPPED`. If the board remains USB-controlled in BOOTSEL after
a successful flash, flash is reported while echo is skipped. Set
`PICO_HARDWARE_REQUIRE_CDC=1` when CDC enumeration is a required acceptance
criterion:

```sh
PICO_TEST_BOARD=pico2_w \
PICO_HARDWARE_TEST=1 \
PICO_HARDWARE_REQUIRE_CDC=1 \
sh Tests/integration/generated-project.sh
```

Never enable this section in unattended CI unless the connected board,
bootloader state, and destructive flash scope are explicitly owned by that job.

## Peripheral validation matrix

After the firmware and USB path are proven, validate one physical peripheral
at a time. Record the selected board, chip, PicoKit/SDK revisions, power,
ground, wiring, and expected response:

| Feature | Minimal physical evidence |
| --- | --- |
| Board LED/GPIO | Measured output level or visible board LED transition |
| Delay/timer | Measured pulse period and duty on a scope/analyzer |
| UART | TX-to-RX loopback with byte integrity and timeout behavior |
| PWM | Measured carrier frequency and duty at requested levels |
| ADC | Calibrated low/mid/high input samples and monotonicity |
| I2C | Addressed device ACK/read response, then unplug timeout |
| SPI | Known identity/pattern response with captured CS/clock/data |
| GPIO interrupt | Deliberate edges observed by foreground polling, with debounce policy |
| Watchdog | Intentional missed update resets, healthy updates prevent reset |

For bus failures, capture the waveform before changing several software
settings at once. A successful constructor proves only the typed pin/function
map; it does not prove voltage, pull-up sizing, chip select, device address, or
protocol framing.

## Recording a run

Keep a small record for every physical or release-relevant validation:

```text
board: pico2_w
chip: rp2350
PicoKit commit: <commit>
SDK revision: <revision>
firmware product: SerialEcho
UF2: <resolved path>
flash target: <BOOTSEL identity or volume>
serial path: <CDC device path>
hardware gate: PICO_HARDWARE_REQUIRE_CDC=1
sent bytes: 50 69 6f 00 7f ff 0a
received bytes: <captured bytes>
wiring: <device/pin/power record>
instrument: <scope/analyzer/model or none>
result: pass/fail/skip with reason
```

A skipped physical section is an honest result, not a pass. A passing script
without board identity, image revision, and captured output is difficult to
compare with a later release.

## Failure triage

Use the first failed layer as the next diagnostic step:

1. Host failure: inspect Swift source, package API, or toolchain.
2. CMake/compiler failure: inspect SDK path, Embedded Swift compiler, board,
   target architecture, and cache values.
3. Missing ELF/UF2: inspect product name and final firmware link output.
4. Fake-flash mismatch: inspect generated project metadata and resolved UF2.
5. Flash failure: inspect BOOTSEL state, board identity, and device selection.
6. CDC silence: inspect USB options, enumeration, monitor timing, and startup
   output policy.
7. Peripheral silence: inspect power, ground, pin mux, pull-ups, CS/address,
   waveform, and protocol framing.

Do not rerun a lower-level green check as proof of a higher-level failure. Keep
the original output and record the exact change made before the next attempt.

## Related documents

- [Firmware build and bridge](firmware-build-and-bridge.md) — CMake inputs and
  host/firmware boundaries.
- [Failure diagnosis](failure-diagnosis.md) — general evidence ladder.
- [Runtime and testing](runtime-and-testing.md) — test limits and evidence.
- [Performance](performance.md) — release measurements and physical timing.
- [Board and pin planning](board-and-pin-planning.md) — wiring records and
  alternate-function maps.
