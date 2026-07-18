# PicoKit firmware build and bridge boundary

PicoKit has two related but different build surfaces:

1. SwiftPM builds the portable Swift API and host validation executable.
2. CMake builds a firmware image, selects the Pico SDK and Embedded Swift
   target, compiles the application, and links the SDK bridge.

The first surface is fast and reproducible on the host. The second is the
proof that an application can become a board-specific ELF and UF2. A passing
host build is not a firmware build and does not exercise Pico SDK headers,
cross-compilation, linker scripts, USB startup, or board pin muxing.

## The source layers

The normal dependency direction is:

```text
application Swift sources
          │ import PicoKit
          ▼
PicoKit facade ── PicoKitHAL ── PicoKitCore
          │
          │ fixed-width C ABI calls
          ▼
PicoKitSDKBridge.c + PicoKitGPIOFacade.c
          │
          ▼
Pico SDK, board support, linker, UF2
```

`PicoKitCore` contains Foundation-free values, units, errors, and the
`DigitalIO` protocol. `PicoKitHAL` contains the hardware-facing Swift types.
`Sources/PicoKitFacade` exports the single `PicoKit` module imported by an
application. `Firmware/PicoKitSDKBridge.c` and
`Firmware/PicoKitGPIOFacade.c` are the only PicoKit C sources that include SDK
headers.

Keeping the bridge narrow has two consequences:

- host SwiftPM builds can compile and test declarations without a Pico SDK;
- firmware Swift sees fixed-width C functions instead of SDK macros, inline
  functions, or register layouts.

Application-owned C and C++ libraries belong in a generated project's
`Firmware/Interop` boundary. Do not add a vendor header to PicoKit's private
bridge merely because one application needs it.

## Host validation

From a PicoKit checkout, run the package build and executable host validation:

```sh
swift build
swift run PicoKitHostTests
```

The package manifest defines three library layers and a Foundation-free
`PicoKitHostTests` executable. Host hardware calls intentionally report
`PicoKitError.unavailable("Pico SDK bridge")`; host tests can still cover value
validation, error conversion, overloads, fake GPIO, serial buffering, and
source-level API shape.

Use this path first for a Swift-only change. It cannot prove that an Embedded
Swift compiler accepts the source, that the bridge links, or that the selected
board starts.

## Firmware inputs

`Firmware/CMakeLists.txt` accepts these important inputs:

| Input | Purpose | Default or selection |
| --- | --- | --- |
| `PICOKIT_ROOT` | Reusable PicoKit checkout containing `Sources` and `Firmware` | Firmware directory's parent when building in-tree |
| `PICO_SDK_PATH` | Pico SDK checkout | `PICO_SDK_PATH` environment value, then `Vendor/pico-sdk` if present |
| `PICO_BOARD` | SDK board and compiled-board identity | SDK default `pico` when omitted |
| `PICO_PLATFORM` | RP2350 ARM/RISC-V platform selection | SDK default unless explicitly set |
| `PICOKIT_PRODUCT` | Firmware target and output basename | `PicoKitFirmware` |
| `PICOKIT_SOURCE` | Entry-point hint and source-directory anchor | `Sources/Blink/main.swift` |
| `PICOKIT_SOURCES` | Explicit Swift source list | Recursive Swift files below `PICOKIT_SOURCE`'s directory |
| `PICOKIT_ENABLE_USB` | USB CDC/reset interface | `ON` |

The supported board identifiers are `pico`, `pico_w`, `pico2`, and `pico2_w`.
The CMake file maps them to the runtime `PicoBoard.compiled` identity so
`BoardLED` and explicit chip checks can reject a mismatch instead of silently
using another target.

`PICOKIT_SOURCE` is retained as a backwards-compatible entry-point hint. A
normal application directory is compiled recursively, so helper Swift files
can sit beside `main.swift`. Set `PICOKIT_SOURCES` only when an integration
needs an intentional source selection.

## Direct CMake build

For a direct firmware investigation, use the same source and board values that
the generated project resolved:

```sh
cmake -S Firmware -B Firmware/build -G Ninja \
  -DPICOKIT_ROOT="$PWD" \
  -DPICO_SDK_PATH="$PWD/Vendor/pico-sdk" \
  -DPICO_BOARD=pico2_w \
  -DPICOKIT_PRODUCT=Diagnostic \
  -DPICOKIT_SOURCE="$PWD/Sources/Blink/main.swift" \
  -DPICOKIT_ENABLE_USB=ON
cmake --build Firmware/build --parallel
```

This requires CMake 3.29 or newer, Ninja, a matching Pico SDK, an Embedded
Swift compiler, and the SDK's cross compiler. If `Vendor/pico-sdk` is not
present, pass the real SDK path explicitly or let SwiftPico resolve its shared
cache.

The resulting files are named from `PICOKIT_PRODUCT`:

```text
Firmware/build/Diagnostic.elf
Firmware/build/Diagnostic.uf2
```

Do not assume the product is always `PicoKitFirmware`; generated projects and
performance fixtures intentionally select their own product names. Inspect
the generated project or use `swiftpico info` to find the authoritative UF2.

## Compiler selection

When CMake does not receive `CMAKE_Swift_COMPILER`, PicoKit follows its local
discovery path: an explicit `PICOKIT_SWIFT_COMPILER`, then `PICO_SWIFTC`, then
the newest matching development snapshot under `SWIFTLY_TOOLCHAINS_DIR` or
the user's Developer Toolchains directory, then a directly installed
`SWIFTLY_BIN_DIR/swiftc`. An explicit compiler path must exist and be
executable.

For reproducible diagnosis, print and retain the compiler path rather than
assuming the host `swiftc` is an Embedded Swift compiler:

```sh
PICOKIT_SWIFT_COMPILER=/path/to/embedded/swiftc \
cmake -S Firmware -B Firmware/build -G Ninja \
  -DPICOKIT_ROOT="$PWD" \
  -DPICO_BOARD=pico \
  -DPICOKIT_SOURCE="$PWD/Sources/Blink/main.swift"
```

The CMake file marks the compiler probe usable before enabling Swift because a
host link probe is not valid for an Embedded Swift bare-metal target. The real
firmware target still compiles and links with the selected embedded compiler;
the probe bypass is not a firmware-success claim.

## Board and target architecture

The board selects the chip family and usually the ARM target. For RP2350, the
firmware can be built for the supported platform selected by the SDK. The
CMake logic chooses these Swift target/ABI values:

| Configuration | Swift target | ABI detail |
| --- | --- | --- |
| RP2040 / default ARM | `armv6m-none-none-eabi` | soft-float C flags |
| RP2350 ARM-S | `armv7em-none-none-eabi` | soft-float C flags |
| RP2350 RISC-V | `riscv32-none-none-eabi` | `rv32imac_zicsr_zifencei_zba_zbb_zbs_zbkb`, `ilp32` |

Keep `PICO_BOARD`, `PICO_PLATFORM`, SwiftPico's project board, and any explicit
`PicoBoard`/`PicoChip` declaration aligned. A host build cannot catch a board
metadata mismatch that only appears when the bridge compares its compiled chip
or board identity.

## USB build options

USB CDC is enabled by default and is configured through CMake cache values:

| Option | Default | Behavior |
| --- | ---: | --- |
| `PICOKIT_ENABLE_USB` | `ON` | Initialize/link USB CDC and reset interface |
| `PICOKIT_USB_STDOUT_TIMEOUT_US` | `10000` | Maximum time a CDC output operation may block |
| `PICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS` | `0` | `0` means no wait; positive values bound startup wait; `-1` waits indefinitely |
| `PICOKIT_USB_POST_CONNECT_WAIT_DELAY_MS` | `50` | Additional settle delay after host connection |
| `PICOKIT_USB_CONNECTION_WITHOUT_DTR` | `OFF` | When `ON`, connection readiness does not require DTR |

For a firmware image that must boot without USB, disable the interface
explicitly:

```sh
cmake -S Firmware -B Firmware/build-no-usb -G Ninja \
  -DPICOKIT_ROOT="$PWD" \
  -DPICO_BOARD=pico \
  -DPICOKIT_SOURCE="$PWD/Sources/Blink/main.swift" \
  -DPICOKIT_ENABLE_USB=OFF
cmake --build Firmware/build-no-usb --parallel
```

Disabling USB does not turn `Serial` into a UART. USB calls remain unavailable
or nonfunctional according to the selected API path; use `PicoUART` with valid
hardware UART pins when a physical serial link is required.

The CMake validation rejects malformed, negative, or out-of-range option
values before SDK setup. Keep option values in the build record because they
change startup timing and the meaning of serial evidence.

## Generated SwiftPico projects

For normal application work, use the companion SwiftPico CLI so project
metadata, SDK resolution, firmware build, flash, and monitor commands stay
consistent:

```sh
swiftpico doctor
swiftpico init --board pico2_w --name Diagnostic --template serial
cd Diagnostic
./swiftpico info
./swiftpico build
./swiftpico flash
./swiftpico monitor --reconnect
```

The generated `swiftpico.json` records the board, firmware directory, PicoKit
source/version, product, UF2 path, and tool overrides. The project-owned
`Firmware` directory is the right place for stable CMake and `Interop` changes;
do not edit generated files below `Firmware/build`.

Use direct CMake when isolating a CMake, compiler, SDK, or bridge failure. Use
the CLI when proving the user workflow, because a direct build does not prove
that SwiftPico resolved the same project metadata or flash artifact.

## Bridge linkage and application C/C++

The SDK libraries are private to `PicoKitSDKBridge`. The final firmware target
links the bridge and Swift library without forwarding all SDK compile options
and definitions into every Swift consumer. This keeps SDK C-only flags out of
the embedded Swift compile command.

Application-owned C/C++ code follows a separate path:

```text
Firmware/Interop/
  AppInterop.h
  AppInterop.c
  Modules/Device/module.modulemap
```

Use a C-shaped adapter for vendor macros and a C ABI adapter for C++ classes.
Keep fixed-width integers, pointer-length buffers, opaque handles, explicit
status codes, and create/destroy ownership at that boundary. Do not include a
vendor header in `PicoKitSDKBridge.c` or expose C++ exceptions and templates to
Swift. See [external libraries](external-libraries.md) and [integration notes](integration.md)
for dependency lock and module-map workflows.

## Evidence and troubleshooting

Diagnose in this order:

| Observation | Strongest conclusion |
| --- | --- |
| `swift build` passes | Host Swift declarations compile |
| `swift run PicoKitHostTests` passes | Portable validation and host error paths pass |
| CMake configure passes | SDK path, board metadata, and project inputs are accepted |
| `.elf` and `.uf2` are non-empty | Firmware compiled and linked for the selected target |
| Flash reports the intended UF2 loaded | Image reached a selected BOOTSEL device |
| USB CDC emits expected bytes | Firmware started and the USB path exchanged data |
| External device responds or waveform matches | Physical pin/power/protocol path works |

If a host build fails, do not start with wiring. If CMake cannot find the SDK or
compiler, fix tool discovery. If firmware builds but USB is silent, inspect
USB options and monitor timing before changing a peripheral pin. If USB works
but an external device is silent, move to the relevant bus, electrical, and
logic-analyzer checks.

## Repository verification

For a PicoKit source change, use the narrowest relevant checks first and then
the full source-backed gates:

```sh
swift build
swift run PicoKitHostTests
sh Tests/docs-links.sh
sh Tests/docs-consistency.sh
sh Tests/api-reference.sh
sh Tests/bridge-validation.sh
sh Tests/bridge-atomic.sh
sh Tests/integration/generated-project.sh
```

The generated-project and hardware-flash sections are intentionally separate:
the normal integration script verifies a disposable firmware build and fake
flash arguments, while physical proof requires an explicitly owned board.

## Related documents

- [Getting started](getting-started.md) — first project, CLI, flash, and monitor.
- [Failure diagnosis](failure-diagnosis.md) — layer-by-layer failure evidence.
- [External libraries](external-libraries.md) — C/C++ adapter and module rules.
- [Runtime and testing](runtime-and-testing.md) — host versus firmware limits.
- [Integration notes](integration.md) — dependency, ABI, and performance details.
