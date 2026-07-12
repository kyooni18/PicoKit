# PicoKit Documentation

## Chapter 16: Timing


Read the monotonic SDK timer:

```swift
let microseconds = Clock.now()
```

Block the current core:

```swift
try Clock.sleep(for: .milliseconds(500))
```

Because the duration factory throws, construct it separately or use `try` with the call:

```swift
try Clock.sleep(for: Duration.milliseconds(500))
```

Arduino-compatible helpers:

```swift
try delay(500)
try delayMicroseconds(10)

let elapsedMilliseconds = millis()
let elapsedMicroseconds = micros()
```

High-level non-throwing helpers:

```swift
sleep(500)
sleepMicroseconds(10)
```

All sleep operations block the calling core. They must not be called from an interrupt handler.
