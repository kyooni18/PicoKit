# PicoKit Documentation

## Chapter 22: SPI


Choose SPI0 or SPI1 and make the bus pins and clock rate explicit:

```swift
let spi = try PicoSPI(
    .spi0,
    frequency: .megahertz(8),
    sck: try PicoPin(18),
    mosi: try PicoPin(19),
    miso: try PicoPin(16)
)
```

Transfers are full duplex: every byte sent clocks one byte back:

```swift
let received = try spi.transfer(
    [0x9F, 0x00, 0x00, 0x00],
    timeout: .milliseconds(100)
)
```

The returned array always has the same length as the transmitted array.

`PicoSPI` deliberately does not own chip select. Configure a GPIO output and
drive it around each transaction so the ownership stays obvious in your driver.

The current API uses the Pico SDK's default SPI format. It does not yet expose
clock polarity, clock phase, bit order, or frame width, so confirm that default
matches the part you are talking to.
