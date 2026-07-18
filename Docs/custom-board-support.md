# PicoKit custom-board support

PicoKit has named support for four Raspberry Pi boards, but the firmware
bridge can also compile against a custom Pico SDK board definition. The custom
board path is deliberately explicit: chip-level GPIO and peripherals remain
available, while board metadata and status-LED behavior are not guessed.

## Recognized versus custom metadata

`PicoBoard` recognizes only `.pico`, `.picoW`, `.pico2`, and `.pico2W`.
`PicoBoard.compiled` returns the exact recognized board selected by `PICO_BOARD`;
for a custom SDK board it returns `nil`. This is a useful distinction, not a
build failure:

```swift
guard let board = PicoBoard.compiled else {
    // The firmware is a custom board; use its explicit project configuration.
    Serial.println("custom board")
    return
}

Serial.println("board=\(board.cmakeName) chip=\(board.chip)")
```

Do not create a fake `PicoBoard` value by reusing `.pico` merely because the
custom board uses an RP2040. `.pico` also means the Pico SDK's board identity
and GPIO25 LED assumptions, not only the chip family. Use `PicoChip.compiled`
when the application needs only RP2040/RP2350 selection.

## What remains usable

Custom-board firmware can use chip-level APIs with the compiled chip:

```swift
let gpio = PicoGPIO.compiled
let reset = try PicoPin(6)

try gpio.configure(reset, mode: .output, initialState: .high)
try gpio.resetPulse(reset, activeState: .low, duration: .milliseconds(2))

let uart = try PicoUART(
    .uart0,
    baudRate: .hertz(115_200),
    tx: .gpio0,
    rx: .gpio1,
    chip: .compiled
)
```

The pins must match the custom board schematic and the selected RP2040/RP2350
function map. PicoKit still validates GPIO range, peripheral roles, shared
pins, and chip declarations. A custom PCB's connector labels do not change
the MCU's GPIO numbers; keep a board-specific translation table in the
application or project documentation.

`PicoI2C`, `PicoSPI`, `PicoPWM`, `PicoADC`, interrupts, watchdog, USB, and
`PicoUART` are likewise chip/peripheral APIs. Their successful construction
does not prove that a custom board routed the signal, populated pull-ups, or
connected the expected voltage domain.

## BoardLED is intentionally different

`BoardLED()` and `BoardLED(board:)` require a recognized Pico board identity.
On a custom board, construction reports
`PicoKitError.unavailable("unknown compiled Pico board")` or a board mismatch
instead of guessing an LED pin or invoking the wrong SDK status-LED path.

If the custom board has a GPIO-backed LED, use the schematic's pin explicitly:

```swift
let ledPin = try PicoPin(25) // Replace with the custom board's actual LED GPIO.
let gpio = PicoGPIO.compiled
try gpio.configure(ledPin, mode: .output, initialState: .low)
try gpio.write(ledPin, state: .high)
```

If the LED is controlled by a custom expander, power controller, or wireless
status device, keep that implementation in the application-owned driver. Do
not add a custom board case to PicoKit just to make a product LED look like a
standard board LED.

## Align the firmware build

The custom board definition belongs in the Pico SDK/CMake project, not in
PicoKit's private bridge. Keep these values aligned:

| Input | Responsibility |
| --- | --- |
| `PICO_BOARD` | selects the custom SDK board definition and compiled board metadata |
| `PICO_PLATFORM` or inferred chip | selects the RP2040/RP2350 platform |
| `PicoChip.compiled` / `PicoGPIO.compiled` | exposes the bridge's compiled chip to Swift |
| application pin table | maps schematic signals to GPIO and peripheral roles |
| optional LED driver | controls a custom board indicator explicitly |

For a direct CMake build, pass the SDK path and board explicitly:

```sh
cmake -S Firmware -B Firmware/build \
  -DPICO_SDK_PATH=/path/to/pico-sdk \
  -DPICO_BOARD=my_custom_board \
  -DPICO_PLATFORM=rp2040 \
  -G Ninja
cmake --build Firmware/build
```

Use the generated project's normal SwiftPico workflow when it supports the
custom board configuration. Do not edit generated build output below
`Firmware/build`; keep stable board and CMake inputs in project-owned files.

## Validate a custom board in layers

Start without hardware:

```sh
swift build
swift run PicoKitHostTests
sh Tests/peripheral-pin-mux-validation.sh
sh Tests/bridge-validation.sh
```

Then build the exact custom firmware with the real SDK and compiler. Host
validation proves typed values and error paths, but it uses RP2040 as the host
validation default and cannot prove custom board metadata, pin routing, power,
or the status LED.

For hardware acceptance, record the custom `PICO_BOARD` name, chip, SDK
revision, PicoKit commit, UF2, schematic pin map, supply voltage, and observed
response. Test one boundary at a time: boot/USB first, then GPIO/LED, then
UART/I2C/SPI/ADC/PWM or the application-specific peripheral. A successful
custom build is not evidence that a connector is wired as named.

## Custom-board checklist

Before sharing a custom-board firmware result, verify:

1. `PICO_BOARD` resolves to the intended SDK definition.
2. `PicoChip.compiled` matches the physical MCU family.
3. No application path assumes `PicoBoard.compiled` is non-`nil`.
4. `BoardLED` is replaced by an explicit LED driver when needed.
5. Every peripheral pin and voltage is checked against the schematic.
6. Host, firmware, and physical evidence are reported separately.

## Related documents

- [Board and pin planning](board-and-pin-planning.md) — signal maps and
  conflicts.
- [Peripheral pin validation](peripheral-pin-validation.md) — SDK function
  map checks.
- [Firmware build and bridge](firmware-build-and-bridge.md) — CMake and chip
  selection.
- [Hardware validation](hardware-validation.md) — physical evidence records.
- [Typed API and errors](typed-api-and-errors.md) — board and chip contracts.
