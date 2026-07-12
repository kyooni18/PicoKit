# PicoKit Documentation

## Chapter 26: Peripheral ownership and concurrency


Give each hardware peripheral one logical owner. It makes pin conflicts and
reconfiguration bugs much easier to reason about.

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
