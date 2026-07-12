# PicoKit Documentation

## Chapter 24: Watchdog


Create and enable the watchdog:

```swift
let watchdog = PicoWatchdog()
try watchdog.enable(
    timeout: .seconds(2),
    pauseOnDebug: true
)
```

Feed it periodically:

```swift
watchdog.update()
```

The timeout is converted to milliseconds for the Pico SDK. The value must fit the bridge’s `UInt32` millisecond argument.
