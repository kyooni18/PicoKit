# External C and C++ libraries

PicoKit keeps its SDK bridge private. A firmware project owns third-party
headers, adapters, callbacks, and build dependencies below `Firmware`, keeping
vendor-specific APIs out of PicoKit itself.

## Dependency files

Generated SwiftPico projects separate editable intent from resolved state:

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

| File | Purpose | Commit? |
|---|---|---|
| `dependencies.json` | Requested repositories, revisions, and build intent | Yes |
| `dependencies.lock` | Exact commits and compatibility result | Yes |
| `Generated/Dependencies.cmake` | Reproducible generated CMake wiring | Yes |
| `Dependencies.local.cmake` | Machine-local paths and overrides | No |

After editing intent, resolve and build:

```sh
swiftpico dependencies resolve
swiftpico build
```

Ordinary builds regenerate CMake from the lockfile and do not silently select
a newer revision.

## Clang modules

Give each imported adapter its own module-map directory:

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

Application Swift can then `import ST7789Adapter`. Module names must be unique.
Only the application target receives these module maps; PicoKit's private SDK
bridge remains isolated.

## C adapter shape

Prefer fixed-width values, pointer-length pairs, opaque handles, and explicit
status codes:

```c
#pragma once
#include <stdint.h>

typedef struct DisplayHandle DisplayHandle;

DisplayHandle *display_create(void);
void display_destroy(DisplayHandle *handle);
int32_t display_write(
    DisplayHandle *handle,
    const uint8_t *bytes,
    uint32_t count
);
```

Wrap function-like macros behind real C functions. Document whether a null
pointer is accepted for a zero-length buffer, who owns returned memory, and
whether a call retains pointers after returning.

## C++ libraries

Keep C++ classes behind `extern "C"` create/destroy/operation functions. Do not
expose templates, overloaded functions, exceptions, RTTI, standard-library
containers, or ownership hidden in global constructors across the Swift ABI.
Catch any C++ exception inside the adapter and convert it into an explicit
status code.

## Callbacks into Swift

Declare callbacks in `Callbacks.h`, then implement the exact C signature using
the Embedded Swift toolchain's C-export annotation. A C caller must not retain
Swift-owned memory beyond the documented lifetime, and errors must be converted
to C-compatible status values before crossing the boundary.

`swiftpico doctor` checks callback interoperability by compiling a Swift
callback, a C caller, and their combined object. This is stronger than assuming
support from a toolchain version string.

## Umbrella-header fallback

Use `AppInterop.h` when vendor configuration headers require strict include
ordering or a standalone Clang module is impractical. Keep the umbrella narrow:
it should expose project adapters, not every private vendor header.

## Dependency review checklist

Before merging a dependency change, inspect the URL or local path, exact
revision, archive checksum, selected integration mode, include directories,
configuration headers, compile definitions, and board conditions. Then review
both `dependencies.lock` and `Generated/Dependencies.cmake`. A dependency that
builds on one host but is not represented in those files is not reproducible.

Keep the application ABI smaller than the vendor API. A C adapter should expose
fixed-width values, pointer-plus-length buffers, opaque handles, and explicit
status codes. A C++ adapter should own construction/destruction and catch
exceptions before crossing into Swift.

## Migrating legacy projects

Legacy `Firmware/Dependencies.cmake` remains supported. Migrate deliberately:

```sh
swiftpico dependencies migrate
swiftpico dependencies resolve
swiftpico build
```

The migration does not delete the legacy file. Move and validate one dependency
at a time, compare generated targets and sources, then remove the legacy file
only after the firmware result matches.
