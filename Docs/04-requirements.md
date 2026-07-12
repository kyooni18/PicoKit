# PicoKit Documentation

## Chapter 4: Requirements


A firmware build requires:

- Swift 6-compatible Embedded Swift toolchain
- CMake 3.29 or newer
- Ninja
- Raspberry Pi Pico SDK
- A matching cross compiler
- `arm-none-eabi-gcc` for the standard ARM targets
- A USB connection for UF2 flashing or a supported debug probe for OpenOCD

The Swift package itself declares macOS 13 or newer for its host tools.

Run the environment diagnostic command from the PicoKit checkout:

```sh
swift run picokit doctor
```

The command checks the local Swift installation, CMake, Ninja, ARM cross compiler, SDK bridge, mounted boot volumes, and serial devices.
