# Protocol framing and data representation

PicoKit transports bytes and frames; it does not define an application
protocol. A Swift `String`, `UInt16`, I2C address, or SPI mode is not enough to
determine what an external device expects. Define the wire representation in
the driver and test it with exact byte fixtures before connecting hardware.

## Separate the transport from the protocol

Keep these decisions distinct:

| Layer | Questions to answer |
| --- | --- |
| Electrical path | voltage, ground, pull-ups, termination, idle level |
| Peripheral transport | UART pins/baud, I2C instance/address, SPI mode/bit order/frame width |
| Frame format | header, length, command, payload, checksum, terminator |
| Value encoding | signedness, scaling, byte order, bit fields, text encoding |
| Recovery | acknowledgement, sequence number, timeout, replay, resynchronization |

PicoKit validates the transport arguments it owns. The device datasheet and
application driver own the remaining rows.

## Raw bytes are the stable boundary

Use byte-array APIs for packets, binary logs, and exact fixtures:

```swift
let request: [UInt8] = [
    0xA5,       // sync
    0x02,       // payload length
    0x10,       // command
    0x00, 0x7F  // payload
]

try uart.write(request, timeout: .milliseconds(50))
```

`Serial.write`, `USBSerial.write`, and `PicoUART.write` preserve NUL and
non-UTF-8 bytes. `String` writes are useful for human-readable diagnostics,
but converting arbitrary packets through text can lose framing or byte values.
If a protocol is text-based, specify its encoding, newline, escaping, and
maximum line length explicitly.

## Encode byte order explicitly

Do not assume a device's byte order from the Swift host or the MCU. Make the
conversion visible and test both directions:

```swift
func bigEndianBytes(_ value: UInt16) -> [UInt8] {
    [UInt8(value >> 8), UInt8(value & 0x00FF)]
}

func littleEndianBytes(_ value: UInt16) -> [UInt8] {
    [UInt8(value & 0x00FF), UInt8(value >> 8)]
}

precondition(bigEndianBytes(0x1234) == [0x12, 0x34])
precondition(littleEndianBytes(0x1234) == [0x34, 0x12])
```

These helpers describe a wire format; they are not a statement about the
endianness of a particular bus or SDK. Keep signed conversion, scaling, and
range checks next to the protocol field rather than relying on a memory cast.

## SPI words are frames, not a protocol encoding

`PicoSPI` supports `SPIDataBits.eight` and `.sixteen`, with matching byte and
`UInt16` overloads. RP-series SPI hardware supports only
`.mostSignificantBitFirst`; requesting `.leastSignificantBitFirst` throws
`PicoKitError.unavailable` before the peripheral is configured. Bit order does
not tell the device whether a multi-byte register value is big-endian or
little-endian. Confirm all of these from the device datasheet:

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

try spi.select()
defer { try? spi.deselect() }
let response = try spi.transfer([0x9F, 0, 0, 0], timeout: .milliseconds(100))
```

Use 16-bit overloads only when the device defines 16-bit frames and the
transaction's alignment and byte order are understood. Do not turn a byte
packet into `[UInt16]` merely to reduce the number of array elements. A
write-only SPI instance can omit MISO, but a read or full-duplex transfer
requires it.

## I2C addresses are not packet bytes

PicoKit's I2C API takes a validated 7-bit address in `0x08...0x77`. The SDK
handles the transport address phase; do not shift the address left and pass an
8-bit read/write address unless a separate adapter API explicitly asks for
that representation. The register number, command prefix, repeated START,
payload, and response decoding remain device protocol policy:

```swift
let raw = try i2c.writeRead(
    address: 0x40,
    bytes: [0x00],       // device register/command, not a shifted address
    count: 2,
    timeout: .milliseconds(50)
)
```

For a multi-byte register, decode `raw` using the device's documented order.
Do not infer it from the order in which bytes arrived on the wire.

## UART needs framing and resynchronization

UART provides a byte stream, not message boundaries. Choose a framing scheme:

- fixed-length records when every field has a known width;
- sync byte plus length for variable payloads;
- delimiter with escaping for human-readable command lines;
- sequence number plus acknowledgement when replay matters;
- checksum or CRC when corruption must be detected.

Bound the parser's maximum frame length and reset it when a timeout or invalid
length is received. A `partialTransfer` after a command write means the peer
may have acted on a prefix; do not blindly resend the same command without a
resynchronization rule. See [peripheral recovery](peripheral-recovery.md).

## Check before sending

Construct the complete frame in ordinary Swift before touching the peripheral:

```swift
func makeFrame(command: UInt8, payload: [UInt8]) -> [UInt8]? {
    guard payload.count <= 255 else { return nil }
    var frame = [UInt8](arrayLiteral: 0xA5, UInt8(payload.count), command)
    frame.append(contentsOf: payload)
    let checksum = frame.reduce(UInt8(0)) { $0 &+ $1 }
    frame.append(checksum)
    return frame
}

guard let frame = makeFrame(command: 0x10, payload: [0, 0xFF]) else {
    throw PicoKitError.ioFailure(operation: "frame construction", status: -1)
}
Serial.write(frame)
```

Validate length, field ranges, checksum input, and total transfer count before
selecting a device or starting a transaction. This keeps an invalid packet
from becoming a partial hardware side effect.

## Test exact representation

Host tests should cover protocol values without constructing hardware objects:

1. known values encode to exact expected bytes;
2. decode rejects short, oversized, invalid-checksum, and invalid-length frames;
3. NUL and `0xFF` survive round trips;
4. signed values and boundary scaling are explicit;
5. SPI byte/word paths are not mixed accidentally;
6. a timeout or partial transfer follows the driver's resynchronization policy.

Then use firmware and physical evidence for the transport claim:

```sh
swift build
swift run PicoKitHostTests
sh Tests/integration/usb-serial-status-firmware.sh
```

The USB fixture proves raw CDC bytes for its image. A UART loopback, I2C device
response, SPI identity response, logic analyzer, or scope is needed to prove a
different physical path. A host packet test proves representation, not wiring.

## Related documents

- [USB serial and UART](serial-and-uart.md) — byte transport and UART timing.
- [I2C and SPI transactions](i2c-and-spi-transactions.md) — bus boundaries,
  frame widths, and timeouts.
- [Driver testing](driver-testing.md) — host fakes and exact behavior tests.
- [Peripheral recovery](peripheral-recovery.md) — partial transfer and retry
  policy.
- [Hardware validation](hardware-validation.md) — physical evidence levels.
