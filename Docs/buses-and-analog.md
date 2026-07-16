# PWM, ADC, I2C, and SPI

Peripheral objects validate their configuration during construction and are
designed to be reused. Create one owner for a controller or channel, keep it
alive, and perform repeated transfers through that instance.

## PWM

Create PWM with a pin and requested frequency:

```swift
let pwm = try PicoPWM(pin: .gpio0, frequency: .kilohertz(1))
```

The SDK selects a divider and counter wrap; `actualFrequency` reports the
result and `counterTop` reports the maximum raw counter level. Update the duty
cycle without reconstructing the peripheral:

```swift
try pwm.setDutyCycle(32_768)              // UInt16 fraction
try pwm.analogWrite(UInt8(128))           // Arduino-style 8-bit value
try analogWrite(0, UInt8(128), using: pwm)
try pwm.setCounterLevel(pwm.counterTop / 4)
```

The free helper verifies that its integer pin matches `pwm.pin`; a mismatch is
an ownership conflict. `setCounterLevel` avoids rescaling when the application
already computes hardware counter units.

`PicoBacklight` wraps the common PWM backlight policy and supports `UInt8` and
`UInt16` brightness, `off()`, and `fullOn()`.

## ADC

One ADC instance can sample `.gpio26`, `.gpio27`, `.gpio28`, `.gpio29`, or the
internal temperature channel:

```swift
let adc = try PicoADC()
let input = try adc.read(.gpio26)
let sameInput = try analogRead(26, using: adc)
let temperatureRaw = try adc.read(.temperature)
```

Results are raw `UInt16` samples. PicoKit does not guess the reference voltage,
board calibration, or temperature conversion formula. Reusing the instance
and channel minimizes repeated setup work; continuous high-rate capture needs
a purpose-built DMA or C/PIO path.

## I2C construction and transfers

Select a controller, bus frequency, SDA, and SCL:

```swift
let i2c = try PicoI2C(
    .i2c0,
    frequency: .kilohertz(400),
    sda: .gpio4,
    scl: .gpio5
)
```

`actualFrequency` reports the SDK-selected rate. PicoKit accepts normal 7-bit
addresses `0x08...0x77`, rejects a shared SDA/SCL pin, treats an empty write as
a no-op, and returns an empty array for a zero-length read.

```swift
let written = try i2c.write(
    address: 0x3C,
    bytes: [0x00, 0xAF],
    timeout: .milliseconds(100)
)
let bytes = try i2c.read(
    address: 0x3C,
    count: 4,
    timeout: .milliseconds(100)
)
```

Positive short results become `PicoKitError.partialTransfer`. Timeouts wider
than the SDK's `UInt32` microsecond bound are rejected before hardware access.

## Repeated START

Calls issue STOP by default. A register read usually suppresses STOP after the
register prefix and then reads:

```swift
try i2c.write(
    address: 0x3C,
    bytes: [0x10],
    timeout: .milliseconds(100),
    stop: false
)
let bytes = try i2c.read(
    address: 0x3C,
    count: 4,
    timeout: .milliseconds(100)
)
```

`writeRead` performs the common sequence directly. Its timeout applies to each
portion independently. Reads also accept `stop: false` when a following
operation must continue the transaction.

## SPI construction

Select the controller, clock, pins, mode, bit order, and frame width. Supplying
`chipSelect` lets the instance configure an active-low CS that is high while
idle:

```swift
let spi = try PicoSPI(
    .spi0,
    frequency: .megahertz(8),
    sck: .gpio18,
    mosi: .gpio19,
    miso: .gpio16,
    mode: .mode0,
    chipSelect: .gpio17
)

try spi.select()
let id = try spi.transfer([0x9F, 0, 0, 0], timeout: .milliseconds(100))
try spi.deselect()
```

SCK, MOSI, MISO, and explicit chip select must not conflict. Full-duplex
`transfer` requires MISO. Receive-only devices can use
`read(count:repeatedByte:)`; 16-bit mode uses `read(_:repeatedWord:)` and the
`[UInt16]` transfer/write overloads.

## SPI DMA

DMA calls remain synchronous but reduce CPU work for prepared buffers:

```swift
try spi.writeDMA(frameBytes, timeout: .milliseconds(100))
let received = try spi.transferDMA(frameBytes, timeout: .milliseconds(100))
spi.releaseDMAChannels()
```

`transferDMA` needs MISO and paired TX/RX channels. `writeDMA` drains RX while
discarding it. The SPI object retains channels for repeated calls; timed-out
operations abort both channels before returning. The source array is not
retained after the call. Clock rate, wiring, and receiver behavior still bound
the actual throughput.
