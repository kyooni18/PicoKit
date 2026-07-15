# PicoKit Documentation

## Runtime model, testing, and limits


Use the high-level facade (`Serial`, `pinMode`, `sleep`) for fixed sketches.
It traps on configuration failures. Use the throwing low-level APIs
(`USBSerial`, `PicoUART`, `PicoI2C`, and peers) in reusable drivers or whenever
timeouts and failures require recovery.

### Ownership and concurrency

Give each hardware peripheral one logical owner. It makes pin conflicts and
reconfiguration bugs easier to reason about.

Do not create competing active instances for:

- The same UART controller
- The same I2C controller
- The same SPI controller
- The same PWM slice
- The watchdog
- Shared USB stdio state

PicoKit peripheral instances do not implement synchronization. Use each instance
from one foreground execution context; do not call the same instance concurrently
from multiple Swift tasks, cores, or interrupt handlers.

`Pico` and `PicoSerial` are marked `@unchecked Sendable` so they are usable in
embedded Swift code, but that annotation does not make the underlying hardware
thread-safe.

### Host behavior and test seam

Host SwiftPM builds compile the public API without the Pico SDK. Hardware calls
normally throw `PicoKitError.unavailable("Pico SDK bridge")`; `Clock.now()` and
interrupt polling return `0`, while watchdog update is a no-op. PicoKit's host
executable tests core validation, GPIO fakes, serial buffering, and raw bytes.
Applications can test GPIO-dependent code with a `DigitalIO` fake passed to
`Pico(gpio:)`; the serial transport seam remains internal to PicoKit tests.

The C bridge is the only Pico SDK boundary. It exposes fixed-width operations
for GPIO, time, USB CDC, UART, PWM, ADC, I2C, SPI, interrupts, and watchdog.
USB CDC, UART, and SPI timeouts use saturating `time_us_64()` deadlines. I2C
uses Pico SDK timeout functions and rejects durations wider than `UInt32`
microseconds with `invalidTimeout`.

Run `swift build`, `swift run PicoKitHostTests`, and
`sh Tests/api-reference.sh` for host validation. The disposable firmware gate
is `sh Tests/integration/generated-project.sh`; generated CLI templates are
checked against the Embedded Swift module with
`sh Tests/integration/generated-templates.sh`; `sh Tests/integration/usb-disabled.sh`
covers the supported no-USB configuration; set `PICO_HARDWARE_TEST=1` only when
a connected board should also be flashed and byte-echo tested.
The in-tree entry point can also be built directly with
`sh Tests/integration/default-firmware.sh`; that gate intentionally leaves
`PICO_BOARD` unset and verifies the Pico SDK default-board path.
Use `PICO_TEST_BOARD=pico2` (or another matching board name) when running the
hardware gate against a Pico 2; BOOTSEL identity is checked before flashing.
The CI firmware job runs the complete `pico`, `pico_w`, `pico2`, and `pico2_w`
matrix plus the USB-disabled integration gate.

### Deliberate limits

PicoKit has no async scheduler, PIO, Wi-Fi/Bluetooth, USB device-class
configuration beyond stdio, multicore coordination, or runtime peripheral
ownership registry. Its DMA APIs are synchronous and limited to prepared
SPI/UART transfers. SPI mode and chip-select behavior are explicit in
`PicoSPI`; device-specific transaction policy, UART framing/buffering, ADC
voltage conversion, and line/protocol parsing remain the responsibility of
focused drivers. `PicoI2C.write(..., stop: false)` and
`PicoI2C.read(..., stop: false)` support repeated START sequences.
I2C reads and writes report a positive short result as `partialTransfer`.
GPIO interrupt events are
bit-coalesced, not counted.
