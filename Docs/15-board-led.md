# PicoKit Documentation

## Chapter 15: Board LED


Use the Pico SDK status LED abstraction:

```swift
let led = try BoardLED(board: .pico2W)
try led.set(.high)
try led.toggle()
```

The constructor initializes the board status LED. It throws `unavailable` when the SDK cannot provide one for the selected build or board.
