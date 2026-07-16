# PicoKit integration and performance

PicoKit keeps its own `PicoKitSDKBridge` private to the hardware abstraction
layer. Firmware applications import third-party C and C++ libraries through
project-owned adapters under `Firmware/Interop`; third-party headers never need
to be added to PicoKit's bridging header.

New SwiftPico projects use:

```text
Firmware/
  dependencies.json
  dependencies.lock
  Generated/Dependencies.cmake
  Dependencies.local.cmake
  Interop/
    AppInterop.h
    AppInterop.c
    Callbacks.h
    Modules/<Library>/module.modulemap
```

`dependencies.json` is editable user intent. `dependencies.lock` records exact
Git commits and toolchain compatibility. Generated CMake is read-only. Run
`swiftpico dependencies resolve` after changing intent; ordinary builds only
regenerate CMake from the existing lock and never select a newer revision.

## Clang modules

Put a module map and its public adapter header in a unique directory:

```text
Firmware/Interop/Modules/ST7789/
  ST7789Adapter.h
  module.modulemap
```

```modulemap
module ST7789Adapter {
  header "ST7789Adapter.h"
  export *
}
```

Then use `import ST7789Adapter` in application Swift. PicoKit discovers all
application module maps, rejects duplicate module names, and passes them only
to the application Swift target.

## Bridging fallback and callbacks

Use `AppInterop.h` as the application umbrella header when configuration-header
ordering or platform headers make a standalone module impractical. Normalize
function-like macros behind C adapter functions; importing a header does not
turn arbitrary C macros into a stable Swift API.

Declare callbacks implemented by Swift in `Callbacks.h`. Implement the exact C
signature with the toolchain's C-export annotation. `swiftpico doctor` compiles
a Swift callback, a C caller, and their combined object instead of trusting a
version number.

Keep the ABI to fixed-width integers, simple enums and structs, pointer-length
pairs, opaque handles, and explicit status codes. C++ classes stay behind
`extern "C"` adapters with explicit create/destroy functions. Avoid exceptions,
RTTI, OS dependencies, and ownership hidden in global constructors.

Legacy `Firmware/Dependencies.cmake` remains supported. Run
`swiftpico dependencies migrate` to create the v0.2 structure without deleting
that file, migrate one entry at a time, and remove the legacy file only after
the generated build matches.

## Migration and fast paths

Existing initializers, Arduino-style GPIO calls, and legacy
`Firmware/Dependencies.cmake` continue to build. Move a project deliberately:

```sh
swiftpico dependencies migrate
swiftpico dependencies resolve
swiftpico build
```

Commit `Package.resolved`, `Firmware/dependencies.json`,
`Firmware/dependencies.lock`, and `Firmware/Generated/Dependencies.cmake`.
Do not commit `Firmware/Dependencies.local.cmake`.

For displays and other bulk SPI output, configure `PicoSPI` with an optional
chip select, then use `writeDMA` for a prepared buffer. `transferDMA` needs a
configured MISO pin and returns received frames. Both are synchronous and their
timeout overloads abort retained channels before returning. Use
`releaseDMAChannels()` (or UART's `releaseDMAChannel()`) when the resource is
no longer needed.

## Performance measurement

Measure before choosing a fast path. GPIO masks update several configured pins
with one operation; PWM and repeated ADC reads reuse setup metadata; DMA lowers
per-byte CPU work but SPI clock or UART baud can still limit wall time. Use PIO
or focused C for cycle-critical waveforms and continuous capture.

`Sources/Performance/main.swift` is a Pico 2 W benchmark fixture. It emits one CSV record per measurement
(`metric,iterations,elapsed_us,check`) for CPU,
GPIO, PWM, and ADC loops. Build it in Release mode, flash it, and verify GPIO
edge timing separately with a logic analyzer when physical timing matters.
`PICOKIT_USB_STDOUT_TIMEOUT_US` defaults to 10,000 microseconds; increase it
when lossless diagnostics matter more than a responsive control loop.
