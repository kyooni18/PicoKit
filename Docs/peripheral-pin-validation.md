# Peripheral pin-map validation

PicoKit validates a peripheral's alternate-function map before it enters the
Pico SDK initialization path. A GPIO number being in the valid range does not
make it valid for UART, I2C, or SPI. The selected board family, peripheral
instance, and signal role must agree with both the SDK headers and PicoKit's
hand-written Swift and C maps.

Use [board and pin planning](board-and-pin-planning.md) to choose a wiring map.
Use this guide when changing a map, reviewing a board-family port, or
diagnosing `PicoKitError.invalidPeripheralPin`.

## Three representations must agree

The repository keeps the same map in three places:

1. `Sources/PicoKitHAL/UART.swift` and `Buses.swift` reject invalid signal
   roles before hardware setup.
2. `Firmware/PicoKitSDKBridge.c` supplies the corresponding tables to the C
   bridge and performs firmware-side validation.
3. `Vendor/pico-sdk` headers define the SDK's `FUNCSEL` names for RP2040 and
   RP2350.

`Tests/peripheral-pin-mux-validation.sh` checks all three representations. It
checks every supported UART0/UART1, I2C0/I2C1, and SPI0/SPI1 signal position
for both chip families, then checks that the Swift and bridge arrays still
contain the expected values. Run it after changing a pin table or updating the
SDK revision:

```sh
sh Tests/peripheral-pin-mux-validation.sh
```

The gate is intentionally stronger than a host build. A host build can prove
that an array is syntactically valid, but only the SDK-header comparison can
prove that the array names a function the selected Pico SDK exposes.

## What constructor validation guarantees

Peripheral constructors validate their complete pin arguments before calling
the bridge:

| Peripheral | Checks before setup |
| --- | --- |
| `PicoUART` | TX and RX differ; each role is valid for the selected UART and chip; the explicit chip matches firmware |
| `PicoI2C` | SDA and SCL differ; each pin matches the instance's repeating function pattern |
| `PicoSPI` | SCK, MOSI, and optional MISO differ; each role is valid; optional chip select differs from bus signals |

An invalid map reports `PicoKitError.invalidPeripheralPin` and must not leave a
partially initialized peripheral behind. A same-pin conflict between two
separately constructed peripherals cannot be inferred by an individual
constructor; track application-wide ownership in the board plan and construct
each resource once.

## RP2040 and RP2350 are not interchangeable

UART alternate-function positions differ between the chip families. For
ordinary firmware, leave `chip` as `.compiled` so `PicoUART` checks the project
target. When testing a portable configuration table, pass `.rp2040` or
`.rp2350` explicitly and assert that each expected pin is accepted or rejected.

```swift
let rp2040UART = try PicoUART(
    .uart0,
    baudRate: .hertz(115_200),
    tx: .gpio0,
    rx: .gpio1,
    chip: .rp2040
)

let rp2350UART = try PicoUART(
    .uart0,
    baudRate: .hertz(115_200),
    tx: .gpio2,
    rx: .gpio3,
    chip: .rp2350
)
```

The constructors still require a firmware build for successful hardware
initialization. On a normal host build, valid construction reaches the SDK
boundary and reports `PicoKitError.unavailable("Pico SDK bridge")`; invalid
pins fail earlier with the typed pin error. This ordering makes host tests
useful for map validation without pretending to configure a board.

## Diagnose a rejected pin

Classify the failure before changing code:

1. Confirm the signal role and peripheral instance in the board schematic and
   [planning tables](board-and-pin-planning.md).
2. Confirm the chip argument matches the generated project's `PICO_BOARD`.
3. Run `sh Tests/peripheral-pin-mux-validation.sh` to distinguish a stale
   repository map from an application wiring mistake.
4. Run `swift build` and `swift run PicoKitHostTests` to check the portable
   typed path.
5. Build the selected firmware before investigating wires, voltage levels,
   pull-ups, or protocol framing.

If the repository gate fails, update the Swift and bridge tables together and
check the SDK header's `FUNCSEL` names. If the gate passes but an application
constructor rejects a pin, the application map is wrong for the selected
instance or chip. If construction succeeds but no device responds, pin mux
validation has already done its job; continue with [hardware validation](hardware-validation.md)
and electrical evidence.

## Related checks

```sh
sh Tests/peripheral-pin-mux-validation.sh
sh Tests/bridge-validation.sh
sh Tests/hardware-board-validation.sh
swift build
swift run PicoKitHostTests
```

The first gate proves function maps, the bridge gate proves C-side invariants,
the board gate proves board-selection and generated-project expectations, and
the host executable proves portable errors and overloads. None of these alone
proves that an external device is wired correctly; use a firmware image and
physical signal or device-response evidence for that claim.
