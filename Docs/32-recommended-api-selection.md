# PicoKit Documentation

## Chapter 32: Recommended API selection


Use the high-level facade when:

- The firmware is a small sketch
- Pins and peripherals are fixed
- Configuration failures should stop execution immediately
- Minimal syntax is preferred

Use the low-level API when:

- Errors must be logged or recovered
- Timeouts need distinct handling
- Code is organized into reusable drivers
- Tests use injected `DigitalIO`
- Peripheral ownership is managed explicitly
- A library should not trap its caller

PicoKit’s main design principle is to keep Embedded Swift application code typed and compact while isolating all direct Pico SDK interaction inside a small C boundary.
