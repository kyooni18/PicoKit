# PicoKit Documentation

## Chapter 27: Host behavior and testing


Host SwiftPM builds compile the public API without linking the Pico SDK. That is
useful: validation logic and protocol-based code can be tested on macOS before a
board is connected.

On the host, hardware methods generally throw:

```swift
PicoKitError.unavailable("Pico SDK bridge")
```

when called outside a firmware build. `Clock.now()` returns `0`, interrupt polling returns `0`, and watchdog update is a no-op on the host.

Use `DigitalIO` test doubles to exercise GPIO-dependent logic without hardware.
The high-level `Pico(gpio:)` initializer makes the same approach work for a
sketch-style API.
