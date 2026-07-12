# PicoKit Documentation

## Chapter 19: PWM


Create a PWM output for a pin:

```swift
let pwm = try PicoPWM(
    pin: PicoPin(0),
    frequency: .kilohertz(1)
)
```

Set full 16-bit duty-cycle resolution:

```swift
try pwm.setDutyCycle(32_768)
```

Arduino-style methods are also available:

```swift
try pwm.analogWrite(UInt8(128))
try pwm.analogWrite(UInt16(32_768))
```

The free helper checks that the supplied pin matches the pin owned by the PWM object:

```swift
try analogWrite(0, 128, using: pwm)
```

A mismatched pin throws `PicoKitError.ownershipConflict`.

The C bridge maps the requested frequency to a Pico PWM clock divider and wrap value. Unsupported frequency/divider combinations produce a setup failure.
