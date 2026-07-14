# PicoKit performance measurement and fast paths

PicoKit's normal Swift APIs are intended for ordinary control logic. Use the
fast paths only after measuring a peripheral-bound workload:

- `PicoGPIO.set(mask:)`, `clear(mask:)`, and `toggle(mask:)` update several
  already-configured GPIO pins with one register operation.
- PWM and repeated ADC reads keep setup metadata in the bridge; create the
  peripheral once, then reuse it.
- `PicoSPI.writeDMA(_:)` and `PicoUART.writeDMA(_:)` synchronously send a
  prepared buffer through DMA. They are best for sufficiently large output
  buffers, not single-byte commands. Each peripheral retains its claimed DMA
  channel(s) between calls. Call `releaseDMAChannels()` on SPI or
  `releaseDMAChannel()` on UART when another subsystem needs those resources.
- Use hardware PWM, PIO, or focused C for cycle-critical waveforms, bit-banged
  protocols, and continuous capture. PicoKit deliberately has no PIO or
  asynchronous DMA API yet.

## Pico 2 W benchmark fixture

`Sources/Performance/main.swift` initializes USB CDC before its monitor grace
period, then emits one CSV record per measurement. It covers eight CPU loops,
single-pin and GPIO-mask toggles, scaled and raw-counter PWM updates, and
repeated-ADC timing.
Build it in Release mode for the RP2350 target, then flash and monitor it with
SwiftPico:

```sh
cmake -S Firmware -B Firmware/build-performance -G Ninja \
  -DPICO_BOARD=pico2_w \
  -DPICOKIT_PRODUCT=Performance \
  -DPICOKIT_SOURCE="$PWD/Sources/Performance/main.swift" \
  -DCMAKE_BUILD_TYPE=Release
cmake --build Firmware/build-performance --parallel
```

Flash `Firmware/build-performance/Performance.uf2` with SwiftPico or
`picotool`, then monitor USB CDC. GPIO tests measure software-side call cost;
confirm real edge timing separately with a logic analyzer when that is the
requirement.

USB output is bounded by `PICOKIT_USB_STDOUT_TIMEOUT_US`, which defaults to
10,000 microseconds. Override that CMake cache value when lossless diagnostic
logging is more important than keeping a control loop responsive.

The fixture intentionally does not drive SPI or UART DMA automatically because
their meaningful throughput test needs the application's selected baud/clock,
wiring, receiver, and buffer size. Benchmark those calls with a verified peer
or analyzer, recording both transfer duration and byte integrity. Do not claim
a DMA wall-time win when SPI clock or UART baud is the limiting factor.
