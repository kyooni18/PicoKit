# PicoKit resource ownership and lifetime

PicoKit exposes hardware objects, not a runtime ownership registry. The
application must decide which component owns each pin, controller, DMA channel,
interrupt event word, watchdog, and USB stdio path. `Sendable` on a facade or
value type does not make the underlying hardware safe for concurrent access.

## Keep one owner per resource

Use a resource ledger next to the application configuration:

| Resource | PicoKit owner | Important lifetime rule |
| --- | --- | --- |
| GPIO pin and electrical configuration | `PicoGPIO` or a driver using `DigitalIO` | do not reconfigure or write from a competing driver, task, core, or IRQ |
| PWM pin/slice/channel | `PicoPWM` or `PicoBacklight` | construct once and reuse; the bridge rejects duplicate channels and incompatible shared-slice frequencies |
| ADC selector and channels | `PicoADC` | share one application owner for sampling policy and calibration |
| I2C controller | `PicoI2C` | serialize transactions and keep SDA/SCL wiring with the bus owner |
| SPI controller and chip select | `PicoSPI` plus its optional GPIO | keep select/deselect and the complete frame in one owner |
| UART controller | `PicoUART` | one owner for framing, reads, writes, and DMA |
| DMA channel(s) | UART/SPI DMA operation | a bridge claim token rejects competing peripheral objects; release explicitly when the owner is done |
| GPIO interrupt event word | `PicoInterrupts` | one foreground consumer; disabling clears pending events |
| watchdog | `PicoWatchdog` | enable and update from the one healthy foreground loop |
| USB stdio | `Serial`, `PicoSerial`, or `USBSerial` | treat connection state as shared external state and serialize writes |

The table is an application rule, not a claim that PicoKit can detect every
conflict. Constructors catch conflicts inside one peripheral, but two separate
objects can still be given the same pin or controller. Track cross-object
ownership explicitly.

## `Sendable` is not a lock

`PicoPin`, `Duration`, `Frequency`, and enum values are immutable value types
and are safe to copy. `PicoGPIO` and `PicoSerial` deliberately have no
`Sendable` conformance. `Pico` uses `@unchecked Sendable` for global firmware
storage; that permits compilation but does not add synchronization.

Keep hardware calls in one foreground owner:

```swift
final class SensorController {
    private let bus: PicoI2C
    private let led: PicoGPIO

    init(bus: PicoI2C, led: PicoGPIO) {
        self.bus = bus
        self.led = led
    }

    func poll() throws(PicoKitError) {
        let bytes = try bus.writeRead(
            address: 0x48,
            bytes: [0x00],
            count: 2,
            timeout: .milliseconds(20)
        )
        try led.write(.gpio25, state: bytes[0] == 0 ? .low : .high)
    }
}
```

If multiple execution contexts need the result, send values or events between
them after the owner completes the hardware operation. Do not pass the same
peripheral object to an interrupt handler or use a detached task as an
implicit lock.

## DMA ownership has two lifetimes

DMA has both an object lifetime and a channel lifetime. `PicoUART` and
`PicoSPI` receive a bridge claim token and retain channels after DMA operations
so they can reuse them. A second object for the same controller receives a
typed ownership conflict instead of reconfiguring or releasing the first
object's channels. Release them explicitly at a known handoff point:

```swift
let uart = try PicoUART(
    .uart0,
    baudRate: .hertz(115_200),
    tx: .gpio0,
    rx: .gpio1,
    chip: .compiled
)

try uart.writeDMA(payload, timeout: .milliseconds(250))
uart.releaseDMAChannel()
```

For SPI, use `releaseDMAChannels()`. The object also releases retained DMA
channels during deinitialization, but deterministic release is clearer when a
subsystem is being replaced or another owner must claim the channel. A timed
DMA operation aborts and cleans up the active channel before returning; the
protocol driver still owns any chip-select or peer resynchronization policy.

Never mutate or reuse a prepared buffer until the DMA call has returned. A
timeout overload is the bounded handoff point; an unbounded DMA call can keep
the caller waiting indefinitely.

## Chip select, reset, and interrupt ownership

When `PicoSPI` is given `chipSelect`, it configures that pin high while idle
and owns the select/deselect writes. Do not also drive the same pin through a
second `PicoGPIO` owner. Keep cleanup on throwing paths:

```swift
try spi.select()
defer { try? spi.deselect() }
let response = try spi.transfer(frame, timeout: .milliseconds(100))
```

The owner of a reset line must also own its electrical configuration. A
`resetPulse` leaves the pin as an output at the inactive level and does not
restore its previous mode or pull settings; a later owner must configure those
explicitly.

`PicoInterrupts` records edge bits for foreground consumption. It is not an
event queue or a second owner for the input pin. The input's GPIO configuration,
interrupt enable/disable lifecycle, and event handling should be coordinated by
one driver. `disable` clears pending state, so use it as an intentional
ownership/lifecycle boundary.

## Shared global state needs policy

USB stdio and the watchdog are naturally global hardware state. Multiple
`PicoSerial` values do not create independent USB connections, and multiple
watchdog values do not create independent watchdogs. Choose one diagnostic
writer and one healthy-loop watchdog owner. A monitor disconnect can race a
connection check, so safety behavior cannot depend on a successful diagnostic
write.

For ADC, PWM, bus, and GPIO objects, prefer explicit injection into a driver so
the owner is visible in its initializer. Avoid hidden global peripheral values
except for small fixed sketches where the ownership is obvious from the whole
program.

## Handoff and shutdown sequence

When replacing a subsystem or entering a fault state, use a deliberate order:

1. stop new application work for the resource;
2. finish or abort the bounded transaction;
3. restore chip select, reset, power-control, and safety outputs;
4. disable interrupt delivery and consume or discard pending state by policy;
5. release retained DMA channels;
6. destroy or transfer the owner object;
7. construct the replacement only after the ledger says the resource is free.

Do not rely on ARC timing as a protocol handshake. Destruction can release DMA,
but it does not notify an external device, undo a bus transaction, or prove a
pin has reached a safe voltage.

## Test ownership without hardware

Host tests can assert the application ownership policy with `DigitalIO` fakes
and recording protocol boundaries:

- a second driver is rejected before it emits a GPIO event;
- SPI chip select returns high when a transfer throws;
- a DMA handoff calls the matching release method;
- interrupt disable clears the driver's pending-event policy;
- a USB diagnostic failure does not skip the safe-state action;
- invalid pin, instance, and mode configuration produces no hardware event.

Use [driver testing](driver-testing.md) for fakes and
[peripheral recovery](peripheral-recovery.md) for retry and safe-state policy.
Host ownership tests prove control flow; firmware and physical tests are still
needed for channel arbitration, voltage, timing, and external-device behavior.

## Related documents

- [Runtime and testing](runtime-and-testing.md) — concurrency and host limits.
- [DMA and buffer lifecycle](dma-and-buffer-lifecycle.md) — buffer and channel
  lifetime details.
- [GPIO and reset sequencing](gpio-and-reset-sequencing.md) — electrical
  ownership and cleanup.
- [I2C and SPI transactions](i2c-and-spi-transactions.md) — bus framing and
  chip-select boundaries.
- [Interrupts and watchdog](interrupts-and-watchdog.md) — event and watchdog
  lifecycle.
