# PicoKit Documentation

## Chapter 19: PWM


Create one PWM output for the pin you intend to drive:

```swift
let pwm = try PicoPWM(
    pin: try PicoPin(0),
    frequency: .kilohertz(1)
)
```

For the full 16-bit range, set the duty cycle directly:

```swift
try pwm.setDutyCycle(32_768)
```

The `analogWrite` spelling is available when that reads more naturally in a
sketch:

```swift
try pwm.analogWrite(UInt8(128))
try pwm.analogWrite(UInt16(32_768))
```

The free helper keeps the pin at the call site and checks that it matches the
pin owned by the PWM object:

```swift
try analogWrite(0, 128, using: pwm)
```

A mismatched pin throws `PicoKitError.ownershipConflict`.

Behind the scenes, the C bridge maps the requested frequency onto a Pico PWM
clock divider and wrap value. A combination the hardware cannot represent
becomes a setup failure instead of an approximate, surprising output.
