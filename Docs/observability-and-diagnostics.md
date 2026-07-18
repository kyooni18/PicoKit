# PicoKit observability and diagnostics

Diagnostics are another workload competing for the same firmware time, USB
connection, and serial bandwidth as the control loop. Design them so the
application remains safe and useful when no monitor is attached, when a byte is
not valid UTF-8, or when an interrupt or bus operation is timing-sensitive.

PicoKit provides byte transport and connection state, not a logging framework
or a line protocol. The application owns message format, sampling rate,
sequence numbers, and what must be persisted or acknowledged.

## Separate evidence from control

Keep diagnostics out of decisions that must remain safe:

```swift
do {
    let sample = try readSensor()
    try actuator.apply(sample)
} catch {
    try? actuator.stop()
    report(.sensorFailure(error))
    enterFaultState()
}
```

`report` may do nothing when USB is disconnected. The safe actuator action and
fault transition must not depend on `Serial.connected`, a successful write, or
the monitor being open. This is especially important for startup, watchdog
recovery, and external-device failures.

## Pick a transport by claim

| Need | Transport | Appropriate evidence |
| --- | --- | --- |
| Human-readable bring-up | `Serial.println` | monitor transcript with board and image identity |
| Binary echo or packet capture | `Serial.write([UInt8])` or `USBSerial.write` | exact sent/received byte sequence |
| Bounded command input | `USBSerial.read(timeout:)` | typed timeout/disconnect result |
| External device communication | `PicoUART` | loopback or peer acknowledgement on the selected pins |
| Long-term control independent of USB | GPIO/UART/device-specific path | physical signal or device response |

USB CDC is a diagnostic channel unless the application explicitly defines and
verifies a command protocol. A successful `Serial.connected` check is only a
point-in-time snapshot; the host can disconnect before the next write.

## Make messages identifiable

Include enough context to identify a run without relying on log order:

```swift
var sequence: UInt32 = 0
let board = PicoBoard.pico2 // Use the board selected by this firmware target.

func report(_ event: String) {
    guard Serial.connected else { return }
    sequence &+= 1
    Serial.println("seq=\(sequence) board=\(board.cmakeName) event=\(event)")
}

report("boot")
report("sensor_ready")
```

For release diagnostics, include the board, chip, firmware product or commit,
event name, sequence number, and relevant status/error code. Avoid embedding a
large formatted sensor dump in a tight loop. Emit a periodic heartbeat or
state transition instead, and keep the sampling path independent of whether a
monitor is connected.

Do not assume `String` is a protocol. If a host or fixture must compare data,
define a byte layout and use the byte overloads. `Serial.write` and
`USBSerial.write` preserve NUL and non-UTF-8 bytes; newline text is only a
presentation choice.

## Startup and reconnect policy

Choose explicitly whether startup diagnostics are best effort or must wait for
a host:

```swift
// Best effort: the control loop starts even without a monitor.
if Serial.connected {
    Serial.println("ready")
}

// One-shot diagnostic: wait only when the product requires a host handshake.
let deadline = millis() + 2_000
while !Serial.connected && millis() < deadline {
    sleep(10)
}
if Serial.connected {
    Serial.println("ready")
}
```

The second form needs a documented policy for a clock wrap and for the no-host
case. Avoid an indefinite wait in unattended firmware. The CMake options
`PICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS`,
`PICOKIT_USB_POST_CONNECT_WAIT_DELAY_MS`, and
`PICOKIT_USB_CONNECTION_WITHOUT_DTR` affect USB startup readiness; they do not
turn a diagnostic write into a guaranteed delivery mechanism.

## Bound logging cost

Logging can change the behavior it is intended to observe. Keep it out of
interrupt context, DMA buffer ownership, and the critical portion of a bus
transaction:

- GPIO interrupt handlers record edge bits; foreground code formats and emits
  the event later.
- DMA transfers own their prepared buffers until completion or timeout; do not
  reuse a buffer as a log scratch area while a transfer may still read it.
- Chip select should remain under the transaction driver's control; do not
  print between bytes when the peripheral requires a continuous frame.
- A slow or disconnected USB host must not consume the entire watchdog window.

If full records matter more than control-loop responsiveness, measure that
tradeoff explicitly with the [performance](performance.md) fixture. A log line
that makes a timeout disappear is evidence of an altered workload, not proof
that the underlying peripheral was fixed.

## Report errors without losing their type

Use the typed error for policy and a compact representation for diagnostics:

```swift
do {
    _ = try i2c.read(
        address: 0x48,
        count: 2,
        timeout: .milliseconds(20)
    )
} catch let error as PicoKitError {
    switch error {
    case .timedOut:
        report("sensor_timeout")
    case .partialTransfer:
        report("sensor_partial_transfer")
    default:
        report("sensor_error_\(error)")
    }
}
```

Do not make a recovery decision by parsing `PicoKitError.description`. Keep
the case and associated values in application state, then format a stable
event code for the human or host-facing channel. See [peripheral recovery](peripheral-recovery.md)
for retry and safe-state policy.

## Host and physical evidence

Host tests can verify message formatting, sequence behavior, binary payloads,
and the policy used when `connected` is false. They cannot prove a USB host
received a byte or that logging preserved a control-loop deadline. Use the
appropriate evidence layer:

```sh
swift build
swift run PicoKitHostTests
sh Tests/integration/usb-serial-status-firmware.sh
```

The firmware status fixture checks disconnected and connected USB behavior and
raw-byte echo. A physical run should record board identity, image commit,
serial device path, exact bytes, and whether the monitor was connected before
the first message. For UART or a device protocol, use a loopback, peer
acknowledgement, analyzer, or scope; USB output alone does not prove those
paths.

## Diagnostic checklist

Before relying on a diagnostic channel during bring-up or release testing,
confirm:

1. control and safety behavior continues without USB;
2. startup waits are bounded and the no-host path is explicit;
3. binary fixtures use byte APIs and compare exact bytes;
4. interrupt, DMA, and bus critical paths do not format or block on logs;
5. error handling matches typed cases before formatting output;
6. every physical claim includes board, image, connection, and captured
   evidence.

## Related documents

- [USB serial and UART](serial-and-uart.md) — connection and byte semantics.
- [Failure diagnosis](failure-diagnosis.md) — evidence-driven debugging.
- [Peripheral recovery](peripheral-recovery.md) — safe retry and fault policy.
- [Performance](performance.md) — measure logging and timing effects.
- [Hardware validation](hardware-validation.md) — physical evidence records.
