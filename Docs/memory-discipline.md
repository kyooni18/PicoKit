# PicoKit memory and allocation discipline

Embedded Swift firmware has different consequences for allocation, buffer
growth, and pointer lifetimes than a host utility. PicoKit keeps its core
Foundation-free and makes DMA synchronous, but it does not impose an allocator
or a general memory manager. The application must choose where data is
created, how large it may become, and which operation owns it.

## Keep interrupt paths allocation-free

PicoKit's GPIO IRQ path records edge bits in the C bridge and defers work to
foreground Swift. An interrupt handler must not allocate, format strings,
sleep, print, perform bus I/O, or call another PicoKit object:

```swift
while true {
    let events = interrupts.takeEvents(for: button)
    if events != 0 {
        // Allocate, decode, log, and debounce here in foreground context.
        processButtonEvents(events)
    }
    sleepMicroseconds(100)
}
```

This is not only a speed rule. A handler that allocates or waits can introduce
unbounded latency, re-enter a non-thread-safe peripheral, or fail while the
foreground owner assumes the event was recorded. If exact edge multiplicity
is required, use an application-owned capture design rather than treating the
coalesced event word as a queue.

## Bound packet and sample storage

For a repeated path, establish maximum sizes during setup and reuse storage:

```swift
let maximumPayload = 64
var packet = [UInt8](repeating: 0, count: maximumPayload)

func makeRequest(_ payload: [UInt8]) -> [UInt8]? {
    guard payload.count <= packet.count else { return nil }
    packet.replaceSubrange(0..<payload.count, with: payload)
    return Array(packet[0..<payload.count])
}
```

The example still creates a result array for clarity. A high-rate driver should
choose a ring, pool, fixed-size record, or C-owned buffer appropriate to its
throughput rather than repeatedly growing arrays in its control loop. Validate
lengths before appending or entering a bus operation; transfer counts are
bounded by the bridge's representable C integer range.

Do not assume that a Swift array is stack storage or that an optimization will
remove every allocation. Measure the complete firmware path when allocation
cost matters, and keep the application buffer policy explicit.

## Understand DMA buffer lifetime

PicoKit's UART and SPI DMA calls are synchronous prepared-buffer operations.
They borrow the array contents for the duration of the call; they do not run as
background tasks that keep a caller buffer alive after returning:

```swift
var frame = makeDisplayFrame()
try spi.writeDMA(frame, timeout: .milliseconds(100))

// Safe to mutate or reuse after the call returns.
frame[0] = nextCommand
```

The timeout overload is the bounded handoff point: on timeout it aborts and
cleans up the active channel before returning. An unbounded DMA overload can
wait indefinitely, so do not use it inside a watchdog-protected loop unless
that behavior is intentional. Release retained channels when a subsystem is
handed off with `releaseDMAChannel()` or `releaseDMAChannels()`.

Never mutate a buffer from another context while a DMA call is executing. A
`Sendable` value or copied array reference is not a synchronization protocol.
Keep the buffer and peripheral owner in the same foreground context.

## Prefer scalar fast paths for tiny data

Avoid allocating a one-element array when the API offers a scalar overload:

```swift
try usb.write(0x00)
try uart.write([0x00], timeout: .milliseconds(10))
```

`USBSerial.write(_ byte:)` exists specifically for one raw byte. UART and SPI
protocols may still require an array or word frame for their transaction shape;
do not trade away framing correctness for an allocation micro-optimization.
Measure before changing a clear protocol representation.

## Keep C pointers inside their documented scope

Application C adapters should use pointer-plus-length arguments and define
whether a call retains the pointer. A pointer borrowed from a Swift array is
valid only for the closure or operation that documents that borrow:

```swift
let pixels: [UInt16] = makePixels()
pixels.withUnsafeBufferPointer { buffer in
    st7789_write_pixels(buffer.baseAddress, UInt32(buffer.count))
}
```

Do not store `buffer.baseAddress` in a C global after the closure returns unless
the adapter explicitly copies the data or the application owns a stable C
allocation for the required lifetime. For empty buffers, define whether a null
pointer and zero length are accepted; do not blindly pass an invalid base
address to a vendor library.

C++ adapters must make create/destroy ownership explicit and catch exceptions
before crossing the C ABI. Swift-owned memory must not outlive its documented
borrow, and vendor-owned memory must have an explicit release function.

## Keep diagnostics out of hot paths

Formatting a string or writing USB can allocate, block, or change timing. Use a
counter, flag, or compact event code in a high-rate path and format it later in
foreground context. Never log from an IRQ. A disconnected USB host must not
turn a control loop into an unbounded producer.

When logging is part of a benchmark, measure with the same logging policy in
every comparison. A log line that changes a timeout or hides a race is a
workload change, not neutral instrumentation. See [observability and diagnostics](observability-and-diagnostics.md)
and [performance](performance.md).

## Host tests and memory claims

Host tests can prove bounds and ownership policy:

- oversized packets are rejected before a transfer;
- a fake records no hardware event after invalid input;
- a buffer is not reused until a DMA call returns;
- a C adapter receives the expected pointer length and status;
- an interrupt-facing path only records data for foreground processing.

They cannot prove firmware heap fragmentation, exact allocation count, DMA
alignment, cache behavior, or interrupt latency. Use firmware benchmarks,
linker/map inspection, a scope or analyzer, and the selected receiver when
those claims matter.

## Review checklist

Before accepting a memory-sensitive driver, confirm:

1. interrupt code performs no allocation, blocking, logging, or peripheral I/O;
2. packet, sample, and diagnostic sizes have explicit bounds;
3. DMA buffers are immutable to other owners until the call returns;
4. retained DMA channels are released at subsystem handoff;
5. C pointers are borrowed or owned with documented lifetimes;
6. hot-path diagnostics are bounded and measured;
7. host results are not reported as firmware allocation or timing evidence.

## Related documents

- [DMA and buffer lifecycle](dma-and-buffer-lifecycle.md) — channel and buffer
  contracts.
- [Resource ownership](resource-ownership.md) — owners and handoff order.
- [External libraries](external-libraries.md) — C/C++ ABI and pointer rules.
- [Observability and diagnostics](observability-and-diagnostics.md) — logging
  policy and evidence.
- [Performance](performance.md) — measurement method and interpretation.
