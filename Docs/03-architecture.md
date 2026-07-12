# PicoKit Documentation

## Chapter 3: Architecture


PicoKit is split into four deliberately boring layers. The point is to keep
firmware code pleasant to write without letting Pico SDK details leak through
the rest of the package.

### `PicoKitCore`

`PicoKitCore` contains Foundation-free types that can run in firmware or host tests:

- `PicoChip`
- `PicoBoard`
- `PicoKitError`
- `PicoPin`
- `Duration`
- `Frequency`
- `PinMode`
- `PinState`
- `DigitalIO`
- Throwing GPIO helper functions

This layer never imports the Pico SDK or touches hardware, which is why it also
makes a good home for host tests and test doubles.

### `PicoKitHAL`

`PicoKitHAL` contains the Swift hardware abstraction layer. Its public types expose GPIO, serial, timers, PWM, ADC, I2C, SPI, interrupts, and watchdog operations.

When firmware is compiled, `PICOKIT_PICO_SDK` enables calls into the C bridge.
On a normal host SwiftPM build, the same hardware calls report
`PicoKitError.unavailable` instead of pretending there is a Pico attached.

### `PicoKit`

The `PicoKit` target is the public umbrella module. Firmware normally uses:

```swift
import PicoKit
```

On host builds, the module re-exports `PicoKitCore` and `PicoKitHAL`.

### Pico SDK bridge

`Firmware/PicoKitSDKBridge.c` is the only source file that directly includes Pico SDK headers. Swift imports its fixed-width C interface through `Firmware/BridgingHeader.h`.

The bridge intentionally stays small. It turns Swift operations into ordinary C
functions and keeps Pico SDK macros, inline functions, and register details out
of your application code.
