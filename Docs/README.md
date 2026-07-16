# PicoKit documentation

Start with the project workflow, then open the guide for the peripheral or
integration boundary you are using. The repository [README](../README.md) is
the short introduction; these documents contain the working detail.

## Start here

1. [Getting started](getting-started.md) — boards, installation, project
   layout, build, flash, monitor, API-level choice, and troubleshooting.
2. [Explained examples](examples.md) — complete blink, button, serial, PWM,
   ADC, I2C, SPI, interrupt, watchdog, and host-test programs.
3. [Hardware guide](hardware-guide.md) — core values, GPIO, timing, ownership,
   interrupts, watchdog, and an overview of every peripheral.

## Focused guides

4. [USB serial and UART](serial-and-uart.md) — byte I/O, connection behavior,
   timeouts, pin mappings, DMA, and monitor workflow.
5. [PWM, ADC, I2C, and SPI](buses-and-analog.md) — configuration, transactions,
   repeated START, frame widths, chip select, and DMA transfers.
6. [Runtime and testing](runtime-and-testing.md) — ownership, host behavior,
   fakes, validation gates, hardware tests, and deliberate limits.
7. [External libraries](external-libraries.md) — dependency files, Clang
   modules, C/C++ adapters, callbacks, migration, and reproducibility.
8. [Performance](performance.md) — fast paths, benchmark fixture, measurement
   method, DMA interpretation, and physical validation.

## Reference

9. [API reference](api-reference.md) — complete public declaration surface.
10. [Integration notes](integration.md) — concise interoperability and
   performance summary for readers upgrading an existing project.
