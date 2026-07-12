# PicoKit Documentation

## Chapter 3: Architecture


PicoKit is divided into four layers.

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

This layer does not import the Pico SDK or touch hardware.

### `PicoKitHAL`

`PicoKitHAL` contains the Swift hardware abstraction layer. Its public types expose GPIO, serial, timers, PWM, ADC, I2C, SPI, interrupts, and watchdog operations.

When compiled for firmware, the `PICOKIT_PICO_SDK` definition enables calls into the C bridge. In a normal host SwiftPM build, hardware calls report `PicoKitError.unavailable`.

### `PicoKit`

The `PicoKit` target is the public umbrella module. Firmware normally uses:

```swift
import PicoKit
```

On host builds, the module re-exports `PicoKitCore` and `PicoKitHAL`.

### Pico SDK bridge

`Firmware/PicoKitSDKBridge.c` is the only source file that directly includes Pico SDK headers. Swift imports its fixed-width C interface through `Firmware/BridgingHeader.h`.

The bridge is intentionally narrow. It converts Swift operations into ordinary C functions and keeps Pico SDK macros, inline functions, and register details out of application code.
