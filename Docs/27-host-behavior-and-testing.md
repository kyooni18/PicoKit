# PicoKit Documentation

## Chapter 27: Host behavior and testing


Host SwiftPM builds compile the public API without linking the Pico SDK. This permits validation logic and protocol-based code to be tested on macOS.

Hardware methods generally throw:

```swift
PicoKitError.unavailable("Pico SDK bridge")
```

when called outside a firmware build. `Clock.now()` returns `0`, interrupt polling returns `0`, and watchdog update is a no-op on the host.

Use `DigitalIO` test doubles to test GPIO-dependent logic without hardware.
