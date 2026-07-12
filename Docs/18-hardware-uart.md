# PicoKit Documentation

## Chapter 18: Hardware UART


Create UART0 or UART1 with explicit pins and baud rate:

```swift
let uart = try PicoUART(
    .uart0,
    baudRate: .hertz(115_200),
    tx: PicoPin(0),
    rx: PicoPin(1)
)
```

Write bytes with a timeout:

```swift
let bytes = Array("hello\r\n".utf8)
let written = try uart.write(
    bytes,
    timeout: .milliseconds(100)
)
```

Read one byte:

```swift
let byte = try uart.read(timeout: .milliseconds(100))
```

A timeout throws `PicoKitError.timedOut`. Other negative bridge statuses become `PicoKitError.ioFailure`.

PicoKit does not currently provide buffered UART streams, line parsing, framing, parity configuration, stop-bit configuration, or concurrent access control.
