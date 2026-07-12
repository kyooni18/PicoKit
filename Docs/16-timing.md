# PicoKit Documentation

## Chapter 16: Timing


Use `Clock.now()` when you need the SDK's monotonic microsecond counter:

```swift
let microseconds = Clock.now()
```

For a deliberate blocking delay, pass an explicit duration:

```swift
try Clock.sleep(for: .milliseconds(500))
```

Because duration factories validate their input, you can construct the value
separately or keep the `try` at the call site:

```swift
try Clock.sleep(for: Duration.milliseconds(500))
```

If you already have a low-level context and prefer Arduino-style names:

```swift
try delay(500)
try delayMicroseconds(10)

let elapsedMilliseconds = millis()
let elapsedMicroseconds = micros()
```

For a compact sketch, use the high-level non-throwing helpers instead:

```swift
sleep(500)
sleepMicroseconds(10)
```

Every sleep API blocks the calling core. Keep them out of interrupt handlers and
out of code that has to service another peripheral immediately.
