# PicoKit timing and deadline contracts

PicoKit has three different kinds of time control: sleeping the calling core,
bounding one peripheral operation, and resetting a loop that stops making
progress. They are related but interchangeable only by accident. Choose the
primitive that matches the failure you need to handle.

## Use the right time primitive

| Need | API | Failure or result |
| --- | --- | --- |
| Pace a known foreground loop | `Clock.sleep`, `delay`, or `delayMicroseconds` | blocks the calling core; zero delay is a no-op |
| Wait for one USB/UART/bus operation | the operation's `timeout: Duration` overload | throws `timedOut`, `partialTransfer`, `ioFailure`, or an unavailable error |
| Detect a wedged healthy loop | `PicoWatchdog` | hardware reset after the configured deadline |
| Observe elapsed firmware time | `Clock.now()`, `micros()`, or `millis()` | monotonic microsecond time on firmware; zero on host builds |

Do not use a sleep as a substitute for a transaction timeout. A sleep delays
the caller but cannot stop a bus or UART operation that is already blocked. Do
not use a watchdog as ordinary retry control: a watchdog reset is a system
failure boundary, not a recoverable per-device error.

## Construct explicit units

`Duration` stores positive microseconds and rejects zero and multiplication
overflow. The factories keep units visible at the call site:

```swift
let debounce = try Duration.milliseconds(20)
let sensorTimeout = try Duration.milliseconds(100)
let watchdogWindow = try Duration.seconds(2)

try Clock.sleep(for: debounce)
```

`Frequency` follows the same explicit-unit pattern for clocks and baud rates.
Keep a duration value with the operation it bounds instead of passing a naked
integer through several driver layers. A `Duration` is a validated interval,
not an absolute deadline and not a scheduler handle.

## Sleeping is foreground-only

`Clock.sleep(for:)` blocks the calling core and cannot be called from an
interrupt handler. The Arduino-compatible spellings are equivalent for their
respective units:

```swift
try delay(1)                 // milliseconds
try delayMicroseconds(250)   // microseconds
```

Zero is intentionally a valid no-op for `delay(0)` and
`delayMicroseconds(0)`. A positive `Clock.sleep` or nonzero delay reaches the
SDK on firmware. On a normal host build, `Clock.sleep(for:)` throws
`PicoKitError.unavailable("Pico SDK bridge")`; the host path does not pretend
to wait for hardware time.

Use a bounded foreground loop when other work must continue:

```swift
let samplePeriod = try Duration.milliseconds(10)

while true {
    sampleInputs()
    updateOutputs()
    try Clock.sleep(for: samplePeriod)
}
```

The sleep is only pacing. The body must still finish before the next intended
sample, and a watchdog budget must include the slowest complete iteration.

## Operation timeouts are error boundaries

Use a throwing timeout overload when a peripheral may wait for external state:

```swift
let timeout = try Duration.milliseconds(100)
let response = try spi.transfer([0x9F, 0, 0, 0], timeout: timeout)
```

The exact scope belongs to the operation:

- USB CDC timed reads use the supplied duration; USB diagnostic writes use the
  `PICOKIT_USB_STDOUT_TIMEOUT_US` CMake bound. UART timed reads and writes use
  their supplied duration and report timeout or partial progress rather than
  silently dropping the result.
- I2C `write`, `read`, and `writeRead` require a timeout. `writeRead` applies
  the timeout independently to its write and read portions.
- SPI timed reads and writes bound the peripheral wait for the requested
  transfer. DMA timeout overloads abort and clean up the channel before
  returning, so a prepared buffer can be released after the call.

An operation timeout does not guarantee that a disconnected or electrically
invalid device is distinguishable from every other failure. Inspect the typed
`PicoKitError` case and retain the operation name in higher-level diagnostics.
See [typed API and errors](typed-api-and-errors.md) and [failure diagnosis](failure-diagnosis.md).

## Keep an application budget

When several operations must fit inside one application-level budget, measure
the firmware clock around the sequence and pass bounded intervals to each
operation. Do not subtract host wall-clock timestamps from firmware values.

```swift
let budget = try Duration.milliseconds(250)
let started = Clock.now()

func remaining(from started: UInt64, budget: Duration) -> Duration? {
    let elapsed = Clock.now() &- started
    guard elapsed < budget.microseconds else { return nil }
    return try? Duration.microseconds(budget.microseconds - elapsed)
}

guard let firstTimeout = remaining(from: started, budget: budget) else {
    throw PicoKitError.timedOut(operation: "sensor transaction")
}
let prefix = try i2c.writeRead(
    address: 0x40,
    bytes: [0x00],
    count: 2,
    timeout: firstTimeout
)
```

For a simple one-device transaction, pass one fixed timeout directly. Use an
application budget only when multiple waits genuinely share a deadline; it
adds policy and should stay in the driver layer rather than the hardware
abstraction.

The example uses `&-` only for defensive unsigned arithmetic. Firmware clock
values are expected to advance monotonically; if a test double or a clock wrap
produces an unexpected value, fail the transaction rather than extending a
deadline indefinitely.

## Watchdog budgets are reset budgets

Enable the watchdog after the loop can demonstrate health, then update it once
per complete iteration:

```swift
let watchdog = PicoWatchdog()
try watchdog.enable(timeout: .seconds(2), pauseOnDebug: true)

while true {
    try serviceOneIteration()
    watchdog.update()
}
```

The timeout must cover the slowest normal iteration, including bounded bus
waits, USB logging policy, and any deliberate sleeps. Updating the watchdog at
the top of a loop can keep a stuck body alive forever; update it after the work
that proves the loop is healthy. The watchdog timeout is converted upward to
whole milliseconds, so a sub-millisecond duration is not rounded down to zero.
RP2040 and RP2350 have different maximum watchdog windows; see
[interrupts and watchdogs](interrupts-and-watchdog.md).

## Host behavior and verification

Host validation proves unit conversion, overflow rejection, error mapping, and
driver control flow. It does not prove elapsed-time behavior:

- `Clock.now()`, `millis()`, and `micros()` return zero on the host path.
- A positive `Clock.sleep` reports the unavailable SDK bridge on the host.
- Hardware operation calls report unavailable rather than blocking on a fake
  clock.
- The watchdog update is a no-op on the host; its input conversion can still
  be tested.

Run the portable checks first:

```sh
swift build
swift run PicoKitHostTests
sh Tests/bridge-validation.sh
```

Use firmware builds and a physical device, logic analyzer, or scope when the
claim concerns actual delay, bus timing, watchdog reset, or peripheral
response. Record those as separate evidence from host timing tests; a zero
host clock is an intentional boundary, not a failed test.

## Related documents

- [Interrupts and watchdogs](interrupts-and-watchdog.md) — event polling and
  watchdog limits.
- [I2C and SPI transactions](i2c-and-spi-transactions.md) — STOP, repeated
  START, transfer, and timeout behavior.
- [DMA and buffer lifecycle](dma-and-buffer-lifecycle.md) — bounded DMA waits
  and safe buffer release.
- [USB serial and UART](serial-and-uart.md) — connection and timed I/O policy.
- [Runtime and testing](runtime-and-testing.md) — ownership and host limits.
