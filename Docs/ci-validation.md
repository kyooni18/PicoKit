# PicoKit CI validation

PicoKit CI has two different jobs because host portability and firmware
production prove different things. Keep those jobs separate when interpreting
failures, reproducing a run locally, or deciding whether a change is safe to
merge.

## Host validation job

The `host-validation` job runs on both Apple Silicon (`arm64`) and Intel
(`x86_64`) macOS runners. It checks the Foundation-free package behavior and
documentation without a Pico SDK, cross compiler, or connected board:

```sh
swift build
swift run PicoKitHostTests
sh Tests/gpio-facade-host.sh
swift build -c release
swift run -c release PicoKitHostTests
sh Tests/api-reference.sh
sh Tests/docs-consistency.sh
sh Tests/docs-links.sh
sh Tests/docs-links-fixture.sh
sh Tests/performance-fixture.sh
sh Tests/hardware-board-validation.sh
sh Tests/bridge-atomic.sh
sh Tests/bridge-validation.sh
sh Tests/bridge-module.sh
sh Tests/bridge-surface.sh
```

The debug and release host runs catch configuration differences that a single
build can miss. The architecture matrix catches accidental dependence on one
host ABI. A passing host job proves portable validation, typed errors, fakes,
symbol coverage, and source-level bridge contracts; it does not prove that an
Embedded Swift image links or boots.

## Firmware validation job

The `firmware-validation` job runs on arm64 macOS with the Embedded Swift
snapshot, CMake, Ninja, `arm-none-eabi-gcc`, the Pico SDK submodule, and the
SwiftPico checkout. Its gates are intentionally layered:

| Gate | Scope |
| --- | --- |
| `bridge-warnings.sh` for Pico and Pico 2 | strict C bridge warnings on both MCU families |
| `default-firmware.sh` | direct in-tree firmware build |
| `direct-cmake.sh` and `compiler-discovery.sh` | compiler and SDK discovery paths |
| `cmake-options.sh` | USB option spelling, bounds, and connection policy |
| `peripheral-pin-mux-validation.sh` | SDK headers, Swift maps, and C tables |
| SwiftPico firmware matrix | board/compiler combinations owned by the CLI repository |
| `generated-templates.sh` | all tracked templates typecheck against the built module |
| `generated-blink.sh` | board-aware LED behavior and wireless templates |
| `product-name.sh` | generated product naming and artifact paths |
| `usb-disabled.sh` | firmware without USB CDC |
| `usb-serial-status-firmware.sh` | disconnected/connected USB status and raw-byte fixture image |
| `generated-project.sh` for four boards | generated build, fake flash, and artifact checks |
| `performance-firmware.sh` | firmware benchmark fixture contract |
| `riscv-firmware.sh` | RP2350 RISC-V firmware path |

The four generated-project runs select `pico`, `pico_w`, `pico2`, and `pico2_w`.
This is a build matrix, not a claim that four physical boards were flashed.
The default generated-project gate uses a temporary project and fake picotool.

## Reproduce a failure locally

Run the narrowest matching gate first, then widen only if the boundary is
shared:

```sh
# Host/API/docs change
swift build
swift run PicoKitHostTests
sh Tests/api-reference.sh
sh Tests/docs-consistency.sh
sh Tests/docs-links.sh

# Bridge or board-map change
sh Tests/bridge-validation.sh
sh Tests/bridge-atomic.sh
sh Tests/peripheral-pin-mux-validation.sh
PICO_TEST_BOARD=pico2_w sh Tests/bridge-warnings.sh

# Generated firmware change
sh Tests/integration/generated-templates.sh
sh Tests/integration/generated-blink.sh
PICO_TEST_BOARD=pico2_w sh Tests/integration/generated-project.sh
sh Tests/integration/usb-serial-status-firmware.sh
```

If a gate depends on the SwiftPico checkout or a toolchain cache, preserve the
exact environment and command from CI. A local skip caused by a missing
compiler is not equivalent to a green CI gate.

## Hardware is never implicit in CI

`PICO_HARDWARE_TEST=1` is not set by the repository workflow. Physical flashing
is destructive and requires an explicitly owned board, BOOTSEL state, and
serial path. If a hardware job is created, make its scope visible and add
`PICO_HARDWARE_REQUIRE_CDC=1` when missing USB enumeration must fail:

```sh
PICO_TEST_BOARD=pico2_w \
PICO_HARDWARE_TEST=1 \
PICO_HARDWARE_REQUIRE_CDC=1 \
sh Tests/integration/generated-project.sh
```

The normal CI-generated-project gate proves UF2 production, board selection,
and fake flash arguments without touching a board. It cannot prove bootloader
acceptance, CDC enumeration, wiring, or external peripheral behavior.

## Read failures by job and layer

Use the first failed boundary as the diagnosis:

- host job compile/test failure: Swift API, portability, or host behavior;
- host documentation failure: missing link, stale source-backed statement, or
  undocumented public symbol;
- bridge warning or surface failure: C ABI, declaration, or warning drift;
- pin-mux failure: SDK header and Swift/C function maps disagree;
- direct firmware failure: toolchain, SDK, CMake, linker, or board target;
- generated-project failure: SwiftPico project wiring or artifact selection;
- RISC-V-only failure: RP2350 alternate compiler path;
- physical CDC failure: board identity, flash, USB enumeration, or monitor;
- peripheral failure: power, pin wiring, levels, timing, or protocol.

Do not rerun a passing host job to explain a firmware failure. Preserve the
first failed command and its complete output, then use [failure diagnosis](failure-diagnosis.md)
to choose the next layer.

## CI report minimum

For a release or merge report, record:

1. commit and workflow run;
2. job and architecture;
3. exact gate and command;
4. toolchain, SDK, and board variables when firmware is involved;
5. whether the run used fake flash or physical hardware;
6. skipped gates and the reason;
7. the strongest claim the evidence actually supports.

This keeps a green host matrix from being reported as hardware validation and
makes a future failure reproducible.

## Related documents

- [Release readiness](release-readiness.md) — reproducible release inputs and
  evidence claims.
- [Hardware validation](hardware-validation.md) — fake, firmware, USB, and
  physical evidence levels.
- [Firmware build and bridge](firmware-build-and-bridge.md) — CMake and
  toolchain boundaries.
- [Peripheral pin validation](peripheral-pin-validation.md) — map agreement.
- [Failure diagnosis](failure-diagnosis.md) — layer-by-layer triage.
