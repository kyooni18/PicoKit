# PicoKit

PicoKit is a small utility kit for **Swift Embedded** firmware on Raspberry Pi
Pico (RP2040) and Pico 2 (RP2350). It supplies familiar Arduino-style GPIO and
serial APIs, while `picokit` provides a host command line for build context,
UF2 flashing, OpenOCD debugging, and serial monitoring.

## Clone

The Raspberry Pi Pico SDK is tracked as a Git submodule. Clone PicoKit with its
dependencies, or initialize them after a normal clone:

```sh
git clone --recurse-submodules https://github.com/kyooni18/PicoKit.git
cd PicoKit
# For an existing clone:
git submodule update --init --recursive
```

The SDK is kept outside SwiftPM because it is a CMake firmware dependency. The
CLI passes `Vendor/pico-sdk` to the firmware build automatically.

## Firmware API

Add the package to an Embedded Swift executable target, then use GPIO directly:

```swift
import PicoKit

let gpio = PicoGPIO(chip: .rp2040) // use .rp2350 for Pico 2
pinMode(25, .output, using: gpio)
digitalWrite(25, .high, using: gpio)
gpio.toggle(25)
```

`PicoGPIO` configures pins for the SIO peripheral and exposes the Pico-family
GPIO pins 0 through 29. For an object-oriented spelling, call the same methods
on `gpio` directly.

UART0 on GPIO 0 (TX) and GPIO 1 (RX):

```swift
let gpio = PicoGPIO.rp2040
let serial = PicoUART(.uart0, baudRate: 115_200)
serial.configurePins(tx: 0, rx: 1, using: gpio)
serial.print("Hello from Swift Embedded")
```

`ByteSink` and `ByteSource` keep console utilities portable: implement them for
USB CDC, a UART driver, a buffer, or a test fake. `PicoUART` is a minimal PL011
driver intended for the default 48 MHz peripheral clock.

## Public API

The public surface is intentionally small. Use `PicoBoard` and `PicoChip` for
board selection; `PicoGPIO`, `PicoADC`, `PicoPWM`, `PicoI2C`, `PicoSPI`, and
`PicoUART` for peripherals; and the Arduino-style `digitalWrite`, `analogRead`,
`delay`, `millis`, and `micros` helpers for simple sketches.

Configuration values are iterable value types: `PinMode`, `PinState`,
`ADCChannel`, `I2CBusSpeed`, `SPIBitOrder`, `SPIMode`, and `PWMMode`.
`PicoADC.readMillivolts()` makes its unit explicit, and `ElapsedTimer` is the
non-blocking elapsed-time helper. The older `readVoltage()`, `setDivider(_:)`,
`PWMPhaseCorrect`, and `Millis` spellings remain as deprecated compatibility
aliases.

## Host workflow

Keep new firmware projects beside the PicoKit checkout. Running `init` from the
PicoKit directory automatically creates a sibling directory, so project source
and build artifacts do not get mixed into the utility kit:

```sh
cd /path/to/PicoKit
swift run picokit init --board pico2_w --name Blink
cd ../Blink
swift run --package-path ../PicoKit picokit build
swift run --package-path ../PicoKit picokit flash
```

Use `--path` when you want a specific location:

```sh
swift run picokit init --board pico2_w --name Blink --path ~/PicoProjects/Blink
```

The generated project contains `picokit.json`, `Sources/Blink/main.swift`, and
an embedded Swift/CMake `Firmware` directory. Its configuration points at the
shared Pico SDK in the PicoKit checkout, so the SDK is not copied into every
project. `build` produces `Firmware/build/picokit-blink.uf2`; `flash` asks a
running firmware to reboot into BOOTSEL through USB, then copies the UF2. A
manual BOOTSEL press is only needed if the board is not running PicoKit firmware
with the USB reset interface enabled.

Example context:

```json
{
  "board": "pico2_w",
  "firmwareDirectory": "Firmware",
  "picoSDKPath": "/path/to/PicoKit/Vendor/pico-sdk",
  "product": "Blink",
  "configuration": "release",
  "uf2": "Firmware/build/picokit-blink.uf2",
  "openOCD": "openocd",
  "openOCDConfig": ["interface/cmsis-dap.cfg", "target/rp2350.cfg"]
}
```

`flash` automatically finds `RP2350`, `RPI-RP2350`, and `RPI-RP2` boot volumes, or
accepts `--volume`. `debug` starts OpenOCD from the saved config, and `monitor`
configures and streams a serial device:

```sh
picokit debug
picokit monitor --device /dev/cu.usbmodem1101 --baud 115200
picokit list
```

## Verify

```sh
swift build
swift run picokit help
```
