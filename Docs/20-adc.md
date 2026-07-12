# PicoKit Documentation

## Chapter 20: ADC


Create one ADC instance before taking readings:

```swift
let adc = try PicoADC()
```

Then read either a GPIO-backed channel or the on-chip temperature channel:

```swift
let value = try adc.read(.gpio26)
let temperatureRaw = try adc.read(.temperature)
```

The available channel names are:

```swift
.gpio26
.gpio27
.gpio28
.gpio29
.temperature
```

If the channel is already expressed as a Pico GPIO number, the helpers are a
little shorter:

```swift
let value1 = try analogRead(.gpio26, using: adc)
let value2 = try analogRead(26, using: adc)
```

The integer helper accepts only GPIO 26 through GPIO 29. Readings are raw
`UInt16` values; converting them to volts or degrees belongs in application code
because the right conversion depends on your board and reference voltage.
