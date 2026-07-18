# PicoKit build-cache hygiene

PicoKit development can involve several independent caches: SwiftPM host
artifacts, a CMake firmware build directory, a generated SwiftPico project,
and the shared Pico SDK cache. A stale result in one layer can look like a
source or toolchain failure in another. Identify the layer before cleaning so
the original evidence is not lost.

## Know which cache you are looking at

| Location or setting | Owner | Typical contents |
| --- | --- | --- |
| `.build` | SwiftPM | host modules, products, and symbol graphs |
| `Firmware/build*` | CMake/Ninja | cache, objects, ELF, UF2, and generated firmware metadata |
| generated project `Firmware/build` | SwiftPico project | project-specific CMake state and artifacts |
| `SWIFTPICO_CACHE_DIR` | SwiftPico | shared Pico SDK/toolchain cache |
| `Vendor/pico-sdk` | repository submodule | pinned SDK source, not a disposable build cache |

Do not edit generated files below `Firmware/build`, and do not delete or
modify `Vendor/pico-sdk` as a first response to a firmware failure. Record the
SDK revision, CMake cache, board, compiler, and command before changing state.

## Read the symptom before cleaning

Use this triage order:

1. If a changed Swift source is not rebuilt, inspect the package target and
   source path before cleaning `.build`.
2. If CMake reports the wrong board, compiler, SDK, or USB option, inspect
   `Firmware/build/CMakeCache.txt`; an existing cache may retain an old value.
3. If a generated project builds a stale product or UF2, run `swiftpico info`
   and compare the resolved product and artifact path with the image being
   inspected.
4. If several projects disagree about the SDK, inspect `SWIFTPICO_CACHE_DIR`
   and the pinned revision before rebuilding every project.
5. If only one bridge warning or symbol is wrong, preserve the build output and
   reproduce with the focused bridge gate before cleaning.

A clean build can hide the transition that explains a failure. Keep the first
failed command and relevant cache values in the diagnostic record.

## Safe host rebuilds

For ordinary PicoKit host changes, the incremental path is enough:

```sh
swift build
swift run PicoKitHostTests
```

Use a release build when the change touches optimization, `@testable` coverage,
or performance:

```sh
swift build -c release
swift run -c release PicoKitHostTests
```

The host package does not require the Pico SDK or firmware CMake cache. Do not
clean firmware output to diagnose a pure host API failure. Run the API and
documentation gates alongside the relevant build instead:

```sh
sh Tests/api-reference.sh
sh Tests/docs-consistency.sh
sh Tests/docs-links.sh
```

## Reconfigure firmware deliberately

For an in-tree direct CMake build, use a named build directory for each
materially different configuration:

```sh
cmake -S Firmware -B Firmware/build-pico2 -G Ninja \
  -DPICO_SDK_PATH=/path/to/pico-sdk \
  -DPICO_BOARD=pico2
cmake --build Firmware/build-pico2 --parallel
```

Keep separate directories for board families, USB-disabled images, and
performance fixtures. Reusing one directory for `pico` and `pico2` can leave
the cache and generated files describing a different target than the source
command suggests. Inspect `CMakeCache.txt` and the final ELF/UF2 path before
flashing.

The project-owned `Firmware/build` directory is generated output. Stable CMake
inputs belong in `Firmware/CMakeLists.txt` or the project configuration, not in
hand-edited cache files.

## Clean generated firmware safely

For a generated SwiftPico project, use its supported command:

```sh
./swiftpico info
./swiftpico clean
./swiftpico build
```

`clean` removes generated firmware build products for that project. It does not
change the source package or prove that the next image uses the intended SDK;
inspect `info` and the build output afterward. If the project itself is
disposable, create a fresh temporary project and compare its resolved
configuration rather than mutating the original while diagnosing it.

## Shared SDK cache discipline

SwiftPico reuses the SDK revision required by PicoKit. Set
`SWIFTPICO_CACHE_DIR` to a deliberate shared location in CI or on a shared
machine, and record it when reproducing a build:

```sh
SWIFTPICO_CACHE_DIR=/path/to/sdk-cache swiftpico doctor
SWIFTPICO_CACHE_DIR=/path/to/sdk-cache swiftpico build
```

An SDK cache hit is not proof that the revision is correct; verify the resolved
revision and board configuration. If the SDK cache appears corrupt, preserve
the path and error output, then let the tool's documented cache-management
workflow repair or repopulate it. Do not replace the PicoKit submodule or
silently switch to a system SDK.

## Compare artifacts, not just timestamps

Before flashing or reporting a firmware result, verify:

- selected `PICO_BOARD` and inferred `PicoChip`;
- SDK revision and compiler path;
- product name and exact ELF/UF2 path;
- USB CMake options when serial behavior matters;
- PicoKit commit and application source revision.

Use `swiftpico info` for generated-project resolution and record the artifact
path. A newer timestamp can still point to an older product if multiple build
directories or projects exist.

## Validate after cleaning

After a cache reset or new build directory, rerun the boundary that motivated
the clean:

```sh
swift build
swift run PicoKitHostTests
sh Tests/bridge-validation.sh
sh Tests/peripheral-pin-mux-validation.sh
sh Tests/integration/generated-project.sh
```

Add `generated-templates.sh`, `generated-blink.sh`, or the board-specific
firmware gate when the change touches generated source or board selection. A
clean build proves reproducibility for that run; it does not prove hardware
boot or external-device behavior.

## Swift module cache location

Firmware CMake builds keep Clang and Swift module artifacts under the selected
build directory so a read-only global Swift cache cannot prevent compilation.
For a shared CI cache, set `PICOKIT_SWIFT_MODULE_CACHE` to a writable directory
before configuring. The default is disposable and is removed with the rest of
the temporary build tree.

## Related documents

- [Firmware build and bridge](firmware-build-and-bridge.md) — CMake inputs and
  artifact paths.
- [Getting started](getting-started.md) — everyday project commands.
- [Failure diagnosis](failure-diagnosis.md) — preserve evidence and classify
  the first failed layer.
- [CI validation](ci-validation.md) — clean job boundaries and matrix gates.
- [Release readiness](release-readiness.md) — record reproducible inputs.
