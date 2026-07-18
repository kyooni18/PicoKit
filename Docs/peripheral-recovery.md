# Recovering from PicoKit peripheral failures

PicoKit reports failures; it does not silently retry a device operation. That
boundary leaves retry policy with the application, where the protocol's
idempotency, safety state, and user-visible fault behavior are known.

A useful recovery path answers four questions in order:

1. Did the failure happen before any bus or GPIO side effect?
2. Is repeating the operation safe for this device protocol?
3. Can the peripheral be returned to a known electrical state?
4. How many bounded attempts are acceptable before the application enters a
   safe or latched fault state?

## Classify the typed error

Start with the `PicoKitError` case instead of matching only its description:

| Error | Typical meaning | Default policy |
| --- | --- | --- |
| `invalidPin`, `invalidPeripheralPin`, `invalidAddress`, `invalidFrequency`, `invalidTimeout` | application configuration is invalid | fix configuration; do not retry |
| `timedOut` | the operation exceeded its bounded wait | retry only if the protocol permits it and the device may recover |
| `partialTransfer` | a transfer had a side effect but did not finish | do not blindly replay; resynchronize first |
| `ioFailure` | the bridge or SDK reported an operation failure | capture status, then use device-specific recovery policy |
| `unavailable` | host, SDK bridge, board, or selected feature is unavailable | distinguish build/connection state from a transient device fault |
| `ownershipConflict` | two roles or resources violate an ownership rule | fix lifetime or pin/channel allocation; do not retry |

The categories are intentionally conservative. A timeout on a read may be
safe to repeat; a timeout after a write may have changed a register or started
an actuator command. The device datasheet, not the error name alone, decides
whether a replay is valid.

## Keep the resource state explicit

Construct a peripheral once and keep recovery state in the driver that owns it.
Do not create a new `PicoI2C`, `PicoSPI`, or `PicoUART` for every attempt. That
can reconfigure pins, consume another DMA channel, or hide the real owner.

For SPI, chip select is an application-owned transaction boundary. Return it
to its inactive level when a throwing operation exits early:

```swift
func readIdentifier(from spi: PicoSPI) throws(PicoKitError) -> [UInt8] {
    try spi.select()
    defer { try? spi.deselect() }
    return try spi.transfer([0x9F, 0, 0, 0], timeout: .milliseconds(100))
}
```

If a device requires a reset after a failed transaction, use the GPIO reset
sequence rather than an arbitrary sleep and write sequence:

```swift
try gpio.resetPulse(
    .gpio6,
    activeState: .low,
    duration: .milliseconds(2)
)
```

`resetPulse` leaves the pin configured as an output at the inactive level. The
reset duration and polarity still come from the device datasheet, and the
reset line must belong to the same application owner as the peripheral.

## Retry only bounded, idempotent work

Keep attempt count and backoff finite. A retry loop should not feed a watchdog
or claim health merely because it is still making attempts:

```swift
func readWithRetry(from i2c: PicoI2C) throws(PicoKitError) -> [UInt8] {
    let timeout = try Duration.milliseconds(20)
    var lastError: PicoKitError?

    for attempt in 0..<3 {
        do {
            return try i2c.writeRead(
                address: 0x48,
                bytes: [0x00],
                count: 2,
                timeout: timeout
            )
        } catch let error as PicoKitError {
            lastError = error
            guard case .timedOut = error, attempt < 2 else { throw error }
            try delayMicroseconds(UInt64((attempt + 1) * 500))
        }
    }

    throw lastError ?? .timedOut(operation: "I2C sensor read")
}
```

This pattern is appropriate only when the register read is safe to repeat.
For a command write, include a device-level sequence number, status query, or
reset/resynchronization step instead of replaying bytes after
`partialTransfer`. Keep backoff below the surrounding watchdog budget and
application deadline; see [timing and deadlines](timing-and-deadlines.md).

## Make failure outputs safe

When an external device controls motion, power, heat, or another hazard, the
failure branch must define the output state explicitly. A disconnected sensor
must not leave the last actuator command running merely because a read failed:

```swift
do {
    let sample = try readWithRetry(from: i2c)
    try motor.apply(sample)
} catch {
    try? motor.stop()
    Serial.println("sensor fault: \(error)")
    enterLatchedFaultState()
}
```

Best-effort diagnostic output is separate from the safety action. USB may be
disconnected, so `Serial.println` cannot be the mechanism that makes the
system safe. If the safe state itself fails, stop retrying the same operation
and escalate to the board's defined fault behavior.

## Recovery boundaries by bus

### I2C

Use `writeRead` for a register prefix and repeated START. It validates the
complete composed transaction before issuing its write portion, which prevents
invalid read arguments from creating a partial prefix write. After a real bus
timeout, the device may still hold SDA or be mid-command; follow the device's
bus-recovery procedure before retrying. PicoKit does not bit-bang recovery or
invent a protocol-specific reset.

### SPI

Always restore chip select high after a failed transaction. A retry may require
reselecting the device, resending its command prefix, or resetting it first.
For 16-bit transfers, preserve frame alignment; do not retry a partial byte
count as though it were a complete word transfer.

### UART

`partialTransfer` means bytes were accepted before the deadline. A peer may
have acted on those bytes. Resynchronize with a framing marker, explicit
acknowledgement, or device reset before replaying a command. DMA timeout
overloads clean up their channel before returning, so the prepared buffer may
be released, but protocol state still needs application recovery.

### USB CDC

USB connection state is a point-in-time observation. A successful connection
check does not guarantee the next write will be delivered. Use acknowledgements
for commands whose delivery matters, and keep the control path independent of
the monitor. USB diagnostic failures should not prevent a safe actuator
shutdown.

## Test recovery without hardware

Host tests can prove policy even though they cannot prove the electrical reset
or bus recovery:

- inject a `DigitalIO` fake that records reset and safe-state writes;
- inject a fake driver or protocol boundary that throws `timedOut` on the
  first attempt and succeeds on the next;
- assert that `partialTransfer` is not replayed automatically;
- assert the retry count, backoff policy, and final safe output;
- assert that an invalid configuration fails before any fake event occurs.

Use [driver testing](driver-testing.md) for recording fakes and
[hardware validation](hardware-validation.md) to separate host policy tests
from firmware and physical evidence. A passing retry test proves control flow,
not that a stuck bus will recover on a particular board.

## Recovery checklist

Before shipping a driver, record:

1. Which errors are retryable and which are configuration or ownership bugs.
2. Whether every write is idempotent, acknowledged, or resynchronized before
   replay.
3. How chip select, reset, DMA channels, and safe outputs are restored.
4. The maximum attempts and total time allowed inside the watchdog window.
5. What remains safe when USB logging is disconnected.
6. Which host, firmware, and physical tests provide evidence for each claim.

## Related documents

- [Typed API and errors](typed-api-and-errors.md) — error cases and unit
  validation.
- [GPIO and reset sequencing](gpio-and-reset-sequencing.md) — glitch-free
  outputs and reset pulses.
- [I2C and SPI transactions](i2c-and-spi-transactions.md) — transaction
  boundaries and frame behavior.
- [DMA and buffer lifecycle](dma-and-buffer-lifecycle.md) — timeout cleanup
  and buffer ownership.
- [Application design](application-design.md) — loop and failure policies.
