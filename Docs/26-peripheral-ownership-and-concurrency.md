# PicoKit Documentation

## Chapter 26: Peripheral ownership and concurrency


Each hardware peripheral should have one logical owner.

Do not create competing active instances for:

- The same UART controller
- The same I2C controller
- The same SPI controller
- The same PWM slice
- The watchdog
- Shared USB stdio state

PicoKit peripheral instances do not implement synchronization. Use each instance from one foreground execution context. Do not call the same instance concurrently from multiple Swift tasks, cores, or interrupt handlers.

The `Pico` and `PicoSerial` types are marked `@unchecked Sendable` to permit embedded use, but this does not make their underlying hardware operations thread-safe.
