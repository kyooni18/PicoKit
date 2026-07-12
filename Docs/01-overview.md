# PicoKit Documentation

## Chapter 1: Overview


PicoKit is an Embedded Swift library and a small command-line workflow for
Raspberry Pi Pico boards. It covers the RP2040-based Pico and Pico W as well as
the RP2350-based Pico 2 and Pico 2 W.

You write Swift; PicoKit takes care of crossing into the official Pico SDK when
hardware work is needed. That boundary is deliberately narrow, so application
code gets a typed API without inheriting the SDK's macros, inline functions, or
register details.

Out of the box, PicoKit gives you:

- Validated GPIO pin, duration, and frequency types
- Digital GPIO
- Board status LED control
- USB serial output
- Hardware UART
- Timing and blocking delays
- PWM output
- ADC input
- I2C
- SPI
- GPIO interrupt event collection
- Watchdog control
- A host-side `swiftpico` command-line tool
- High-level Arduino-style convenience functions
- Low-level throwing APIs for recoverable failures

Start with the high-level facade for a small blinking or serial sketch. Reach
for the lower-level types when you need explicit ownership, timeouts, or a way
to recover from an error.
