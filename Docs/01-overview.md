# PicoKit Documentation

## Chapter 1: Overview


PicoKit is an Embedded Swift library and command-line workflow for Raspberry Pi Pico boards. It supports the RP2040-based Raspberry Pi Pico and Pico W, and the RP2350-based Pico 2 and Pico 2 W.

The library does not access peripheral registers directly from Swift. Hardware operations pass through a narrow C bridge backed by the official Raspberry Pi Pico SDK. This gives firmware a Swift-facing API while retaining the Pico SDK as the hardware implementation layer.

PicoKit provides:

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
