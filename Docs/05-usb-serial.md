# PicoKit Documentation

## Serial: USB CDC, monitor, and UART


### Low-level USB serial

Use `USBSerial` when serial setup should participate in normal error handling:

```swift
let serial = try USBSerial()
try serial.write("System started")
```

Creating `USBSerial` initializes Pico SDK stdio. Keep the instance around and
reuse it rather than treating every line of output as a new setup operation.

USB CDC input is byte-oriented. Poll without blocking, or use a bounded read
when a command is required:

```swift
if let byte = try serial.read() {
    // Process one host-sent byte.
}

let commandByte = try serial.read(timeout: .seconds(5))
```

The timeout overload throws `PicoKitError.timedOut` if no byte arrives before
the deadline. PicoKit deliberately does not buffer lines or parse commands.

### High-level serial

For a sketch, the global `Serial` object initializes USB stdio lazily on its
first write:

```swift
Serial.write("raw text")
Serial.print("value: ")
Serial.println("42")
Serial.println()
```

`print` does not append a newline. `println` does.

Host input is available through nonblocking byte polling. `available` retains
the next byte internally, so checking it does not consume data:

```swift
while Serial.available {
    if let byte = Serial.read() {
        Serial.write([byte]) // Exact byte echo, including non-UTF-8 input.
    }
}
```

Use `USBSerial.read(timeout:)` instead when firmware must distinguish a timeout
from another USB stdio failure.

The default runtime exposes the same object if you prefer an explicit owner:

```swift
pico.serial.println("hello")
```

### Host monitor

Use SwiftPico to open the board's USB CDC device:

```sh
./swiftpico list
./swiftpico monitor --device /dev/cu.usbmodem... --reconnect
```

`monitor` (also `serial` and `mon`) is an interactive terminal: typed bytes
are sent to the board while firmware output continues to display. `--reconnect`
waits for the same device after a reset or short USB disconnect. Press Ctrl-C
to exit.

### Hardware UART

USB serial is independent from the RP2040/RP2350 UART controllers. Configure
UART0 or UART1 with explicit pins and baud rate, then use bounded byte I/O:

```swift
let uart = try PicoUART(
    .uart0,
    baudRate: .hertz(115_200),
    tx: try PicoPin(0),
    rx: try PicoPin(1)
)
try uart.write(Array("hello\r\n".utf8), timeout: .milliseconds(100))
let byte = try uart.read(timeout: .milliseconds(100))
```

Both USB CDC and UART are byte streams. PicoKit does not provide framing,
line buffering, parity/stop-bit configuration, or concurrent-access control.
