# PicoKit board and pin planning

Choose the board and pin map before writing the driver. PicoKit accepts GPIO
numbers `0...29`, but a valid GPIO is not automatically a valid UART, I2C, or
SPI signal. Peripheral constructors validate the selected function and reject
invalid combinations before the SDK bridge changes the pin mux.

This guide is a planning sheet for the current PicoKit implementation. It is
not a replacement for the board schematic or the external device datasheet.

## Board and chip map

| Swift board | CMake name | Chip | Onboard LED path |
| --- | --- | --- | --- |
| `.pico` | `pico` | RP2040 | GPIO25 |
| `.picoW` | `pico_w` | RP2040 | wireless status LED |
| `.pico2` | `pico2` | RP2350 | GPIO25 |
| `.pico2W` | `pico2_w` | RP2350 | wireless status LED |

`PicoBoard.configurationName` also accepts `pico-w` and `pico2-w`, ignores
surrounding whitespace, and is case-insensitive. `BoardLED()` follows the
compiled board, so prefer it when the application means “the LED on this
board.” Do not hard-code GPIO25 for a wireless board.

The board is selected by the generated project configuration. A typed
peripheral with a `chip` argument must agree with the compiled target; a
mismatch is reported as `PicoKitError.unavailable`, not silently redirected to
another chip.

## Plan pins in this order

1. Reserve power, ground, USB, and any board-specific status LED behavior.
2. Write down each external device's voltage, pull-up, chip-select, address,
   clock, and reset requirements.
3. Select one valid alternate-function map for every peripheral instance.
4. Check that chip-select, reset, interrupt, and power-control GPIOs do not
   collide with bus signals.
5. Construct the PicoKit object in a small test program before adding protocol
   decoding.
6. Verify the electrical signal with the appropriate instrument or device
   response; software pin validation cannot detect a swapped wire.

Keep the final map next to the application source. A useful record looks like:

```text
board: pico2_w
chip: rp2350
I2C0: SDA GPIO4, SCL GPIO5, 400 kHz
SPI0: SCK GPIO18, MOSI GPIO19, MISO GPIO16, CS GPIO17, mode 0
button: GPIO15, input pull-up, falling edge
sensor voltage: 3.3 V
```

## UART maps

The tables list valid TX and RX pins independently. TX and RX must be different
pins, and both must belong to the same valid pair for the selected controller
and chip.

### RP2040

| Controller | TX pins | RX pins |
| --- | --- | --- |
| `UART0` | 0, 12, 16, 28 | 1, 13, 17, 29 |
| `UART1` | 4, 8, 20, 24 | 5, 9, 21, 25 |

Example:

```swift
let uart = try PicoUART(
    .uart0,
    baudRate: .hertz(115_200),
    tx: .gpio0,
    rx: .gpio1,
    chip: .rp2040
)
```

### RP2350

| Controller | TX pins | RX pins |
| --- | --- | --- |
| `UART0` | 0, 2, 12, 14, 16, 18, 28 | 1, 3, 13, 15, 17, 19, 29 |
| `UART1` | 4, 6, 8, 10, 20, 22, 24, 26 | 5, 7, 9, 11, 21, 23, 25, 27 |

Use `chip: .compiled` in ordinary firmware so the constructor checks the
project-selected target. `actualBaudRate` reports the SDK's quantized result;
it does not configure a peer's baud rate or framing policy.

## I2C maps

PicoKit validates the repeating GPIO pattern rather than maintaining a board-
specific table:

| Controller | SDA condition | SCL condition | Valid pairs in GPIO0...29 |
| --- | --- | --- | --- |
| `I2C0` | `pin % 4 == 0` | `pin % 4 == 1` | 0/1, 4/5, 8/9, 12/13, 16/17, 20/21, 24/25, 28/29 |
| `I2C1` | `pin % 4 == 2` | `pin % 4 == 3` | 2/3, 6/7, 10/11, 14/15, 18/19, 22/23, 26/27 |

SDA and SCL must differ. The external bus also needs appropriate pull-ups and
compatible voltage levels; PicoKit does not add or measure those electrical
properties.

```swift
let i2c = try PicoI2C(
    .i2c0,
    frequency: .kilohertz(400),
    sda: .gpio4,
    scl: .gpio5
)
```

I2C addresses must be in the normal 7-bit range `0x08...0x77`. A transaction
timeout is required and is bounded by the SDK's `UInt32` microsecond limit.
Use `writeRead` for a register prefix followed by a repeated START, and set
`stop: false` explicitly when composing a transaction yourself.

## SPI maps

The current function maps are:

| Controller | SCK | MOSI | MISO |
| --- | --- | --- | --- |
| `SPI0` | 2, 6, 18, 22 | 3, 7, 19, 23 | 0, 4, 16, 20 |
| `SPI1` | 10, 14, 26 | 11, 15, 27 | 8, 12, 24, 28 |

SCK, MOSI, and MISO must be different. An optional chip-select pin must also
be distinct from all three signals. When `chipSelect` is supplied, PicoKit
configures it as an active-low output that is high while idle:

```swift
let spi = try PicoSPI(
    .spi0,
    frequency: .megahertz(8),
    sck: .gpio18,
    mosi: .gpio19,
    miso: .gpio16,
    mode: .mode0,
    chipSelect: .gpio17
)

try spi.select()
let response = try spi.transfer([0x9F, 0, 0, 0], timeout: .milliseconds(100))
try spi.deselect()
```

The SPI map validates signal roles, not the device's mode, clock maximum,
command format, or required inter-frame delay. `transfer` and
`transferDMA` require MISO; write-only SPI can omit it. `dataBits: .sixteen`
selects the `UInt16` overloads.

## ADC, PWM, GPIO, and interrupt pins

| Feature | Current rule |
| --- | --- |
| General GPIO | GPIO0 through GPIO29 |
| ADC | GPIO26, GPIO27, GPIO28, GPIO29, or internal temperature |
| PWM | Any validated GPIO; the SDK chooses slice/channel and reports `counterTop` |
| GPIO interrupt | Any GPIO0 through GPIO29; edge is rising, falling, or either |

ADC values are raw `UInt16` samples. PicoKit does not convert them to volts or
temperature because reference voltage, calibration, and board conditions are
application-specific. PWM frequency is quantized by the SDK; inspect
`actualFrequency` instead of assuming the requested value was exact.

For a button with a pull-up and falling-edge event:

```swift
let button = try PicoPin(15)
let interrupts = PicoInterrupts()
let gpio = PicoGPIO.compiled

try gpio.configure(button, mode: .input, pull: .up)
try interrupts.enable(button, edge: .falling)

while true {
    if interrupts.takeEvents(for: button) != 0 {
        Serial.println("button pressed")
    }
    sleepMicroseconds(100)
}
```

The interrupt bridge records event bits and can coalesce repeated edges before
foreground polling. It is not an exact event queue.

## Detect conflicts before flashing

Create a small configuration checklist or test for every project:

```swift
let used: Set<PicoPin> = [
    .gpio4, .gpio5,       // I2C0
    .gpio16, .gpio17,
    .gpio18, .gpio19      // SPI0 MISO/CS/SCK/MOSI
]
precondition(used.count == 6)
```

The typed constructors catch conflicts within one peripheral, such as shared
SDA/SCL or SCK/MOSI/MISO. They cannot know that two separately constructed
peripherals are competing for the same pin or DMA channel. Make cross-device
ownership explicit in application code and construct each resource once.

## Verification ladder

After choosing a map, verify in increasing cost order:

1. Host-check pin and unit construction with `swift build` and
   `swift run PicoKitHostTests`.
2. Build generated templates and board variants with
   `sh Tests/integration/generated-templates.sh`.
3. Build the selected firmware and inspect `actualFrequency` or
   `actualBaudRate` in a diagnostic output.
4. Use `swiftpico monitor --reconnect` for USB evidence.
5. Use a logic analyzer, scope, or the external device's identity response to
   prove the physical map and protocol.

If a constructor reports `invalidPeripheralPin`, fix the map. If construction
succeeds but the bus is silent, inspect power, grounds, pull-ups, chip select,
logic levels, and protocol framing before changing the SwiftPico flash path.

## Related documents

- [Application design](application-design.md) — organize a growing firmware loop.
- [PWM, ADC, I2C, and SPI](buses-and-analog.md) — transaction and DMA behavior.
- [USB serial and UART](serial-and-uart.md) — USB CDC and UART semantics.
- [Hardware guide](hardware-guide.md) — errors, timing, ownership, and limits.
- [API reference](api-reference.md) — exact declarations and overloads.
