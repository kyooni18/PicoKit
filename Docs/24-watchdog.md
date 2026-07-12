# PicoKit Documentation

## Chapter 24: Watchdog


Create the watchdog once, choose a timeout, and enable it after the rest of the
firmware is ready to service it:

```swift
let watchdog = PicoWatchdog()
try watchdog.enable(
    timeout: .seconds(2),
    pauseOnDebug: true
)
```

Feed it from the part of the main loop that proves the firmware is still alive:

```swift
watchdog.update()
```

The timeout is converted to milliseconds for the Pico SDK, so it must fit the
bridge's `UInt32` millisecond argument. Pick a value with enough headroom for a
slow but healthy loop.
