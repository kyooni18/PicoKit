# PicoKit Documentation

## Chapter 8: Building firmware


Build the current project:

```sh
./swiftpico build
```

Aliases:

```sh
./swiftpico b
```

Options include:

```text
--configuration debug|release
--swift-sdk SDK
--product PRODUCT
--verbose
```

For CMake firmware projects, PicoKit configures the project and runs the CMake build. The supplied firmware CMake file selects an Embedded Swift target according to the Pico platform:

| Pico platform | Swift target |
|---|---|
| RP2040 ARM | `armv6m-none-none-eabi` |
| RP2350 ARM | `armv7em-none-none-eabi` |
| RP2350 RISC-V | `riscv32-none-none-eabi` |

The CMake build creates a static Swift `PicoKit` library, links it with `PicoKitSDKBridge`, and then links the application executable against that library.

Remove build artifacts with:

```sh
./swiftpico clean
```
