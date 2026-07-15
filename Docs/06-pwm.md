# PicoKit Documentation

## PWM and ADC


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

`actualFrequency` reports the frequency produced after the SDK clock-divider
and counter-wrap quantization. For a hot loop that already produces
PWM-counter units, bypass the duty-scale division with the explicit fast path.
`counterTop` is the maximum level for the selected frequency; larger inputs
saturate at full duty.

```swift
try pwm.setCounterLevel(nextCounterValue)
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
try analogWrite(0, UInt8(128), using: pwm)
```

A mismatched pin throws `PicoKitError.ownershipConflict`.

Behind the scenes, the C bridge maps the requested frequency onto a Pico PWM
clock divider and wrap value. A combination the hardware cannot represent
becomes a setup failure instead of an approximate, surprising output.
PicoKit caches that setup metadata, so repeated duty updates only scale the
new value and update the configured PWM channel.

### ADC

Create one ADC instance, then read an external channel or the temperature
sensor:

```swift
let adc = try PicoADC()
let input = try adc.read(.gpio26)
let temperatureRaw = try adc.read(.temperature)
let sameInput = try analogRead(26, using: adc)
```

The external channels are `.gpio26`, `.gpio27`, `.gpio28`, and `.gpio29`.
Readings are raw `UInt16` values. Voltage and temperature conversion depend on
the board and reference voltage, so they remain application policy.

The bridge initializes each ADC GPIO and changes ADC selection only when
needed. Keep one `PicoADC` instance and repeatedly read the same channel for
the lowest per-sample setup overhead. Continuous or high-rate capture remains
a DMA use case.
