# PicoKit Documentation

## Chapter 18: Hardware UART


Hardware UART is separate from USB serial. Choose UART0 or UART1, then make the
baud rate and pins explicit:

```swift
let uart = try PicoUART(
    .uart0,
    baudRate: .hertz(115_200),
    tx: try PicoPin(0),
    rx: try PicoPin(1)
)
```

Writes are bounded, so choose a timeout that makes sense for the device on the
other end:

```swift
let bytes = Array("hello\r\n".utf8)
let written = try uart.write(
    bytes,
    timeout: .milliseconds(100)
)
```

Reads return one byte at a time:

```swift
let byte = try uart.read(timeout: .milliseconds(100))
```

`PicoKitError.timedOut` means no progress was made before the deadline. Other
negative bridge statuses become `PicoKitError.ioFailure`.

PicoKit intentionally leaves buffering, line parsing, framing, parity, stop
bits, and concurrent access control to a higher-level driver.
