# PicoKit Documentation

## Chapter 23: GPIO interrupts


Enable edge detection:

```swift
let interrupts = PicoInterrupts()
let pin = try PicoPin(15)

try interrupts.enable(pin, edge: .either)
```

Supported edges:

```swift
.rising
.falling
.either
```

The C interrupt handler records SDK event bits in a per-pin array. Foreground Swift code retrieves and clears them:

```swift
let events = interrupts.takeEvents(for: pin)
if events != 0 {
    // Process the event outside the IRQ handler.
}
```

The bridge does not call Swift from the IRQ handler. This avoids allocation, runtime, and reentrancy hazards inside interrupt context.

Because event bits are coalesced, repeated identical edges may collapse into one pending bit before `takeEvents` is called. Use this API for event notification, not exact edge counting.
