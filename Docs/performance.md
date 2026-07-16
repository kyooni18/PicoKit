# Performance and fast paths

PicoKit's ordinary APIs are intended for control logic. Choose a fast path
only after measuring the actual workload with a Release firmware build.

## Available fast paths

- `PicoGPIO.set(mask:)`, `clear(mask:)`, and `toggle(mask:)` update several
  configured pins with one register operation.
- `PicoPWM.setCounterLevel(_:)` skips duty-fraction scaling when the caller
  already has counter units.
- Reusing a `PicoADC` instance and channel avoids repeated setup work.
- `PicoSPI.writeDMA`, `PicoSPI.transferDMA`, and `PicoUART.writeDMA` reduce
  per-byte CPU work for sufficiently large prepared buffers.
- Hardware PWM, PIO, or focused C is appropriate for cycle-exact waveforms,
  continuous capture, and tightly timed protocols.

DMA calls are synchronous. SPI remains limited by its configured clock and
UART by its baud rate. Retained DMA channels are a finite shared resource; call
`releaseDMAChannels()` or `releaseDMAChannel()` when the peripheral no longer
needs them.

## Benchmark fixture

`Sources/Performance/main.swift` emits records in this form:

```text
metric,iterations,elapsed_us,check
cpu.add,100000,1234,100000
...
complete,0,0,0
```

It covers CPU loops, single-pin and masked GPIO toggles, scaled and raw-counter
PWM updates, and repeated ADC reads. The `check` value prevents the optimizer
from deleting the measured work and helps detect obviously invalid runs.

## Release build

Build the fixture for Pico 2 W with optimization enabled:

```sh
cmake -S Firmware -B Firmware/build-performance -G Ninja \
  -DPICO_BOARD=pico2_w \
  -DPICOKIT_PRODUCT=Performance \
  -DPICOKIT_SOURCE="$PWD/Sources/Performance/main.swift" \
  -DCMAKE_BUILD_TYPE=Release
cmake --build Firmware/build-performance --parallel
```

Flash `Firmware/build-performance/Performance.uf2`, then capture output with
`swiftpico monitor --reconnect`. Keep board, CPU clock, SDK/PicoKit revision,
CMake values, wiring, and monitor settings constant when comparing runs.

## USB logging effects

The fixture initializes USB CDC before its monitor grace period and emits one
record per measurement. `PICOKIT_USB_STDOUT_TIMEOUT_US` defaults to 10,000
microseconds, preventing a missing host from blocking a control loop forever.
Increase it only when lossless diagnostics matter more than responsiveness.

Do not include USB printing inside the timed region. Store the result, then
print it after the measurement finishes.

## Physical validation

GPIO timings in the CSV describe software-side call cost. Measure actual edge
spacing, pulse width, and jitter with a logic analyzer. PIO or C may still be
required even when a Swift call benchmark looks fast enough.

SPI and UART DMA are intentionally absent from the automatic fixture because a
meaningful test needs selected wiring, clock/baud, buffer size, and a verified
receiver. Record both elapsed time and byte integrity. A shorter duration is
not an improvement if frames are lost or the receiver cannot keep up.

## Reading surprising results

Compare the generated code path and amount of work before attributing a result
to the language. A higher-level GPIO helper may be faster after inlining if it
reaches a direct bridge fast path, while a supposedly lower-level measurement
may construct values or perform validation inside every iteration. Move setup
outside the timed loop, consume results, rerun several times, and explain any
remaining difference from the actual call path.
