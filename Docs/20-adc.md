# PicoKit Documentation

## Chapter 20: ADC


Initialize the ADC:

```swift
let adc = try PicoADC()
```

Read an explicit channel:

```swift
let value = try adc.read(.gpio26)
let temperatureRaw = try adc.read(.temperature)
```

Available channels:

```swift
.gpio26
.gpio27
.gpio28
.gpio29
.temperature
```

Helper forms:

```swift
let value1 = try analogRead(.gpio26, using: adc)
let value2 = try analogRead(26, using: adc)
```

The integer helper accepts only GPIO 26 through GPIO 29. ADC readings are raw `UInt16` values; voltage and temperature conversion are left to application code.
