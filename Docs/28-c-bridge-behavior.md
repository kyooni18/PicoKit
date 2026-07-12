# PicoKit Documentation

## Chapter 28: C bridge behavior


The C bridge provides fixed-width functions for:

- Stdio initialization and output
- UART setup, byte reads, and bounded writes
- Board status LED
- GPIO setup, reads, writes, and toggles
- Monotonic time and sleep
- PWM setup and duty updates
- ADC setup and reads
- I2C setup, reads, and writes
- SPI setup and transfers
- Interrupt recording
- Watchdog enable and update

UART and SPI timeouts are implemented using deadlines based on `time_us_64()`. I2C delegates timeout behavior to the Pico SDK timeout functions.
