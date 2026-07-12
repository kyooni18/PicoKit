# PicoKit Documentation

## Chapter 8: Building firmware


From the generated project directory, build the firmware with:

```sh
./swiftpico build
```

If you prefer short commands while iterating:

```sh
./swiftpico b
```

Useful build options include:

```text
--configuration debug|release
--swift-sdk SDK
--product PRODUCT
--verbose
```

For CMake firmware projects, SwiftPico configures CMake and then asks it to
build. The supplied CMake file chooses the Embedded Swift target that matches
your Pico platform:

| Pico platform | Swift target |
|---|---|
| RP2040 ARM | `armv6m-none-none-eabi` |
| RP2350 ARM | `armv7em-none-none-eabi` |
| RP2350 RISC-V | `riscv32-none-none-eabi` |

The result is a static Swift `PicoKit` library linked with `PicoKitSDKBridge`,
followed by your application executable. If the build fails before compiling
Swift, `swiftpico doctor` is usually the fastest way to spot a missing host
tool.

To start over with a clean firmware build directory:

```sh
./swiftpico clean
```
