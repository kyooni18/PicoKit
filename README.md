# PicoKit

PicoKit lets you write Raspberry Pi Pico firmware in Swift without having to
live in register definitions or Pico SDK macros. It supports the RP2040 Pico
family and the RP2350 Pico 2 family, while keeping the official Pico SDK on the
other side of a small C bridge.

Host-side package builds support macOS 13 or newer on both Apple Silicon
(`arm64`) and Intel (`x86_64`). Firmware output still targets the selected
Raspberry Pi Pico board.

## Architecture

- `Sources/PicoKitCore`: Foundation-free validation, units, errors, boards,
  and protocols.
- `Sources/PicoKitHAL`: public GPIO, board LED, timer, USB/UART, PWM, ADC,
  I2C, SPI, GPIO IRQ, and watchdog APIs.
- `Firmware/PicoKitSDKBridge.c`: the only source that includes Pico SDK APIs.

In practice, application code imports one module—`PicoKit`. The CMake build
compiles the Swift layers into that library and links it to the SDK bridge. The
old direct-register prototype lives in `Legacy/UnsafeMMIO` for reference only;
it is not part of a normal build.

## SwiftPico CLI

Project creation, firmware builds, USB flashing, and serial monitoring live in
the separate [SwiftPico CLI](https://github.com/kyooni18/swiftpico) tool:

```sh
brew tap kyooni18/swiftpico https://github.com/kyooni18/swiftpico
brew install swiftpico
swiftpico init --board pico2_w --name Blink --template blink
```

The initializer creates a normal standalone Swift package. It writes the
`Package.swift`, board configuration, firmware CMake entrypoint, and local
launcher needed for a PicoKit project, so the PicoKit checkout itself can stay
focused on the reusable library.

PicoKit pins the exact Pico SDK commit it needs, but does not embed that SDK in
each project. `swiftpico build` downloads it once into the shared SwiftPico
cache and reuses it for every project that needs that revision. Set
`SWIFTPICO_CACHE_DIR` to put that cache on a shared disk or a CI cache. Direct
CMake builds can instead pass `-DPICO_SDK_PATH=/path/to/pico-sdk`.

## Requirements

Install the CLI and check the host toolchain first:

```sh
brew tap kyooni18/swiftpico https://github.com/kyooni18/swiftpico
brew install swiftpico
swiftpico doctor
```

To work on PicoKit itself, clone the library and run its host validation:

```sh
git clone --recurse-submodules https://github.com/kyooni18/PicoKit.git
cd PicoKit
swift build
swift run PicoKitHostTests
```

Firmware builds need CMake, Ninja, an Embedded Swift toolchain, and the Pico
SDK's matching cross compiler (`arm-none-eabi-gcc` for the standard Pico and
Pico 2 ARM builds). Run `swiftpico doctor` before chasing build errors—it tells
you which host-side prerequisite is missing.

## Documentation

The maintained documentation is organized by workflow and peripheral:

- [Getting started](Docs/getting-started.md)
- [Explained examples](Docs/examples.md)
- [Hardware guide](Docs/hardware-guide.md)
- [USB serial and UART](Docs/serial-and-uart.md)
- [PWM, ADC, I2C, and SPI](Docs/buses-and-analog.md)
- [Runtime and testing](Docs/runtime-and-testing.md)
- [External libraries](Docs/external-libraries.md)
- [Performance](Docs/performance.md)
- [API reference](Docs/api-reference.md)

## Firmware API

There are two ways to write PicoKit code. The lower-level API uses validated
pins, explicit units, and thrown errors. It is the right fit when a failure is
something your application can handle:

```swift
import PicoKit

let led = try BoardLED()
let period = try Duration.milliseconds(500)

while true {
    try led.toggle()
    try Clock.sleep(for: period)
}
```

At that layer, GPIO pins are `PicoPin`, never unchecked integers:

```swift
let gpio = PicoGPIO.compiled
let pin = try PicoPin(15)
try gpio.setMode(pin, mode: .output)
try gpio.write(pin, state: .high)
```

If you like the familiar Arduino spelling but still want error handling, use
the throwing helpers with an explicit GPIO controller:

```swift
try pinMode(15, .output, using: gpio)
try digitalWrite(15, .high, using: gpio)
let state = try digitalRead(15, using: gpio)
```

For a small sketch, the high-level facade removes setup ceremony and
`try`/optional handling. It intentionally fails fast when the configuration is
wrong, so the lower-level API above remains available whenever recovery matters:

```swift
import PicoKit

pinMode(15, .output)
Serial.println("starting")

while true {
    if let byte = Serial.read() {
        Serial.write(byte)
    }
    digitalWrite(15, .high)
    sleep(500)
    digitalWrite(15, .low)
    sleep(500)
}
```

See [the hardware guide](Docs/hardware-guide.md) for complete sketch, serial,
timing, testing, and low-level comparison examples.

The same API is available on an explicit `Pico` runtime. This is useful when a
test or an alternate GPIO implementation should own the runtime:

```swift
let pico = Pico()
pico.pinMode(15, .output)
pico.digitalWrite(15, .high)
```

PWM keeps the same `analogWrite` name, with an 8-bit duty cycle:

```swift
let pwm = try PicoPWM(pin: try PicoPin(0), frequency: .kilohertz(1))
try analogWrite(0, UInt8(128), using: pwm) // 50% duty cycle
```

The lower-level timing helpers are SDK-backed too: `try delay(500)`,
`try delayMicroseconds(10)`, `millis()`, and `micros()`.

ADC follows the same helper style: `let raw = try analogRead(26, using: adc)`.

UART operations specify both baud units and a timeout:

```swift
let uart = try PicoUART(
    .uart0,
    baudRate: .hertz(115_200),
    tx: try PicoPin(0),
    rx: try PicoPin(1),
    chip: .compiled
)
_ = try uart.write(Array("hello\r\n".utf8), timeout: .milliseconds(100))
```

Treat each SDK peripheral as something your firmware owns in one place. Do not
create competing instances for the same UART, I2C controller, SPI controller,
PWM slice, or watchdog. Instances are not thread-safe, so use them from one
foreground execution context. GPIO interrupts only record edge events in the C
bridge; read them from foreground Swift code and never allocate, sleep, or call
Swift from an IRQ handler.

## Host workflow

```sh
swift build
swift run PicoKitHostTests
sh Tests/api-reference.sh
```

The temporary-project integration creates a disposable SwiftPico serial-echo
project against this checkout, builds its UF2, and verifies the picotool flash
arguments without requiring attached hardware:

```sh
sh Tests/integration/generated-project.sh
# Verify generated Blink templates for all supported boards.
sh Tests/integration/generated-blink.sh
# Typecheck every SwiftPico template against the Embedded Swift PicoKit module.
sh Tests/integration/generated-templates.sh
```

To verify the documented no-USB firmware mode on every supported board alias, run:

```sh
sh Tests/integration/usb-disabled.sh
# Verify the documented direct CMake path discovers Embedded Swift itself.
sh Tests/integration/direct-cmake.sh
# Verify compiler environment overrides and invalid override rejection.
sh Tests/integration/compiler-discovery.sh
# Verify USB CMake option bounds without compiling firmware.
sh Tests/integration/cmake-options.sh
```

`PICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS` defaults to `0`. Use a positive value to
wait a bounded number of milliseconds for CDC, or `-1` to wait indefinitely as
supported by the Pico SDK.
`PICOKIT_USB_POST_CONNECT_WAIT_DELAY_MS` defaults to `50` ms and can be set to
`0` or a larger value to tune terminal settling after CDC enumeration.
Set `PICOKIT_USB_CONNECTION_WITHOUT_DTR=ON` when the host does not assert DTR;
the default is `ON`. `Serial.connected` therefore reports USB readiness without
requiring modem-control changes from the monitor.

Set `PICO_HARDWARE_TEST=1` to additionally flash one detected Pico and verify
an exact binary USB CDC echo. A board in BOOTSEL mode is flashed even without a
serial node; after flashing, echo is skipped only when the board remains
USB-controlled in BOOTSEL. Select the connected family with
`PICO_TEST_BOARD=pico` (default), `pico_w`, `pico2`, or `pico2_w`; the script
checks BOOTSEL chip identity before flashing. If no single device is present,
that optional section reports `SKIPPED`. SwiftPico also owns CLI and multi-board tests:

Set `PICO_HARDWARE_REQUIRE_CDC=1` to make missing CDC enumeration fail instead
of reporting the flash-only diagnostic; the firmware image is checked for its
USB startup hook and TinyUSB symbols before flashing.

```sh
cd ../SwiftPico
sh Tests/cli-integration.sh
# On a firmware toolchain host:
sh Tests/firmware-matrix.sh
```

The repository CI runs this matrix on an arm64 macOS runner and also verifies
the USB-disabled firmware path.

Create and use a project from any working directory:

```sh
swiftpico init --board pico2_w --name Blink --template blink
cd Blink
./swiftpico build
./swiftpico flash
./swiftpico monitor --reconnect
```

Supported canonical boards are `pico`, `pico_w`, `pico2`, and `pico2_w`; the
hyphenated `pico-w` and `pico2-w` spellings work too. The generated
`swiftpico.json` records the CMake board identifier, product target, UF2 output,
and PicoKit dependency source. Start with `blink` or `serial`, then explore the
`adc`, `pwm`, `i2c`, `spi`, `interrupt`, and `watchdog` templates as needed.

`swiftpico debug` reads OpenOCD settings from the project config. `swiftpico doctor`
reports Swift, CMake, Ninja, SDK bridge, boot volume, and serial devices.
Use [`Tests/hardware/README.md`](Tests/hardware/README.md) as the required
physical validation matrix; it is deliberately separate from build validation.

## External libraries

PicoKit firmware projects can fetch C dependencies with CMake and compile
Embedded Swift package targets through the extension points described in [the
external-library guide](Docs/integration.md). Keep the dependency
CMake file in the project so the precise targets and source directories linked
into firmware remain reviewable.
