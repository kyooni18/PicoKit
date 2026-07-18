# PicoKit failure diagnosis

When firmware does not behave, identify the layer that has actually failed
before changing code or wiring. A successful host build proves that Swift can
compile for the host; it does not prove that a UF2 was built for the intended
board, that it was flashed, that USB CDC enumerated, or that an external bus is
electrically correct.

This guide turns the current PicoKit error and integration surfaces into a
repeatable diagnosis sequence. It is intentionally evidence-driven: each
stage has a command, an observable result, and a boundary beyond which that
result cannot prove anything.

## The evidence ladder

Use the first failing stage as the starting point:

| Stage | Strong evidence | What it proves | What it does not prove |
| --- | --- | --- | --- |
| Source/API | `swift build`, host validation | Swift declarations and host paths compile | Firmware target or wiring |
| Configuration | `swiftpico info`, generated `swiftpico.json` | Board, product, source, SDK, and output paths are resolved | Image contents or flash |
| Firmware build | non-empty `.elf` and `.uf2` | CMake and Embedded Swift produced the selected artifact | Board accepted the image |
| Flash | CLI reports the intended UF2 loaded | The image reached a selected BOOTSEL device | Application startup or USB CDC |
| USB CDC | expected bytes from `monitor` or a serial test | Firmware started and the USB path exchanged bytes | External UART/I2C/SPI wiring |
| Peripheral | identity response, captured waveform, or measured voltage | The selected device and physical path responded | Unrelated peripherals or future resets |

Do not promote a lower stage to a higher one. For example, a visible serial
device can be stale application firmware, and a successful SPI constructor
only proves that PicoKit accepted the pin roles.

## Start with the exact failure

### A typed API throws before flashing

The portable core reports these failures before the SDK bridge is called:

| Error | Meaning | First check |
| --- | --- | --- |
| `invalidPin` | GPIO is outside `0...29` | Convert the input to `PicoPin` and inspect the board schematic |
| `invalidPeripheralPin` | Pin is not valid for that UART, I2C, or SPI role | Compare the selected map with [board and pin planning](board-and-pin-planning.md) |
| `invalidFrequency` | Frequency is zero, overflows its unit conversion, or is unsupported | Use a non-zero `Frequency` and inspect `actualFrequency`/`actualBaudRate` |
| `invalidTimeout` | Timeout is zero or cannot fit the SDK microsecond value | Use a positive bounded `Duration` |
| `invalidAddress` | I2C address is outside `0x08...0x77` | Confirm the device's 7-bit address; do not pass an 8-bit read/write byte |
| `ownershipConflict` | A resource or DMA channel was already claimed | Find the first owner and release or share it explicitly |
| `unavailable` | Feature is absent from the current board or build | Check the compiled board, USB setting, and selected API path |

Preserve the error while diagnosing it. A useful throwing boundary keeps the
operation and value visible:

```swift
do {
    let i2c = try PicoI2C(
        .i2c0,
        frequency: .kilohertz(400),
        sda: .gpio4,
        scl: .gpio5
    )
    let bytes = try i2c.writeRead(
        address: 0x48,
        bytes: [0x00],
        count: 2,
        timeout: .milliseconds(100)
    )
    Serial.println("sensor bytes: \(bytes)")
} catch let error {
    Serial.println("I2C setup/transaction failed: \(error)")
}
```

`invalidPeripheralPin` is a software map failure. If construction succeeds
but no device responds, continue to power, ground, pull-up, chip-select, and
waveform checks; do not keep changing the pin table at random.

### A read times out or partially transfers

`timedOut(operation:)` means the operation reached its timeout boundary.
`partialTransfer(operation:transferred:expected:)` means the transfer returned
fewer elements than requested. These are different from a configuration
failure and should normally trigger a bounded retry or a visible degraded
state, not an infinite loop.

For every retry, record the operation, attempt number, timeout, and whether the
device was selected. A retry is useful only if the physical cause is transient
or the device protocol permits it. Repeating an I2C transaction against a
miswired bus does not repair the wiring.

For SPI, verify the following independently:

1. `select()` succeeded and chip select is low during the frame.
2. SCK, MOSI, and MISO are the intended pins and are distinct.
3. The mode, bit order, frame width, maximum clock, and inter-frame delay
   match the device datasheet.
4. `deselect()` runs after the frame, including the error path.

For I2C, verify pull-ups, common ground, voltage levels, address format, and
whether the device expects a repeated START. PicoKit validates the digital
transaction shape, not those electrical or protocol-specific requirements.

## If the firmware does not build

Run the host checks first:

```sh
swift build
swift run PicoKitHostTests
```

Then run the generated-project integration path from a PicoKit checkout:

```sh
sh Tests/integration/generated-project.sh
sh Tests/integration/generated-templates.sh
```

If `swift build` fails, fix the package or toolchain issue before inspecting
the board. If host validation passes but generated firmware fails, inspect the
first CMake or Embedded Swift compiler error and retain the complete command
line. The firmware boundary is selected by CMake; it is not exercised by a
normal host package build.

For a direct CMake investigation, preserve the same root and source values as
the generated project:

```sh
cmake -S Firmware -B Firmware/build -G Ninja \
  -DPICOKIT_ROOT="$PWD" \
  -DPICOKIT_PRODUCT=Diagnostic \
  -DPICOKIT_SOURCE="$PWD/Sources/Blink/main.swift" \
  -DPICO_BOARD=pico2
cmake --build Firmware/build --parallel
```

Use the generated project's resolved SDK and compiler settings when replacing
this placeholder command. Do not diagnose a flash issue from an old `.uf2`:
check the modification time and product path reported by `swiftpico info`.

## If flashing fails

Separate image selection from USB state:

```sh
swiftpico doctor
./swiftpico info
./swiftpico devices
./swiftpico flash
```

The `flash` command must identify the intended BOOTSEL volume and load the UF2
that the current build produced. If no BOOTSEL device is found, put only the
intended board into BOOTSEL mode and rerun `devices`; multiple candidates are
not a safe selection. A serial node by itself is evidence of an application
USB interface, not permission to flash that device.

After flashing, allow the board to reboot before interpreting serial output.
If the board remains in BOOTSEL mode, the flash can have succeeded while the
application and CDC checks remain unproven.

## If USB serial is silent

USB CDC has two separate questions: did firmware initialize the interface, and
did a host open it? `Serial.connected` is a snapshot, and it can change
immediately after it is read. A throwing `USBSerial` write reports a disconnected
host as `unavailable("USB serial host is not connected")`; the sketch facade
intentionally keeps the short nonthrowing path and ignores that status.

Use a bounded startup policy that matches the application:

```swift
let deadline = millis() + 5_000
while !Serial.connected && millis() < deadline {
    sleep(10)
}
Serial.println("diagnostic ready")
```

For a continuously running device, do not block forever waiting for a monitor:
continue the control loop and announce readiness when the connection appears.
For a one-shot diagnostic, an explicit wait can be appropriate, but document
the timeout and the host-side action required to open the port.

Check the complete path in this order:

1. Confirm the selected build has USB enabled and uses the expected board.
2. Flash the newly built UF2 and run `swiftpico devices` after reboot.
3. Open `swiftpico monitor --reconnect` before expecting startup-only output.
4. Emit a repeated heartbeat or exact byte sequence so a late monitor can
   distinguish silence from a one-time message that already passed.
5. If the device enumerates but writes fail, inspect DTR/connection settings
   and the configured USB wait/post-connect delays.

USB output is not proof of a UART, I2C, or SPI device. Use those buses' own
responses or an instrument next.

## If an external peripheral is silent

Reduce the application to one peripheral and one observable result. Keep USB
serial only as diagnostics and assign it different pins from the device under
test. Then verify:

| Check | Evidence |
| --- | --- |
| Board and chip | `PicoBoard`/CMake selection agrees with the firmware log |
| Pin map | Constructor succeeds and the wiring record matches the schematic |
| Electrical | Measured 3.3 V logic, common ground, pull-ups, and reset state |
| Selection | CS or device address is correct; inactive devices are idle |
| Waveform | Logic analyzer or scope shows the expected clock/data/START/STOP |
| Protocol | Known identity/register response matches the datasheet |

Start with the lowest-speed supported clock and the largest practical timeout
while proving the wiring. Once a known response is captured, raise one setting
at a time and record the resulting `actualFrequency`, `actualBaudRate`, or
transfer result.

## Keep a diagnosis record

For a failure that may recur, save a small record beside the application:

```text
board: pico2_w
chip: rp2350
commit: <firmware commit>
product: Diagnostic
uf2: Firmware/build/Diagnostic.uf2
flash target: <BOOTSEL identity or volume>
serial path: <device path>
expected: 9f 40 18
observed: <bytes or none>
pins: SPI0 SCK=18 MOSI=19 MISO=16 CS=17
clock: requested 8 MHz, actual <reported value>
power/ground: verified
waveform: <capture name or pending>
```

This makes the next change falsifiable. Change one layer at a time, retain
the failing output, and only claim a peripheral fix after its own response or
waveform is present.

## Related documents

- [Getting started](getting-started.md) — project creation and CLI workflow.
- [Application design](application-design.md) — failure policy and loop shape.
- [Board and pin planning](board-and-pin-planning.md) — validated pin maps.
- [Runtime and testing](runtime-and-testing.md) — host, integration, and
  hardware evidence boundaries.
- [Hardware guide](hardware-guide.md) — API contracts and deliberate limits.
