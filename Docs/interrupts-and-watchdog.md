# PicoKit interrupts and watchdogs

PicoKit keeps interrupt delivery deliberately small: the SDK callback records
edge bits for a GPIO, and foreground Swift polls and clears those bits. The
watchdog is similarly explicit: the application enables it once and feeds it
only after a complete healthy iteration. Neither API is an async scheduler,
event queue, or recovery policy.

## GPIO interrupt delivery

Create one `PicoInterrupts` owner, configure the input electrically, then
enable the edge you care about:

```swift
let gpio = PicoGPIO.compiled
let button = PicoPin.gpio15
let interrupts = PicoInterrupts()

try gpio.configure(button, mode: .input, pull: .up)
try interrupts.enable(button, edge: .falling)

while true {
    let events = interrupts.takeEvents(for: button)
    if events != 0 {
        Serial.println("button activity")
    }
    sleepMicroseconds(1_000)
}
```

`GPIOInterruptEdge` selects rising, falling, or either edge. The bridge stores
event bits in atomic per-pin storage. `takeEvents(for:)` atomically returns the
current word and clears it, so the next poll sees only activity recorded after
that exchange.

The result is a notification bitset, not an exact event count. Several equal
edges can collapse into one pending bit before foreground code polls it. The
event word also exposes SDK event bits rather than a count of transitions; for
portable application logic, test it for zero and then read the pin or inspect a
device state if the distinction matters.

The bridge never calls Swift from the GPIO callback. Do not allocate, sleep,
print, perform bus I/O, or call another PicoKit object from interrupt context.
Keep the callback path bounded and do all application work after
`takeEvents(for:)` returns.

## Enable, disable, and stale events

Enabling an interrupt clears any previously recorded event word before
installing the selected edge mask. Disabling turns off both rising and falling
delivery and clears pending state. Treat enable and disable as lifecycle
boundaries:

```swift
try interrupts.enable(button, edge: .falling)
// Poll and handle events here.
interrupts.disable(button)       // no pending event survives this call
try interrupts.enable(button, edge: .rising)
```

Do not interpret the first event after enabling as proof that the button was
pressed during the current application phase; the line may transition while
the SDK is installing the callback. Sample the idle level after configuration
when startup state matters.

## Debounce in the foreground

Mechanical inputs can produce multiple real edges. Because event storage is
already coalesced, use a foreground timestamp or state check for debounce; do
not try to turn `takeEvents` into a counter:

```swift
var lastPress = UInt64(0)
let debounce = UInt64(30_000)

while true {
    if interrupts.takeEvents(for: button) != 0 {
        let now = micros()
        if now - lastPress >= debounce {
            lastPress = now
            Serial.println("accepted press")
        }
    }
    sleepMicroseconds(1_000)
}
```

This policy assumes the clock is monotonic and that the loop polls often
enough for the application's latency requirement. If the button must never
lose transitions, use a hardware counter or a dedicated peripheral rather
than relying on a one-bit notification.

## Watchdog contract

Enable the watchdog after all fixed setup has succeeded and after the main loop
has a defined healthy iteration:

```swift
let watchdog = PicoWatchdog()
try watchdog.enable(timeout: .seconds(2), pauseOnDebug: true)

while true {
    let healthy = performOneCompleteIteration()
    if healthy {
        watchdog.update()
    }
}
```

`update()` resets the watchdog deadline and does not throw. Call it only after
the work that demonstrates liveness has completed. Feeding it at the top of a
loop can hide a stuck sensor read, bus transaction, or state machine because
the firmware would continue extending the deadline without proving useful
progress.

There is no public disable method. Treat the watchdog as a boot-to-reset
policy, enable it once, and keep its owner in the same foreground context as
the loop it protects. If setup fails before enabling it, enter the application's
defined safe failure state. If a required operation fails after enabling it,
do not feed the watchdog merely to keep a failed application alive.

## Time conversion and board limits

The SDK watchdog counter is configured in milliseconds. PicoKit rounds a
positive sub-millisecond `Duration` up to 1 ms, then validates the resulting
millisecond value before calling the SDK:

```swift
try watchdog.enable(timeout: .microseconds(1)) // becomes 1 ms
```

The maximum accepted value is board-specific:

| Compiled chip | Maximum watchdog timeout |
| --- | ---: |
| RP2040 | 8,388 ms |
| RP2350 | 16,777 ms |

An out-of-range value throws `PicoKitError.invalidTimeout` before watchdog
hardware is enabled. The limit is not a recommendation for loop latency: pick
a timeout larger than the slowest healthy iteration, including bounded UART,
USB, I2C, SPI, and DMA waits, while leaving enough margin for scheduling and
diagnostics.

`pauseOnDebug` defaults to `true`. Keep it enabled during ordinary debugger
bring-up when stopping at a breakpoint should not look like a watchdog reset.
Set it to `false` only when debugger stalls must be treated as real liveness
failures.

## A bounded healthy loop

Every operation inside a watchdog-protected loop should have a bounded failure
path. A single unbounded DMA or bus operation can prevent `update()` from being
reached, which is useful only if that operation's stall should reset the board.

```swift
let watchdog = PicoWatchdog()
let spi = try PicoSPI(
    .spi0,
    frequency: .megahertz(4),
    sck: .gpio18,
    mosi: .gpio19,
    miso: .gpio16,
    chipSelect: .gpio17
)
try watchdog.enable(timeout: .seconds(2))

while true {
    do {
        try spi.select()
        let sample = try spi.transfer([0x00, 0x00], timeout: .milliseconds(100))
        try spi.deselect()
        consume(sample)
        watchdog.update()
    } catch {
        try? spi.deselect()
        Serial.println("sample failed: \(error)")
        // Deliberately do not update the watchdog for this failed iteration.
        sleep(10)
    }
}
```

The timeout and watchdog budget are separate: the SPI call has 100 ms to
finish, while the board has up to 2 seconds to recover from repeated failed
iterations. Choose both from the device protocol and the desired reset time.
Always release chip select on the error path before retrying.

## Ownership and concurrency

`PicoInterrupts`, `PicoWatchdog`, GPIO objects, and peripheral objects do not
provide synchronization. Keep the interrupt owner, the pin's GPIO owner, and
the protected loop on one task/core. Never call `watchdog.update()` from an IRQ
handler as a substitute for proving that foreground work is healthy.

An interrupt event can arrive while foreground code is processing a previous
event. The atomic exchange preserves a later notification, but it does not
preserve multiplicity. A watchdog update can occur while an interrupt exists,
but that does not make the interrupted operation safe or reentrant.

## Host behavior and test boundaries

Host builds intentionally do not emulate hardware interrupts or watchdog
resets:

- `PicoInterrupts.enable` throws
  `PicoKitError.unavailable("Pico SDK bridge")`.
- `takeEvents(for:)` returns zero on the host.
- `PicoWatchdog.enable` throws the same unavailable error.
- `PicoWatchdog.update()` is a no-op on the host.

Host tests can still verify edge selection, timeout conversion, failure policy,
and application logic that consumes a fake event source. A firmware build can
prove that the bridge and SDK symbols link. A physical test is required to
prove actual edge delivery, watchdog reset timing, debugger pause behavior,
and interaction with a stalled external device.

## Verification checklist

Before relying on either mechanism, record:

1. The input's idle level, pull configuration, and expected edge.
2. Whether missing edges are acceptable; if not, choose a counting peripheral.
3. The worst healthy loop duration and every bounded operation inside it.
4. The watchdog timeout and board-specific maximum.
5. Whether debugger pauses should suspend watchdog expiry.
6. The physical evidence: captured GPIO edges, intentional watchdog reset, or
   a known recovery message after the reset.

Related commands for repository-level proof are:

```sh
swift build
swift run PicoKitHostTests
sh Tests/bridge-atomic.sh
sh Tests/bridge-validation.sh
```

## Related documents

- [GPIO and reset sequencing](gpio-and-reset-sequencing.md) — input pulls,
  output startup, and reset ownership.
- [Application design](application-design.md) — healthy loop structure and
  failure policy.
- [Runtime and testing](runtime-and-testing.md) — concurrency and evidence
  boundaries.
- [Explained examples](examples.md) — interrupt button and watchdog programs.
- [Failure diagnosis](failure-diagnosis.md) — classify software and physical
  failures by evidence.
