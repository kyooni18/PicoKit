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
# ready=send-one-byte
# format=picokit-performance-v1
# chip=rp2350
# board=pico2_w
# iterations=100000
metric,iterations,elapsed_us,check
cpu.add,100000,1234,100000
...
complete,0,0,0
```

Lines beginning with `#` are run metadata. Keep them with the CSV when
archiving results; they identify the format, compiled chip and board, and the
iteration count without relying on the capture filename.

After opening the monitor, send exactly one byte (for example `r`) to start a
run. The fixture prints `complete,0,0,0`, returns to the ready prompt, and waits
for another byte. This handshake prevents startup output from racing USB
enumeration and allows repeated samples without rebuilding or reflashing.

It covers CPU loops, counterbalanced single-pin and masked GPIO toggles, scaled
and raw-counter PWM updates, and repeated ADC reads. The second GPIO pair runs
in the opposite order so ordering effects are visible. The `check` value prevents the optimizer
from deleting the measured work and helps detect obviously invalid runs.

## Release build

Build the fixture for the selected Pico board with optimization enabled (Pico
2 W is shown here):

```sh
cmake -S Firmware -B Firmware/build-performance -G Ninja \
  -DPICO_BOARD=pico2_w \
  -DPICOKIT_PRODUCT=Performance \
  -DPICOKIT_SOURCE="$PWD/Sources/Performance/main.swift" \
  -DPICOKIT_USB_STDOUT_TIMEOUT_US=1000000 \
  -DCMAKE_BUILD_TYPE=Release
cmake --build Firmware/build-performance --parallel
```

Flash `Firmware/build-performance/Performance.uf2`, then capture output with
`swiftpico monitor --reconnect` and type `r` once per sample. Keep board, CPU clock, SDK/PicoKit revision,
CMake values, wiring, and monitor settings constant when comparing runs.

## USB logging effects

The fixture initializes USB CDC before waiting for its host byte and emits one
record per measurement. `PICOKIT_USB_STDOUT_TIMEOUT_US` defaults to 10,000
microseconds for ordinary firmware, preventing a missing host from blocking a
control loop forever. The benchmark command raises it to one second because
complete diagnostic records matter more than responsiveness and the handshake
guarantees an attached reader.

The fixture waits for `Serial.connected` before advertising readiness. The
default DTR-dependent connection check prevents output from being accepted
before a monitor has actually opened CDC, so records need no artificial pacing.
If that monitor disconnects before requesting a run, the fixture leaves the
input wait and advertises readiness again after the next DTR connection.

The GPIO section also emits
`gpio.counterbalanced,single1,mask1,mask2,single2`. Keeping all four elapsed
times in one short USB packet makes order-effect analysis robust even when a
host serial stack drops an earlier diagnostic record.

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
