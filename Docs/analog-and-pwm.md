# PicoKit ADC and PWM

PicoKit exposes ADC readings as raw samples and PWM as a configured hardware
counter. The library validates the channel, pin, and requested frequency, but
it does not guess a board's reference voltage, sensor calibration, LED polarity,
or application-level unit conversion.

## ADC channels and ownership

`PicoADC` supports four external ADC GPIOs and the internal temperature
channel:

```swift
let adc = try PicoADC()

let potentiometer = try adc.read(.gpio26)
let secondInput = try analogRead(27, using: adc)
let temperatureRaw = try adc.read(.temperature)
```

The integer convenience form accepts only GPIO26 through GPIO29. A different
valid GPIO is still not an ADC input and throws
`PicoKitError.unavailable("ADC is only available on GPIO26...GPIO29")`:

```swift
let channel = ADCChannel.gpio26
let sample = try adc.read(channel)
```

Application code normally uses `analogRead(_:using:)` for a configured integer
pin or the typed `ADCChannel` overload.

Readings are raw `UInt16` values. The result is not automatically converted to
volts, degrees, or percentage because those conversions depend on reference
voltage, board layout, calibration, and the external sensor. Keep conversion
policy above PicoKit:

```swift
let raw = try adc.read(.gpio26)
let normalized = Double(raw) / Double(UInt16.max)
Serial.println("raw=\(raw) normalized=\(normalized)")
```

Treat that normalization as an application example, not a calibrated voltage
measurement. Confirm the ADC resolution and reference assumptions for the
compiled board and connected circuit before publishing physical units.

The ADC peripheral has shared channel-selection and temperature-sensor state.
The bridge initializes it once and serializes reads while changing that state,
so separate `PicoADC` values do not race the ADC selector. This protects the
conversion sequence; it does not make the rest of the application or its
sensor wiring concurrently owned. A single ADC owner is still the clearest
application design.

## Sampling a sensor in a loop

Initialize once, then sample at an interval suited to the sensor and logging
path:

```swift
let adc = try PicoADC()
let sampleInterval = try Duration.milliseconds(100)

while true {
    let sample = try adc.read(.gpio26)
    Serial.println("ADC26=\(sample)")
    try Clock.sleep(for: sampleInterval)
}
```

Do not print every sample in a high-rate acquisition loop. USB output can be
disconnected or slower than the ADC; use a bounded buffer and a purpose-built
DMA, PIO, or C path when continuous capture needs a deterministic rate.

ADC initialization and GPIO wiring still require physical checks:

- keep the input within the board's allowed analog voltage;
- connect a common ground;
- avoid driving an ADC pin from a conflicting digital or peripheral function;
- account for source impedance, filtering, and settling time;
- measure the reference and calibrate before converting samples to units.

PicoKit can reject an unavailable channel, but it cannot detect an over-voltage
input, a noisy source, or a swapped wire.

## PWM construction and actual frequency

Create one `PicoPWM` for an output pin and requested frequency:

```swift
let pwm = try PicoPWM(pin: .gpio0, frequency: .kilohertz(1))

Serial.println("PWM Hz=\(pwm.actualFrequency.hertz)")
Serial.println("counter top=\(pwm.counterTop)")
```

The SDK chooses an integer clock divider and wrap value. `actualFrequency` is
the frequency produced by those quantized settings; it may differ from the
request. `counterTop` is the highest usable counter level after configuration,
not necessarily `UInt16.max`. Always use the reported values when calculating
timing or direct counter updates.

PicoKit validates the requested frequency before changing the pin's PWM mux.
If setup is rejected, the previous GPIO/peripheral pin function remains
available to the caller. A successful second `PicoPWM` on the same pin still
changes that pin's mux, so keep one logical owner and do not construct
competing PWM objects for a pin.

## Duty-cycle APIs

There are two distinct ways to set the output level:

```swift
try pwm.setDutyCycle(32_768)           // normalized UInt16 range: 0...65535
try pwm.setCounterLevel(pwm.counterTop / 4) // direct hardware counter units
try pwm.analogWrite(UInt8(128))        // 8-bit convenience form
```

`setDutyCycle` scales the full `UInt16` input range onto the configured PWM
counter and saturates at the counter's top. `setCounterLevel` treats its input
as already-scaled counter units and also saturates at `counterTop`; use it when
a tight loop already produces hardware-level values.

The `UInt8` overload expands `0...255` to the full `UInt16` range by multiplying
by 257, so 0 maps to 0, 128 maps to 32896, and 255 maps to 65535. The `UInt16`
overload passes the full value to the normal duty-cycle path.

Do not confuse `counterTop` with the duty input range:

```swift
let quarterDuty = UInt16(UInt32(pwm.counterTop) / 4)
try pwm.setCounterLevel(quarterDuty)
try pwm.setDutyCycle(UInt16.max / 4)
```

These two calls are both approximately one-quarter duty, but they use
different input units. The first is a direct counter value; the second is a
normalized fraction.

The free helper is useful when keeping an Arduino-style pin number in a driver,
but it checks ownership before writing:

```swift
try analogWrite(0, UInt8(128), using: pwm)
```

Passing a different pin throws `PicoKitError.ownershipConflict` rather than
silently changing which PWM channel is driven.

## Backlights and polarity

`PicoBacklight` wraps PWM brightness and makes polarity explicit:

```swift
let display = try PicoBacklight(
    pin: .gpio0,
    frequency: .kilohertz(20),
    activeHigh: false
)

try display.setBrightness(UInt8(128))
try display.off()
try display.fullOn()
```

Brightness uses the same `UInt8`/`UInt16` scaling as `PicoPWM`. For an
active-high backlight, brightness maps directly to duty. For an active-low
backlight, PicoKit uses `UInt16.max - brightness`, so logical `off()` drives
the inactive high output and `fullOn()` drives the active low output.

The initializer immediately sets logical brightness to zero. It does not leave
the pin at an arbitrary previous duty level while the application finishes
setup. Confirm the polarity against the display controller or transistor
stage; `activeHigh` describes the electrical input to the backlight driver,
not necessarily the optical polarity of the display module.

## Update rate and workload

PWM hardware continues producing its waveform while Swift performs other
foreground work. Updating the duty cycle is separate from the PWM frequency:

```swift
let pwm = try PicoPWM(pin: .gpio0, frequency: .hertz(500))
var level: UInt16 = 0
var increasing = true

while true {
    try pwm.setDutyCycle(level)
    if increasing {
        if level > UInt16.max - 512 { increasing = false }
        else { level += 512 }
    } else {
        if level < 512 { increasing = true }
        else { level -= 512 }
    }
    try delay(10)
}
```

The loop's update interval does not change the PWM carrier frequency. It only
changes how quickly the application changes duty. Measure the physical output
if the load has filtering, inertia, or a driver stage that changes the visible
response.

## Host tests and physical evidence

Host tests can verify channel mapping, overload shape, error values, and that
hardware constructors report the unavailable SDK bridge:

```sh
swift build
swift run PicoKitHostTests
```

They cannot verify an ADC voltage, temperature calibration, PWM edge timing,
actual output frequency, or load current. Firmware evidence should record the
board/chip, requested and actual frequency, `counterTop`, duty input units,
ADC channel, raw sample, and conversion assumptions. A scope or logic analyzer
proves PWM period and duty; a calibrated source and meter prove ADC behavior.

## Related documents

- [Board and pin planning](board-and-pin-planning.md) — reserve ADC and PWM
  pins alongside buses and control lines.
- [GPIO and reset sequencing](gpio-and-reset-sequencing.md) — output electrical
  settings and startup levels.
- [DMA and buffer lifecycle](dma-and-buffer-lifecycle.md) — high-rate prepared
  transfers when a sampling loop outgrows foreground Swift.
- [Performance](performance.md) — repeatable CPU/PWM/ADC measurements.
- [PWM, ADC, I2C, and SPI](buses-and-analog.md) — transaction-oriented API
  summary and adjacent bus behavior.
