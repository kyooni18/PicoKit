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

### C adapter example

Expose a stable C-shaped surface instead of importing vendor macros directly.
For example, put a public declaration in `ST7789Adapter.h`:

```c
#pragma once
#include <stdint.h>

void st7789_write_pixels(const uint8_t *bytes, uint32_t count);
```

Implement it in a project-owned `.c` file that includes the vendor header and
performs any macro or configuration translation. Swift then sees a simple,
reviewable function:

```swift
import ST7789Adapter

pixels.withUnsafeBufferPointer { buffer in
    st7789_write_pixels(buffer.baseAddress, UInt32(buffer.count))
}
```

For empty buffers, avoid passing an invalid pointer; make the C adapter's
zero-length policy explicit. Keep vendor-specific data structures and lifetime
rules inside the adapter rather than spreading them across application Swift.

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

### C++ adapters and callbacks

C++ libraries need a C ABI boundary. Keep class ownership explicit with create,
destroy, and operation functions; do not expose exceptions, RTTI, templates, or
C++ standard-library types to Swift:

```c
typedef struct DisplayHandle DisplayHandle;
DisplayHandle *display_create(void);
void display_destroy(DisplayHandle *handle);
int32_t display_flush(DisplayHandle *handle, const uint8_t *bytes, uint32_t count);
```

For callbacks from C into Swift, declare the exact function signature in
`Callbacks.h` and use the Embedded Swift toolchain's C-export annotation on the
Swift implementation. Prefer fixed-width integers, pointer-length pairs,
opaque handles, and integer status codes. The callback must not allow a Swift
error or exception-like control flow to cross the C ABI.

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

### Dependency workflow

Treat the dependency files as different kinds of state:

| File | Role | Commit? |
|---|---|---|
| `dependencies.json` | Human-maintained dependency intent | Yes |
| `dependencies.lock` | Exact revisions and compatibility result | Yes |
| `Generated/Dependencies.cmake` | Reproducible generated build wiring | Yes |
| `Dependencies.local.cmake` | Machine-specific local override | No |

After changing `dependencies.json`, run `swiftpico dependencies resolve`,
inspect the lockfile and generated CMake, then build before committing. A normal
`swiftpico build` reuses the lockfile; it does not silently upgrade a library.
That separation keeps a firmware build reviewable and reproducible.

## Performance measurement

Measure before choosing a fast path. GPIO masks update several configured pins
with one operation; PWM and repeated ADC reads reuse setup metadata; DMA lowers
per-byte CPU work but SPI clock or UART baud can still limit wall time. Use PIO
or focused C for cycle-critical waveforms and continuous capture.

`Sources/Performance/main.swift` is a benchmark fixture for every supported Pico board. It emits one CSV record per measurement
(`metric,iterations,elapsed_us,check`) for CPU,
GPIO, PWM, and ADC loops. Build it in Release mode, flash it, and verify GPIO
edge timing separately with a logic analyzer when physical timing matters.
Comment-prefixed metadata records the compiled board, chip, format version,
and iteration count at the start of every capture.
The fixture waits for one host byte before each run, preventing USB enumeration
from racing the first record and allowing repeated samples without reflashing.
`PICOKIT_USB_STDOUT_TIMEOUT_US` defaults to 10,000 microseconds; increase it
when lossless diagnostics matter more than a responsive control loop.

### Running the benchmark fixture

The fixture is deliberately a starting point rather than a universal throughput
claim. Build it for the selected board in Release mode, flash it, and capture
the CSV stream with `swiftpico monitor --reconnect`. Compare runs with the same
CPU clock, CMake settings, wiring, and monitor configuration.

```sh
cmake -S Firmware -B Firmware/build-performance -G Ninja \
  -DPICO_BOARD=pico2_w \
  -DPICOKIT_PRODUCT=Performance \
  -DPICOKIT_SOURCE="$PWD/Sources/Performance/main.swift" \
  -DPICOKIT_USB_STDOUT_TIMEOUT_US=1000000 \
  -DCMAKE_BUILD_TYPE=Release
cmake --build Firmware/build-performance --parallel
```

GPIO measurements report software-side call cost, not necessarily the physical
edge time. Validate a waveform with a logic analyzer. SPI DMA throughput needs
a correctly wired receiver or analyzer; UART DMA needs a known baud rate and
peer. Record byte integrity alongside duration, because a fast transfer with a
bad setup is not a useful result.
