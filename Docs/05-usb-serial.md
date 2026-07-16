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
`serial.isConnected` reports whether a host currently has the CDC interface
open; it is only a snapshot, so writes must still handle a disconnect.

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
        Serial.write(byte) // Exact byte echo, including non-UTF-8 input.
    }
}
```

Use `USBSerial.read(timeout:)` instead when firmware must distinguish a timeout
from another USB stdio failure.

The default runtime exposes the same object if you prefer an explicit owner:

```swift
pico.serial.println("hello")
if pico.serial.connected {
    pico.serial.println("host connected")
}
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

For firmware that must keep its first diagnostic output until a host is ready,
set the CMake cache value `-DPICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS=5000`. The
default is `0`, which preserves non-blocking startup; a positive value waits
up to that many milliseconds during USB CDC initialization. This setting is
only applied when `PICOKIT_ENABLE_USB=ON`. Set it to `-1` to wait indefinitely,
matching the Pico SDK's documented indefinite-wait mode.

`PICOKIT_USB_POST_CONNECT_WAIT_DELAY_MS` defaults to `50`, matching the Pico
SDK's post-connect settle delay. Increase it when a host terminal needs more
time after CDC enumeration before the first diagnostic output is sent; set it
to `0` to disable the extra delay.

`PICOKIT_USB_CONNECTION_WITHOUT_DTR=ON` makes `USBSerial.isConnected` and
`PicoSerial.connected` report the CDC interface as connected once USB is ready,
without waiting for a terminal to assert DTR. It defaults to `ON` so USB CDC
works with host tools that open the device without changing modem-control
signals. Set it to `OFF` when firmware must require DTR explicitly.

### Hardware UART

USB serial is independent from the RP2040/RP2350 UART controllers. Configure
UART0 or UART1 with explicit pins and baud rate, then use bounded byte I/O:

```swift
let uart = try PicoUART(
    .uart0,
    baudRate: .hertz(115_200),
    tx: try PicoPin(0),
    rx: try PicoPin(1),
    chip: .compiled
)
try uart.write(Array("hello\r\n".utf8), timeout: .milliseconds(100))
let byte = try uart.read(timeout: .milliseconds(100))
```

For polling loops, `PicoUART.read()` returns one byte immediately or `nil` if
the RX FIFO is empty. Use the timeout overload when input must arrive before
the call returns.

Both USB CDC and UART are byte streams. PicoKit does not provide framing,
line buffering, parity/stop-bit configuration, or concurrent-access control.
`PicoUART.write(_:timeout:)` returns the full byte count on success. If the
deadline expires after only part of the buffer enters the UART FIFO, it throws
`PicoKitError.partialTransfer` with the accepted and expected counts.
`PicoUART.writeDMA(_:timeout:)` provides the same bounded-resource behavior for
prepared DMA output; a timeout aborts the active channel before returning.
`uart.actualBaudRate` reports the baud rate actually selected by the SDK.
The `chip` argument defaults to `.compiled`, which follows the firmware target.
Pass `.rp2040` or `.rp2350` explicitly when a driver intentionally targets a
specific chip family; UART0 uses TX/RX pairs
`0/1, 2/3, 12/13, 14/15, 16/17, 18/19, 28/29`, while UART1 uses
`4/5, 6/7, 8/9, 10/11, 20/21, 22/23, 24/25, 26/27` on RP2350. The
even-numbered alternate positions use the SDK's auxiliary UART mux.
