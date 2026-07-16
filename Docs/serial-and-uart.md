# USB serial and UART

PicoKit exposes two independent serial paths. `USBSerial` and `Serial` use the
board's USB CDC stdio connection. `PicoUART` uses one of the RP2040/RP2350
hardware UART controllers and physical TX/RX pins. Choose based on wiring and
protocol needs; neither path adds line parsing or message framing.

## USB CDC sketch API

The global `Serial` value initializes USB stdio lazily. It is convenient for
fixed firmware where a configuration failure should stop execution:

```swift
Serial.write("booting")
Serial.print(" mode=")
Serial.println("diagnostic")
Serial.println()
```

`write` and `print` do not append a newline. `println` does. Byte overloads
preserve NUL and non-UTF-8 data, so a raw echo loop is straightforward:

```swift
while true {
    if let byte = Serial.read() {
        Serial.write(byte)
    }
}
```

`Serial.available` checks for a byte without consuming it. PicoKit retains one
lookahead byte internally so `available` followed by `read()` does not lose
data. Both calls are nonblocking.

## Throwing USB CDC API

Create one `USBSerial` when disconnects, initialization failures, or timeouts
need an application-controlled recovery path:

```swift
let serial = try USBSerial()
try serial.write(Array("ready\r\n".utf8))

do {
    let command = try serial.read(timeout: .seconds(5))
    try serial.write(command)
} catch PicoKitError.timedOut {
    try serial.write("no command received")
}
```

The unbounded `read()` overload is actually a nonblocking poll and returns
`nil` when no byte is waiting. `isConnected` is a point-in-time USB readiness
check, not a guarantee that the following write will succeed.

## Startup and connection options

USB CDC startup is controlled by CMake cache values:

| Option | Default | Meaning |
|---|---:|---|
| `PICOKIT_ENABLE_USB` | `ON` | Include USB stdio support. |
| `PICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS` | `0` | Do not wait; positive values bound the wait; `-1` waits indefinitely. |
| `PICOKIT_USB_POST_CONNECT_WAIT_DELAY_MS` | `50` | Extra settling time after connection; `0` disables it. |
| `PICOKIT_USB_CONNECTION_WITHOUT_DTR` | `ON` | Treat USB enumeration as ready without requiring host DTR. |
| `PICOKIT_USB_STDOUT_TIMEOUT_US` | `10000` | Bound individual USB diagnostic writes. |

Avoid an indefinite startup wait in unattended firmware. A bounded wait can
preserve early diagnostics while still allowing the control loop to start when
no host terminal is attached.

## Monitoring

Use SwiftPico's interactive byte terminal:

```sh
./swiftpico devices
./swiftpico monitor --reconnect
```

Pass `--device /dev/cu.usbmodem...` when automatic selection is ambiguous.
`--reconnect` waits for the device to return after reset or a short USB
disconnect. Press Ctrl-C to leave the monitor.

## Hardware UART

Configure the controller, baud rate, and pins once, then reuse the instance:

```swift
let uart = try PicoUART(
    .uart0,
    baudRate: .hertz(115_200),
    tx: .gpio0,
    rx: .gpio1,
    chip: .compiled
)

let sent = try uart.write(
    Array("hello\r\n".utf8),
    timeout: .milliseconds(100)
)
let byte = try uart.read(timeout: .milliseconds(100))
```

`actualBaudRate` reports the SDK-selected rate after divider quantization. A
bounded write returns its full count on success. If the deadline expires after
partial progress, it throws `PicoKitError.partialTransfer` with accepted and
expected counts.

UART0 supports TX/RX pairs `0/1, 2/3, 12/13, 14/15, 16/17, 18/19, 28/29`.
UART1 supports `4/5, 6/7, 8/9, 10/11, 20/21, 22/23, 24/25, 26/27` on RP2350.
TX and RX must be different pins and valid for the selected controller/chip.

## UART DMA and ownership

For a sufficiently large prepared output buffer, `writeDMA` reduces per-byte
CPU work while remaining synchronous:

```swift
try uart.writeDMA(payload, timeout: .milliseconds(250))
uart.releaseDMAChannel()
```

The UART retains its claimed channel between calls. Release it when another
subsystem needs DMA, or let the object release it during deinitialization. A
timed-out DMA write aborts the active channel before returning. DMA does not
increase the configured baud rate, and it is usually the wrong path for
single-byte commands.

Give each hardware UART one logical owner. PicoKit does not serialize access,
configure parity/stop bits, buffer lines, or define a packet protocol.
