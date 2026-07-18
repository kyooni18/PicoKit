# PicoKit DMA and buffer lifecycle

PicoKit's DMA APIs are synchronous prepared-buffer fast paths. They claim the
necessary SDK channels, start the transfer, wait for completion, and return
only after the bridge no longer reads the caller's Swift array. This makes them
straightforward to use in a foreground loop, but they are not asynchronous
queueing APIs and they do not make a peripheral thread-safe.

Use DMA when the buffer is large enough that CPU-driven transfers are a real
part of the workload. Use the ordinary timed API for short control messages,
where a timeout and simpler failure path matter more than reducing per-byte
CPU work.

## What each API does

| Peripheral | API | Frames | Receive path | Timeout form |
| --- | --- | --- | --- | --- |
| UART | `writeDMA(_:)` | 8-bit | none exposed | unbounded completion wait |
| UART | `writeDMA(_:timeout:)` | 8-bit | none exposed | bounded; timeout aborts the channel |
| SPI | `writeDMA(_:)` | 8 or 16-bit | received words discarded | unbounded completion wait |
| SPI | `transferDMA(_:)` | 8 or 16-bit | returned array | unbounded completion wait |
| SPI | `writeDMA(_:timeout:)` / `transferDMA(_:timeout:)` | 8 or 16-bit | discarded or returned | bounded; timeout cleans up channels |

SPI is physically full-duplex even for a write. A write-only DMA call uses a
discard sink for received data so the RX FIFO does not stall; a transfer call
requires `miso` and returns the captured words. UART DMA only sends bytes.

The Swift overload selects the frame width. An 8-bit `[UInt8]` operation
requires `dataBits: .eight`; a 16-bit `[UInt16]` operation requires
`dataBits: .sixteen`. A mismatched overload throws `unavailable` before the
bridge starts a transfer.

## Keep one owner per hardware instance

DMA channels are retained by the bridge for reuse:

- UART retains one channel per `UARTInstance` and releases it with
  `releaseDMAChannel()` or when the owning `PicoUART` deinitializes.
- SPI retains a TX/RX pair per `SPIInstance` and releases them with
  `releaseDMAChannels()` or when the owning `PicoSPI` deinitializes.

This is a reuse optimization, not a general ownership registry. Create one
application owner for each UART/SPI instance, keep all calls on that owner, and
release it when the resource's lifetime ends. Do not run two independent
objects for the same peripheral instance or call its DMA methods concurrently.
PicoKit's hardware objects are single-owner foreground resources; `Sendable`
does not turn them into synchronized queues.

```swift
let uart = try PicoUART(
    .uart0,
    baudRate: .hertz(1_000_000),
    tx: .gpio0,
    rx: .gpio1,
    chip: .compiled
)

let packet: [UInt8] = [0x55, 0x02, 0x10, 0x00, 0x12]
try uart.writeDMA(packet, timeout: .milliseconds(20))

// Keep this owner while sending more packets. Release before handing the
// UART instance to another owner or entering a low-resource mode.
uart.releaseDMAChannel()
```

Calling `releaseDMAChannel()` or `releaseDMAChannels()` is idempotent at the
Swift boundary when no channel is retained. Release only after the synchronous
operation returns; a caller must not invalidate or repurpose a resource while
its DMA operation is active.

## Buffer lifetime and mutation

DMA methods borrow the contents of the array for the duration of the call.
They do not retain the Swift array after returning and they do not provide a
completion callback. Therefore this is safe:

```swift
func sendFrame(_ spi: PicoSPI, _ source: [UInt8]) throws {
    var frame = source
    frame.append(0x00)
    try spi.writeDMA(frame, timeout: .milliseconds(100))
    // `frame` can be reused or destroyed here: DMA has completed or aborted.
}
```

Do not treat `writeDMA(_:)` without a timeout as a background operation. It
waits until the bridge reports completion or an SDK/DMA error. If the device
can hold a transfer indefinitely, use the timeout overload so a control loop
can recover and the buffer can be safely reused after the method returns.

For a full-duplex transfer, the returned array is newly produced by PicoKit:

```swift
let spi = try PicoSPI(
    .spi0,
    frequency: .megahertz(8),
    sck: .gpio18,
    mosi: .gpio19,
    miso: .gpio16,
    dataBits: .eight,
    chipSelect: .gpio17
)

try spi.select()
defer { try? spi.deselect() }

let tx = [UInt8](repeating: 0, count: 256)
let rx = try spi.transferDMA(tx, timeout: .milliseconds(100))
precondition(rx.count == tx.count)
```

`transferDMA` requires MISO because every transmitted frame produces a
received frame. Use `writeDMA` when the device's response is intentionally
discarded. Chip select remains an application-level transaction boundary:
select before the DMA call and deselect after it, including when the call
throws.

## Timeout and error behavior

Bounded DMA methods poll the active channel(s) until completion. On timeout,
the bridge cleans up the channel(s) before returning `PicoKitError.timedOut`;
the retained slot remains reusable by the same peripheral owner. A hardware
DMA fault becomes `PicoKitError.ioFailure`. A result count that is positive but
short of the request becomes `PicoKitError.partialTransfer`.

The error policy should distinguish a recoverable transfer timeout from a
permanent configuration error:

```swift
func send(_ bytes: [UInt8], through spi: PicoSPI) -> Bool {
    do {
        try spi.writeDMA(bytes, timeout: .milliseconds(25))
        return true
    } catch PicoKitError.timedOut(let operation) {
        Serial.println("timed out during \(operation)")
        Serial.println("SPI DMA timed out; retrying once")
        return false
    } catch let error {
        Serial.println("SPI DMA failed: \(error)")
        return false
    }
}
```

After a timeout, inspect chip select, clock, wiring, and the device's busy
state before blindly retrying. A timeout cleanup prevents a stale channel from
continuing to access the array, but it cannot make an unpowered or held device
respond.

## Counts and frame width

Transfer counts cross the C bridge as signed 32-bit result counts, so PicoKit
rejects an array whose element count exceeds `Int32.max` before touching the
hardware. RP2350 DMA also reserves upper transfer-count bits for control flags;
the bridge applies the smaller hardware-valid count limit there. Normal
embedded buffers are far below both limits, but a generated or externally
owned buffer should still be bounded before allocation.

The count is in frames, not bytes:

```swift
let bytes = [UInt8](repeating: 0xA5, count: 512)       // 512 8-bit frames
let words = [UInt16](repeating: 0xA55A, count: 512)    // 512 16-bit frames

let spi8 = try PicoSPI(
    .spi0, frequency: .megahertz(4), sck: .gpio18,
    mosi: .gpio19, miso: .gpio16, dataBits: .eight
)
try spi8.writeDMA(bytes, timeout: .milliseconds(100))

let spi16 = try PicoSPI(
    .spi1, frequency: .megahertz(4), sck: .gpio10,
    mosi: .gpio11, miso: .gpio8, dataBits: .sixteen
)
try spi16.writeDMA(words, timeout: .milliseconds(100))
```

The device protocol still determines byte order, command framing, and whether
the first or last bit is significant. DMA preserves the configured SPI mode,
bit order, and frame width; it does not interpret a device protocol.

## Choosing a useful buffer size

Measure the complete application path rather than assuming DMA is faster:

1. Measure the ordinary timed write with the same clock, buffer, and receiver.
2. Measure the DMA write with the same buffer and timeout.
3. Verify byte or word integrity at the receiver.
4. Measure CPU availability or loop latency outside the transfer.
5. Repeat across the smallest buffer sizes the application will actually use.

DMA can reduce CPU work while leaving wire time unchanged. SPI remains bounded
by its configured clock and UART by its baud rate. For one-byte commands, DMA
setup and channel reuse can cost more than a direct write; for display rows or
large prepared packets, the reduced per-frame CPU work may matter.

Do not print inside the measured region. Save the result, then report it over
USB after the transfer; USB connection and logging delays would otherwise be
part of the measurement.

## Host and firmware verification

Host builds can verify API shape, overloads, and unavailable-hardware behavior:

```sh
swift build
swift run PicoKitHostTests
```

The host cannot prove DMA timing, channel availability, or receiver integrity.
For firmware, build a selected board and inspect the resulting ELF/UF2 before
flashing. A meaningful physical test records the board, SDK/PicoKit revision,
frame width, buffer size, requested and actual frequency, timeout, and receiver
result. Use a logic analyzer or the device's known response to prove that
frames were clocked correctly.

The performance fixture is useful for CPU and GPIO baselines, but it does not
certify SPI or UART DMA because those measurements require a selected receiver,
pin map, buffer size, and protocol-specific integrity check.

## Related documents

- [PWM, ADC, I2C, and SPI](buses-and-analog.md) — transaction semantics and
  SPI DMA overloads.
- [USB serial and UART](serial-and-uart.md) — UART framing, timeout, and DMA
  behavior.
- [Performance](performance.md) — repeatable measurement and reporting.
- [Runtime and testing](runtime-and-testing.md) — ownership and concurrency
  boundaries.
- [Failure diagnosis](failure-diagnosis.md) — classify timeout versus wiring
  and flash failures.
