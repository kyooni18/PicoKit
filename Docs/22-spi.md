# PicoKit Documentation

## Chapter 22: SPI


Create SPI0 or SPI1:

```swift
let spi = try PicoSPI(
    .spi0,
    frequency: .megahertz(8),
    sck: PicoPin(18),
    mosi: PicoPin(19),
    miso: PicoPin(16)
)
```

Perform a full-duplex transfer:

```swift
let received = try spi.transfer(
    [0x9F, 0x00, 0x00, 0x00],
    timeout: .milliseconds(100)
)
```

The returned array has the same length as the transmitted array.

Chip-select management is not built into `PicoSPI`. Configure a GPIO output and drive it around each transaction.

The current API uses the Pico SDK’s default SPI format. It does not expose clock polarity, clock phase, bit order, or frame-width configuration.
