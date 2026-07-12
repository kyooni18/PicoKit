# PicoKit Documentation

## Chapter 29: Current limitations


PicoKit intentionally stays small enough to understand. That means a few things
are still left to application code or a focused driver:

- No asynchronous API or scheduler integration
- Blocking sleep and peripheral operations
- No built-in multicore coordination
- No DMA API
- No PIO API
- No USB device-class configuration beyond SDK stdio
- No Wi-Fi or Bluetooth API
- No I2C repeated-start transaction abstraction
- No SPI mode or chip-select abstraction
- No UART framing configuration or buffering
- No ADC voltage-reference conversion helpers
- No PWM slice ownership registry
- No automatic runtime enforcement of peripheral uniqueness
- Interrupt events are bit-coalesced rather than counted
- Host builds cannot simulate hardware without injected abstractions
- The high-level facade traps instead of returning errors

Use low-level throwing APIs where runtime recovery matters. Use the facade for
compact sketches whose configuration is known at compile time.
