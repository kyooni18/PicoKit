# PicoKit Documentation

## GPIO interrupts and watchdog


Interrupts are intentionally kept simple: enable the edge you care about, then
poll for recorded events from normal foreground Swift code:

```swift
let interrupts = PicoInterrupts()
let pin = try PicoPin(15)

try interrupts.enable(pin, edge: .either)
```

The supported edge selections are:

```swift
.rising
.falling
.either
```

The C interrupt handler records SDK event bits in a per-pin array. Foreground
Swift code retrieves and clears them:

```swift
let events = interrupts.takeEvents(for: pin)
if events != 0 {
    // Process the event outside the IRQ handler.
}
```

The bridge never calls Swift from the IRQ handler. That avoids allocation,
runtime, and reentrancy hazards in interrupt context.

Because event bits are coalesced, repeated identical edges can collapse into one
pending bit before `takeEvents` runs. Treat this as event notification, not an
exact edge counter.

### Watchdog

Create and enable the watchdog once the main loop is ready to prove it is
healthy:

```swift
let watchdog = PicoWatchdog()
try watchdog.enable(timeout: .seconds(2), pauseOnDebug: true)

while true {
    // Work that must stay alive.
    watchdog.update()
}
```

The timeout must fit a `UInt32` count of milliseconds. Give it enough headroom
for a slow but healthy loop.
