# PicoKit Documentation

## Chapter 4: Requirements


For a first firmware build, make sure these pieces are installed before you
start debugging Swift code:

- Swift 6-compatible Embedded Swift toolchain
- CMake 3.29 or newer
- Ninja
- Raspberry Pi Pico SDK
- A matching cross compiler
- `arm-none-eabi-gcc` for the standard ARM targets
- A USB connection for UF2 flashing or a supported debug probe for OpenOCD

The host tools currently target macOS 13 or newer.

Run the environment diagnostic command from the PicoKit checkout:

```sh
swift run swiftpico doctor
```

It checks the Swift installation, CMake, Ninja, ARM cross compiler, SDK bridge,
mounted boot volumes, and serial devices in one pass.
