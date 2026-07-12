# PicoKit

PicoKit is an SDK-backed Swift Embedded library for Raspberry Pi Pico (RP2040)
and Pico 2 (RP2350). It uses a narrow C bridge over the official Pico SDK;
Swift firmware does not access peripheral registers directly.

## Architecture

- `Sources/PicoKitCLI`: host CLI for diagnostics, project creation, build,
  flash, debugging, and serial monitoring.
- `Sources/PicoKitCore`: Foundation-free validation, units, errors, boards,
  and protocols.
- `Sources/PicoKitHAL`: public GPIO, board LED, timer, USB/UART, PWM, ADC,
  I2C, SPI, GPIO IRQ, and watchdog APIs.
- `Firmware/PicoKitSDKBridge.c`: the only source that includes Pico SDK APIs.

`Firmware/CMakeLists.txt` compiles the three Swift layers into a `PicoKit`
library, then links firmware sources against it. The previous direct-register
prototype is isolated in `Legacy/UnsafeMMIO` and excluded from every build.

## Requirements

```sh
git clone --recurse-submodules https://github.com/kyooni18/PicoKit.git
cd PicoKit
swift run picokit doctor
```

Firmware builds need CMake, Ninja, an Embedded Swift toolchain, and the Pico
SDK's matching cross compiler (`arm-none-eabi-gcc` for the standard Pico and
Pico 2 ARM builds). `picokit doctor` reports the host-side prerequisites.

## Firmware API

The library uses validated pins, explicit units, throwing failures, and bounded
operations:

```swift
import PicoKit

let led = try BoardLED(board: .pico)
let period = try Duration.milliseconds(500)

while true {
    try led.toggle()
    try Clock.sleep(for: period)
}
```

GPIO pins are `PicoPin`, never unchecked integers:

```swift
let gpio = PicoGPIO(chip: .rp2040)
let pin = try PicoPin(15)
try gpio.setMode(pin, mode: .output)
try gpio.write(pin, state: .high)
```

The Arduino-style helpers are available when that spelling is clearer:

```swift
try pinMode(15, .output, using: gpio)
try digitalWrite(15, .high, using: gpio)
let state = try digitalRead(15, using: gpio)
```

For small sketches, the high-level facade removes setup ceremony and
`try`/optional handling. It fails fast on invalid configuration; the low-level
throwing APIs above remain available for applications that need recovery:

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

The same API is available on an explicit `Pico` runtime, which is convenient
for tests and alternate GPIO implementations:

```swift
let pico = Pico()
pico.pinMode(15, .output)
pico.digitalWrite(15, .high)
```

PWM uses the same `analogWrite` name, with an 8-bit duty cycle:

```swift
let pwm = try PicoPWM(pin: try PicoPin(0), frequency: .kilohertz(1))
try analogWrite(0, 128, using: pwm) // 50% duty cycle
```

Timing helpers are throwing and SDK-backed too: `try delay(500)`,
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

Each SDK peripheral has one owner: do not create competing instances for the
same UART, I2C, SPI, PWM slice, or watchdog. Instances are not thread-safe;
use each from one foreground execution context. GPIO interrupts only record
edge events in the C bridge—read them from foreground Swift code and never
allocate, sleep, or call Swift from an IRQ handler.

## Host workflow

```sh
swift run PicoKitHostTests
sh Tests/cli-integration.sh
# On a firmware toolchain host:
sh Tests/firmware-matrix.sh
swift run picokit init --board pico2_w --name Blink --template blink
cd ../Blink
./picokit build
./picokit flash
./picokit monitor --reconnect
```

Supported canonical boards are `pico`, `pico_w`, `pico2`, and `pico2_w`.
`pico-w` and `pico2-w` are accepted input aliases. Generated `picokit.json`
contains the exact CMake board identifier, dynamic product target and UF2 name,
and the reusable PicoKit checkout path. Templates include `blink`, `serial`,
`adc`, `pwm`, `i2c`, `spi`, `interrupt`, and `watchdog`.

`picokit debug` reads OpenOCD settings from the project config. `picokit doctor`
reports Swift, CMake, Ninja, SDK bridge, boot volume, and serial devices.
Use [`Tests/hardware/README.md`](Tests/hardware/README.md) as the required
physical validation matrix; it is deliberately separate from build validation.
