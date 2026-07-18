# PicoKit application design guide

This guide is for the step after the first blink: a firmware program that has
more than one peripheral, produces useful diagnostics, and must remain
understandable when a board or external device is disconnected.

PicoKit gives an application two deliberate styles:

- the sketch facade (`Serial`, `pinMode`, `digitalWrite`, `sleep`) is short and
  fail-fast;
- the typed objects (`BoardLED`, `PicoGPIO`, `PicoADC`, `PicoI2C`, `PicoSPI`,
  `PicoUART`, and `USBSerial`) validate configuration and throw
  `PicoKitError`.

Use the facade for fixed, tiny bring-up programs. Use typed objects when the
application needs a timeout, a retry, a diagnostic message, a fake in a host
test, or a clear owner for a hardware resource. It is normal to use both: the
application can use `Serial` for diagnostics while keeping its device driver
on a throwing bus object.

## The application loop

A robust PicoKit application can be described as five phases:

```text
boot
  │ configure validated resources
  ▼
announce
  │ wait for USB only when diagnostics require it
  ▼
sample ── failure ──► record/retry/fail according to policy
  │
  ▼
actuate
  │
  └──────────────► sleep for a bounded interval and repeat
```

The loop is foreground code. PicoKit has no async scheduler, and interrupt
handlers only record GPIO edge bits for later polling. Keep every peripheral
instance owned by one loop or one explicitly coordinated execution context.

## A complete application

This program is a useful architecture baseline for a Pico or Pico 2. It uses
the board-aware LED, reads ADC GPIO26, announces USB readiness, and keeps a
disconnected USB host from blocking the control loop.

```swift
import PicoKit

@main
struct SensorIndicator {
    static func main() {
        let led = try! BoardLED()
        let adc = try! PicoADC()
        var announced = false

        while true {
            if Serial.connected {
                if !announced {
                    Serial.println("sensor indicator ready")
                    announced = true
                }

                let raw = try! adc.read(.gpio26)
                Serial.println("ADC26: \(raw)")
            } else {
                announced = false
            }

            try! led.toggle()
            sleep(500)
        }
    }
}
```

Create and run it with the normal host workflow:

```sh
swiftpico init --board pico --name SensorIndicator --template blink
cd SensorIndicator
# Replace Sources/SensorIndicator/main.swift with the program above.
swiftpico build
swiftpico flash
swiftpico monitor --reconnect
```

This example proves only that the application boots, the board LED path is
valid, ADC setup and reads link, and USB CDC can print. It does not prove that
an external analog source is safe or meaningful; GPIO26 still needs the wiring,
voltage range, and sampling interpretation specified by the application.

## Decide the failure policy

Do not choose `try!`, `try?`, or `do/catch` by habit. Choose it per operation:

| Operation | Common policy | Reason |
| --- | --- | --- |
| Fixed board LED setup | `try!` during bring-up, then fail-fast if impossible | no useful work exists without it |
| USB diagnostic write | sketch `Serial` or ignored best effort | a missing host should not stop control |
| Sensor read | `do/catch` with a retry or fault counter | peripherals can disconnect or time out |
| Safety output | explicit error handling and safe state | continuing blindly can be unsafe |
| Configuration from a user or manifest | throwing constructor | invalid pins/frequency/address should be reported |

For a recoverable driver, keep the error at the boundary where a policy can be
chosen:

```swift
func readSensor(_ i2c: PicoI2C) -> [UInt8]? {
    do {
        return try i2c.read(
            address: 0x48,
            count: 2,
            timeout: .milliseconds(20)
        )
    } catch {
        Serial.println("sensor read failed: \(error)")
        return nil
    }
}
```

The address and transaction in this snippet are illustrative. Replace them
with the device's datasheet-defined protocol before wiring hardware.

## Keep setup out of the loop

Construct and configure a peripheral once, then reuse it:

```swift
let spi = try PicoSPI(
    .spi0,
    frequency: .megahertz(40),
    sck: .gpio18,
    mosi: .gpio19,
    miso: .gpio16,
    mode: .mode0,
    chipSelect: .gpio17
)

while true {
    try spi.select()
    try spi.write([0x9F])
    let response = try spi.read(count: 3, repeatedByte: 0)
    try spi.deselect()
    _ = response
    sleep(100)
}
```

`PicoSPI` validates the selected mux, rejects shared signal pins, initializes
chip select high, and reports the actual quantized frequency. The application
still owns the transaction protocol: it must decide when to select, what bytes
to send, how to decode the response, and what to do after an error. Use a
`defer`-style cleanup pattern in a larger driver so chip select returns high
when a throwing operation exits early.

For I2C, use `writeRead` for a register prefix followed by a repeated START:

```swift
let i2c = try PicoI2C(
    .i2c0,
    frequency: .kilohertz(400),
    sda: .gpio4,
    scl: .gpio5
)
let value = try i2c.writeRead(
    address: 0x50,
    bytes: [0x00],
    count: 2,
    timeout: .milliseconds(20)
)
```

The address, register, count, and timeout must come from the peripheral
protocol. `writeRead` validates the complete operation before issuing its write
portion, so a negative count cannot cause a partial side effect.

## Board portability

The four supported boards map to two chip families:

| Board | Chip | LED behavior |
| --- | --- | --- |
| `.pico` | RP2040 | GPIO25 |
| `.picoW` | RP2040 | SDK wireless status LED |
| `.pico2` | RP2350 | GPIO25 |
| `.pico2W` | RP2350 | SDK wireless status LED |

Prefer `BoardLED()` when the application means “the board's onboard LED.” It
follows the compiled board. Use an explicit `BoardLED(board:)` only when the
application is intentionally checking or controlling a particular board
configuration; a mismatched chip declaration is rejected.

For peripheral pin maps, do not assume RP2040 and RP2350 have identical valid
alternate-function positions. Construct the typed peripheral and let its
validation report `invalidPeripheralPin` before the SDK is touched. Keep the
selected board in project configuration, not as a second hard-coded board
constant in application logic.

## Interrupts without hidden concurrency

PicoKit does not call Swift from a GPIO IRQ handler. It records edge flags in
the C bridge, and foreground code consumes them:

```swift
let input = try PicoPin(17)
let interrupts = PicoInterrupts()
try interrupts.enable(input, edge: .falling)

while true {
    if interrupts.takeEvents(for: input) != 0 {
        Serial.println("button event")
    }
    sleepMicroseconds(100)
}
```

Repeated edges can coalesce before polling, so this is an event notification,
not an exact edge counter. Do not allocate, sleep, log, or touch a peripheral
from interrupt context. If the application needs every edge, design an
application-specific capture path instead of treating `takeEvents` as a queue.

## Watchdog placement

Update the watchdog after the work that proves the loop is healthy:

```swift
let watchdog = PicoWatchdog()
try watchdog.enable(timeout: .seconds(5))

while true {
    let healthy = performRequiredWork()
    if healthy {
        watchdog.update()
    }
}
```

Do not call `update()` unconditionally before the health checks; that turns a
stuck subsystem into a loop that never expires. The maximum timeout is board
specific, and the application must leave headroom for its slowest valid
iteration.

## Testing the design

Use increasing levels of evidence:

1. `swift build` checks Foundation-free values, protocols, fakes, and error
   mapping without claiming hardware I/O.
2. `swift run PicoKitHostTests` exercises the package's host validation.
3. `sh Tests/integration/generated-templates.sh` checks generated source
   against the Embedded Swift PicoKit module.
4. `sh Tests/integration/generated-project.sh` checks a generated firmware
   project and the flash boundary.
5. A physical board run proves USB boot, pin mux, electrical behavior, and
   external protocol only for the selected board and wiring.

For host tests, replace `DigitalIO` with a fake and assert state transitions:

```swift
final class FakeGPIO: DigitalIO {
    var state: PinState = .low

    func setMode(_ pin: PicoPin, mode: PinMode) throws {}
    func write(_ pin: PicoPin, state: PinState) throws { self.state = state }
    func read(_ pin: PicoPin) throws -> PinState { state }
}
```

This proves application decisions without pretending that a GPIO voltage was
measured. Keep those claims separate in test output and release notes.

## Where to continue

- [Getting started](getting-started.md) for installation and the first UF2.
- [Explained examples](examples.md) for complete peripheral programs.
- [Runtime and testing](runtime-and-testing.md) for host limits and ownership.
- [API reference](api-reference.md) for every public declaration.
- [Hardware guide](hardware-guide.md) for wiring and board-level cautions.
