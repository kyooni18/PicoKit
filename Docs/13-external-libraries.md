# External libraries

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
