# PicoKit GPIO and reset sequencing

GPIO configuration is part of a board's electrical behavior, not just a type
conversion. Direction, initial latch state, pull resistor, drive strength, and
slew rate affect what an attached reset, chip-select, LED, button, or power
enable line sees during startup.

PicoKit keeps this surface explicit through `PicoGPIO.configure` and provides
`resetPulse` for the common active-level reset sequence. Both are synchronous
operations. Keep one logical owner for each pin and do not call them from an
interrupt handler or concurrently with a peripheral that uses the same pin.

## Configure an output without a startup glitch

`configure` validates the chip and GPIO, initializes the pin, writes the
requested output latch, applies pulls and electrical settings, and enables the
requested direction. For an output, the latch is written before output mode is
enabled. This ordering matters for active-low reset and chip-select lines:
the pin does not briefly become low merely because output mode was selected.

```swift
let gpio = PicoGPIO.compiled

try gpio.configure(
    .gpio17,
    mode: .output,
    initialState: .high,
    pull: .none,
    driveStrength: .milliamps4,
    slewRate: .slow
)
```

The configuration values describe SDK settings; they do not replace a board
schematic or an electrical calculation:

| Setting | Values | Use it to express |
| --- | --- | --- |
| `mode` | `.input`, `.output` | Whether the MCU drives the line |
| `initialState` | `.low`, `.high` | Output latch value before output enable |
| `pull` | `.none`, `.up`, `.down` | Internal bias for a floating input or idle line |
| `driveStrength` | 2, 4, 8, 12 mA | SDK output drive setting |
| `slewRate` | `.slow`, `.fast` | Output edge-rate setting |

Do not use a pull-up to compensate for a missing external pull-up on a bus
without checking the device's voltage, rise-time, and current requirements.
Likewise, a stronger drive setting does not make an over-voltage connection
safe. PicoKit does not measure voltage, current, edge shape, or contention.

For an input, `initialState` is still passed through the same configuration
boundary but the input direction means the external line determines the
observed state. A button with an active-low connection commonly uses:

```swift
let button = PicoPin.gpio15
try gpio.configure(button, mode: .input, pull: .up)

if try gpio.read(button) == .low {
    Serial.println("pressed")
}
```

Use `PicoInterrupts` only after the input's idle level and edge polarity are
known. A pull-up button normally reports a falling edge when pressed and a
rising edge when released; bounce can still coalesce or produce multiple
foreground observations.

## Active-low reset pulse

`resetPulse` takes the level that means “reset asserted,” not the inactive
level. It performs this sequence synchronously:

1. Reconfigures the pin as an output with the inactive level already in the
   latch.
2. Applies no pull, 4 mA drive, and slow slew.
3. Drives the active level.
4. Blocks for the requested duration.
5. Drives the inactive level and returns.

For an active-low device, the resulting waveform is high → low → high:

```swift
try gpio.resetPulse(
    .gpio20,
    activeState: .low,
    duration: .milliseconds(10)
)
```

For an active-high enable/reset input, the waveform is low → high → low:

```swift
try gpio.resetPulse(
    .gpio21,
    activeState: .high,
    duration: .milliseconds(2)
)
```

The call leaves the pin as an output at the inactive level. It does not restore
the pin's previous mode, pull, drive strength, or slew rate. If the line must
later be an input or use different electrical settings, configure it explicitly
after the pulse:

```swift
try gpio.resetPulse(.gpio20, activeState: .low, duration: .milliseconds(10))
try gpio.configure(.gpio20, mode: .input, pull: .up)
```

The pulse duration must be positive because `Duration` rejects zero. The call
blocks the calling core for the entire duration, so keep the pulse within the
device's reset specification and do not use it as a scheduler delay. If the
application must remain responsive during a longer power-settle interval,
drive the line explicitly and track the deadline in the foreground loop.

## Reset and chip-select ownership

Reset lines and chip-select lines often share the same electrical concerns but
have different transaction lifetimes. Reserve both in the application's pin
map:

```swift
let reset = PicoPin.gpio20
let chipSelect = PicoPin.gpio17
precondition(reset != chipSelect)

try gpio.configure(reset, mode: .output, initialState: .high)
let spi = try PicoSPI(
    .spi0,
    frequency: .megahertz(8),
    sck: .gpio18,
    mosi: .gpio19,
    miso: .gpio16,
    chipSelect: chipSelect,
    gpio: gpio
)

try gpio.resetPulse(reset, activeState: .low, duration: .milliseconds(10))
```

When `PicoSPI` receives both `chipSelect` and a `PicoGPIO`, it configures the
chip-select as an active-low output that is high while idle. Do not also drive
that chip-select through a second GPIO controller or helper. The SPI object
owns its selected chip-select behavior for the lifetime of the instance;
application code owns reset timing and device initialization.

## Mask operations and atomicity

Use masks when several already-configured output pins must change together:

```swift
let dataMask = (1 << 2) | (1 << 3) | (1 << 4)
try gpio.set(mask: dataMask)
try gpio.clear(mask: dataMask)
try gpio.toggle(mask: dataMask)
```

`set(mask:)`, `clear(mask:)`, and `toggle(mask:)` use the SDK's atomic register
paths rather than a read-modify-write sequence. Bits above GPIO29 are ignored
by the C facade, so keep the mask explicit and do not treat an ignored bit as
evidence that a physical pin exists. These operations change latch state for
the selected pins; they do not configure direction, pulls, drive, or slew.

Atomic register access prevents lost updates within the SDK operation, but it
does not establish ownership between two Swift callers. A mask update racing
with `configure`, `resetPulse`, or a peripheral mux change still produces an
application-level conflict. Keep the GPIO controller and its pin map on one
foreground owner.

## Verification sequence

Verify GPIO behavior from software intent to physical waveform:

1. Confirm the board and compiled chip before constructing `PicoGPIO`.
2. Record each pin's role, inactive level, pull, voltage, and external owner.
3. Configure the inactive output level before attaching a sensitive device or
   enabling its power rail.
4. Capture a reset pulse with a scope or logic analyzer and measure its actual
   active duration and idle level.
5. Read an input at idle and active levels before enabling an interrupt.
6. Confirm that the first peripheral transaction occurs only after reset has
   completed and the device's required settle time has elapsed.

A passing `swift build` or a successful `PicoGPIO.configure` call proves only
that the Swift and digital configuration path accepted the request. It cannot
prove that the external device saw the required voltage, pulse width, or edge
shape.

## Host testing

The `DigitalIO` protocol lets application logic test pin decisions without
pretending that host execution toggled a Pico register:

```swift
final class RecordingGPIO: DigitalIO {
    var writes: [(PicoPin, PinState)] = []

    func setMode(_ pin: PicoPin, mode: PinMode) throws {}
    func write(_ pin: PicoPin, state: PinState) throws {
        writes.append((pin, state))
    }
    func read(_ pin: PicoPin) throws -> PinState { .low }
}

let fake = RecordingGPIO()
let app = Pico(gpio: fake)
app.pinMode(15, .output)
app.digitalWrite(15, .high)
precondition(fake.writes.last?.1 == .high)
```

Host fakes can prove mode decisions, active levels, and application ownership.
They cannot prove `resetPulse` wall-clock timing, pull behavior, drive current,
slew rate, or contention. Keep those claims in the hardware verification
record.

## Related documents

- [Board and pin planning](board-and-pin-planning.md) — reserve GPIO roles and
  validate peripheral alternate-function maps.
- [PWM, ADC, I2C, and SPI](buses-and-analog.md) — bus chip-select and signal
  ownership.
- [Runtime and testing](runtime-and-testing.md) — single-owner and interrupt
  boundaries.
- [Explained examples](examples.md) — buttons, interrupts, and watchdog loops.
- [Hardware guide](hardware-guide.md) — complete API contract and board limits.
