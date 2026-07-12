# PicoKit

PicoKit lets you write Raspberry Pi Pico firmware in Swift without having to
live in register definitions or Pico SDK macros. It supports the RP2040 Pico
family and the RP2350 Pico 2 family, while keeping the official Pico SDK on the
other side of a small C bridge.

## Architecture

- `Sources/SwiftPicoCLI`: host CLI for diagnostics, project creation, build,
  flash, debugging, and serial monitoring.
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

Build the project tool once if you are working from this checkout:

```sh
swift build -c release --product swiftpico
```

After that, starting a project is a single command:

```sh
swiftpico init --board pico2_w --name Blink --template blink
```

The initializer gives you the boring but necessary pieces: a `Package.swift`
that depends on PicoKit, a board-aware `swiftpico.json`, a firmware CMake
entrypoint, and a local launcher. It resolves PicoKit and initializes the Pico
SDK submodule as part of setup. If you are offline, add `--skip-resolve` and
resolve the package later.

The old `picokit` executable remains as a compatibility alias.

## Requirements

```sh
git clone --recurse-submodules https://github.com/kyooni18/PicoKit.git
cd PicoKit
swift run swiftpico doctor
```

Firmware builds need CMake, Ninja, an Embedded Swift toolchain, and the Pico
SDK's matching cross compiler (`arm-none-eabi-gcc` for the standard Pico and
Pico 2 ARM builds). Run `swiftpico doctor` before chasing build errors—it tells
you which host-side prerequisite is missing.

## Firmware API

There are two ways to write PicoKit code. The lower-level API uses validated
pins, explicit units, and thrown errors. It is the right fit when a failure is
something your application can handle:

```swift
import PicoKit

let led = try BoardLED(board: .pico)
let period = try Duration.milliseconds(500)

while true {
    try led.toggle()
    try Clock.sleep(for: period)
}
```

At that layer, GPIO pins are `PicoPin`, never unchecked integers:

```swift
let gpio = PicoGPIO(chip: .rp2040)
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
    digitalWrite(15, .high)
    sleep(500)
    digitalWrite(15, .low)
    sleep(500)
}
```

See [the high-level API guide](Docs/33-high-level-api.md) for complete sketch,
serial, timing, testing, and low-level comparison examples.

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
try analogWrite(0, 128, using: pwm) // 50% duty cycle
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
    rx: try PicoPin(1)
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
swift run PicoKitHostTests
sh Tests/cli-integration.sh
# On a firmware toolchain host:
sh Tests/firmware-matrix.sh
swift run swiftpico init --board pico2_w --name Blink --template blink
cd ../Blink
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
