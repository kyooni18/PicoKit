# PicoKit I2C and SPI transactions

I2C and SPI constructors validate digital pin roles, but a successful
constructor is only the beginning of a device transaction. The external
device still determines address format, pull-ups, timing mode, command layout,
chip-select lifetime, and response validity.

Keep one logical owner for each bus instance. Build a small driver above
`PicoI2C` or `PicoSPI` when a device needs registers, retries, a reset sequence,
or protocol-specific validation.

## I2C construction

Choose the controller, requested frequency, and a valid SDA/SCL pair:

```swift
let i2c = try PicoI2C(
    .i2c0,
    frequency: .kilohertz(400),
    sda: .gpio4,
    scl: .gpio5
)

Serial.println("I2C Hz=\(i2c.actualFrequency.hertz)")
```

PicoKit validates the repeating alternate-function pattern:

| Controller | SDA | SCL |
| --- | --- | --- |
| `I2C0` | GPIO values where `pin % 4 == 0` | following value where `pin % 4 == 1` |
| `I2C1` | GPIO values where `pin % 4 == 2` | following value where `pin % 4 == 3` |

SDA and SCL must be different. The bridge configures both selected pins for
I2C and enables their SDK pull-ups. Check the device and board electrical
requirements before relying on those internal pulls; many buses need external
pull-ups chosen for voltage and rise time.

`actualFrequency` reports the divider-quantized SDK result. Use it in a
diagnostic record rather than assuming the requested `Frequency` was exact.

## I2C addresses and timeouts

PicoKit expects a 7-bit I2C address in `0x08...0x77`:

```swift
let status = try i2c.write(
    address: 0x48,
    bytes: [0x01, 0x80],
    timeout: .milliseconds(100)
)
Serial.println("wrote \(status) bytes")
```

Do not pass the 8-bit wire byte that some datasheets show after shifting the
address and adding a read/write bit. Convert that representation to the
device's 7-bit address first. Reserved addresses are rejected as
`PicoKitError.invalidAddress`.

Every read and write takes a positive `Duration`. The C bridge accepts a
`UInt32` microsecond timeout, so a duration above that range is rejected as
`PicoKitError.invalidTimeout` before hardware access. A timed transfer can
throw `timedOut`, `partialTransfer`, or `ioFailure`; use those outcomes to
choose a bounded retry or a safe device state.

An empty STOP-scoped write or direct read is a validated no-op and clears any
pending repeated-START state. An empty no-STOP operation is rejected because it
cannot represent a useful next phase. A composed `writeRead` must request at
least one byte: PicoKit rejects an empty response before issuing its prefix
write so it cannot leave a repeated START pending. Address and timeout
validation still occurs first, so an invalid transaction is not made valid by
passing an empty buffer.

## STOP and repeated START

I2C calls issue STOP by default. Set `stop: false` when the following operation
must retain the bus and begin with a repeated START:

```swift
try i2c.write(
    address: 0x48,
    bytes: [0x00],
    timeout: .milliseconds(100),
    stop: false
)

let sample = try i2c.read(
    address: 0x48,
    count: 2,
    timeout: .milliseconds(100)
)
```

For the common register-prefix pattern, use `writeRead`:

```swift
let sample = try i2c.writeRead(
    address: 0x48,
    bytes: [0x00],
    count: 2,
    timeout: .milliseconds(100)
)
```

`writeRead` validates the complete address, prefix, count, and timeout before
issuing the prefix write. Its timeout applies independently to the write and
read portions. This prevents an invalid read count from causing a side-effect
or a failed no-STOP phase from leaking a repeated START into the next
independent transaction; no prefix write occurs before an invalid composed
operation is reported.

Use `stop: false` on a read only when another operation must follow without
releasing the bus. If the transaction is complete, leave the default STOP in
place. A repeated START is a protocol choice, not a general performance
optimization.

## I2C transaction ownership

PicoKit does not provide a cross-object bus lock or a device-address registry.
One `PicoI2C` object should own an entire composed transaction. Do not let two
independent loops interleave a register prefix and a read, even if they share
the same controller pins. Serialize at the application driver boundary and
keep device-specific retry policy there.

When a transaction is silent, check power, ground, pull-ups, voltage levels,
address format, reset state, and SDA/SCL waveforms in that order. Constructor
success proves only that the software pin pattern was accepted.

## SPI construction and format

SPI configuration selects instance, frequency, pin roles, mode, bit order, and
frame width:

```swift
let spi = try PicoSPI(
    .spi0,
    frequency: .megahertz(8),
    sck: .gpio18,
    mosi: .gpio19,
    miso: .gpio16,
    mode: .mode0,
    bitOrder: .mostSignificantBitFirst,
    dataBits: .eight,
    chipSelect: .gpio17
)

Serial.println("SPI Hz=\(spi.actualFrequency.hertz)")
```

The constructor rejects invalid alternate-function roles and shared SCK/MOSI/
MISO pins. The optional chip-select pin must also be distinct. The selected
mode maps to the device's CPOL/CPHA requirement:

| Mode | CPOL | CPHA |
| --- | ---: | ---: |
| `.mode0` | 0 | 0 |
| `.mode1` | 0 | 1 |
| `.mode2` | 1 | 0 |
| `.mode3` | 1 | 1 |

`bitOrder` and `dataBits` are part of the hardware format. An 8-bit overload
cannot be called on a 16-bit instance and vice versa; PicoKit throws
`unavailable` before starting a mismatched operation. `actualFrequency` is the
SDK-selected rate after divider quantization.

## Chip-select lifetime

When `chipSelect` is supplied, PicoKit configures it as an active-low output
that is high while idle. `select()` drives it low and `deselect()` drives it
high:

```swift
try spi.select()
defer { try? spi.deselect() }

let identifier = try spi.transfer(
    [0x9F, 0x00, 0x00, 0x00],
    timeout: .milliseconds(100)
)
```

The `defer` keeps the device deselected if a transfer throws. Keep CS asserted
across the complete command/response frame when the device protocol requires
it; do not select and deselect between every byte unless the datasheet says to.

If no chip-select pin was supplied, `select()` and `deselect()` throw
`PicoKitError.unavailable("SPI chip-select pin")`. This supports devices whose
CS is controlled by another owner, but that owner must coordinate the whole
transaction. PicoKit does not automatically toggle an unconfigured GPIO.

The SPI object configures an explicitly supplied `PicoGPIO` with the compiled
chip. Pass a controller that belongs to the same firmware target; a chip
mismatch is unavailable rather than silently redirected.

## SPI write, read, and transfer

SPI is full duplex at the wire. A receive operation clocks a repeated transmit
value on MOSI for every received frame:

```swift
let bytes = try spi.read(
    count: 3,
    repeatedByte: 0x00,
    timeout: .milliseconds(100)
)
```

`read(count:repeatedByte:)` requires MISO and 8-bit mode. In 16-bit mode, use
the corresponding word overload:

```swift
let spi16 = try PicoSPI(
    .spi1,
    frequency: .megahertz(4),
    sck: .gpio10,
    mosi: .gpio11,
    miso: .gpio8,
    dataBits: .sixteen
)
let words = try spi16.read(2, repeatedWord: 0x0000, timeout: .milliseconds(100))
```

`transfer` sends the supplied frames and returns one received frame for each
transmitted frame. It requires MISO:

```swift
let response = try spi.transfer(
    [0x80, 0x00, 0x00],
    timeout: .milliseconds(100)
)
```

For write-only devices, omit MISO and use `write` or `write(_:timeout:)`. The
SPI hardware still receives data internally; PicoKit's write path drains it
without exposing a response array.

## Blocking versus timed operations

Use the timed overload on a control path that must recover from a stalled
peripheral:

```swift
try spi.write([0x06], timeout: .milliseconds(20))
```

The timeout covers the complete operation. Timed SPI writes can report a
`partialTransfer` with the number of frames accepted before the deadline.
Timed receive and full-duplex paths report `timedOut` or an SDK `ioFailure`
according to the bridge result. Untimed operations use the SDK blocking path;
on every timed SPI failure, PicoKit aborts the controller frame and clears its
RX FIFO and overrun state. That prevents stale data from reaching the next API
call, but it does not make the device protocol retry-safe: deassert/reassert
chip select and resynchronize the device command sequence before retrying.
do not place one in a watchdog-protected loop unless an unbounded stall is an
intentional reset policy.

Empty SPI buffers are safe no-ops through the SDK transfer-count boundary, but
mode, MISO, and chip-select configuration requirements still apply to the
selected overload. A zero-length call is not evidence that a device responded.

## Transaction checklist

Before flashing a bus driver, record:

1. Board, chip, controller instance, and actual frequency.
2. Pin map, voltage levels, ground, and external pull-up/termination rules.
3. I2C 7-bit address or SPI CS owner and idle level.
4. I2C STOP/repeated-START sequence or SPI CS frame boundary.
5. SPI mode, bit order, frame width, maximum clock, and inter-frame delay.
6. Timeout, retry, and partial-transfer policy.
7. Expected identity/register response and the physical capture that proves it.

When a constructor succeeds but the device is silent, stop changing software
pin maps at random. Capture the actual SDA/SCL or SCK/MOSI/MISO/CS waveform and
compare it with the device datasheet.

## Host and physical verification

Host validation covers API shape, value errors, overloads, and unavailable
hardware behavior:

```sh
swift build
swift run PicoKitHostTests
```

Firmware validation must additionally build the selected board image. Physical
validation needs a powered device, common ground, expected voltage levels, and
either a known response or a logic-analyzer capture. A successful constructor,
host build, or USB diagnostic does not prove that an I2C slave acknowledged or
that an SPI peripheral decoded the frame.

## Related documents

- [Board and pin planning](board-and-pin-planning.md) — validated UART/I2C/SPI
  maps and cross-device conflict checks.
- [Failure diagnosis](failure-diagnosis.md) — classify bus silence by evidence.
- [DMA and buffer lifecycle](dma-and-buffer-lifecycle.md) — prepared SPI
  transfers and channel ownership.
- [GPIO and reset sequencing](gpio-and-reset-sequencing.md) — CS/reset output
  levels and startup sequencing.
- [PWM, ADC, I2C, and SPI](buses-and-analog.md) — compact peripheral summary.
