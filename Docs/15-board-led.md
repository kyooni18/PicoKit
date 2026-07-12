# PicoKit Documentation

## Chapter 15: Board LED


When you want the board's built-in status LED rather than a specific GPIO pin,
use the Pico SDK's board-aware abstraction:

```swift
let led = try BoardLED(board: .pico2W)
try led.set(.high)
try led.toggle()
```

The constructor performs the board-specific setup. It throws `unavailable` when
the selected board or build has no SDK-provided status LED, which is preferable
to silently driving the wrong pin.
