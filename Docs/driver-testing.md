# Testing PicoKit drivers

A driver should be testable without a board, Pico SDK, serial monitor, or
timing-sensitive fixture. Keep protocol decisions in ordinary Swift values,
inject the smallest PicoKit boundary that performs I/O, and reserve firmware
and hardware tests for the behavior a host cannot observe.

## Choose the boundary deliberately

Use the narrowest test seam that proves the claim:

| Code under test | Inject or observe | What the test proves |
| --- | --- | --- |
| Register decoding, checksums, framing | values and byte arrays | pure protocol behavior |
| GPIO driver sequencing | `DigitalIO` fake | pin modes, writes, reads, and ordering |
| A `Pico`-based sketch component | `Pico(gpio:serial:)` | facade calls reach the supplied dependencies |
| Host hardware fallback | public `PicoGPIO`/`PicoSerial` behavior | unavailable hardware is reported honestly |
| USB or bus electrical behavior | firmware plus device or analyzer | the SDK bridge and wiring work together |

Do not use a host green test as evidence that a sensor is connected. The host
implementation intentionally throws
`PicoKitError.unavailable("Pico SDK bridge")` for hardware operations. See
[hardware validation](hardware-validation.md)
for the evidence ladder and [typed API and errors](typed-api-and-errors.md) for
the error contract.

## Record GPIO intent with a fake

`DigitalIO` is a public protocol designed for alternative boards and test
doubles. A recording fake can model only the state needed by the driver:

```swift
final class RecordingGPIO: DigitalIO {
    enum Event: Equatable {
        case mode(PicoPin, PinMode)
        case write(PicoPin, PinState)
        case read(PicoPin)
    }

    var events: [Event] = []
    var inputState: PinState = .low

    func setMode(_ pin: PicoPin, mode: PinMode) throws(PicoKitError) {
        events.append(.mode(pin, mode))
    }

    func write(_ pin: PicoPin, state: PinState) throws(PicoKitError) {
        events.append(.write(pin, state))
    }

    func read(_ pin: PicoPin) throws(PicoKitError) -> PinState {
        events.append(.read(pin))
        return inputState
    }
}

let gpio = RecordingGPIO()
let pin = try PicoPin(3)
try gpio.setMode(pin, mode: .output)
try gpio.write(pin, state: .high)

precondition(gpio.events == [
    .mode(pin, .output),
    .write(pin, .high),
])
```

For a real driver, put the sequence in a method such as `configure()` or
`pulse()`, then assert the complete event list. This catches a mode/write
ordering regression and an accidental extra write without requiring a GPIO
fixture. Use `PicoPin` in the fake rather than storing only integers so invalid
pin construction remains part of the test.

## Test failures as part of the contract

A fake should be able to fail at the operation the driver must recover from:

```swift
final class FailingGPIO: DigitalIO {
    let failure: PicoKitError

    init(_ failure: PicoKitError) { self.failure = failure }

    func setMode(_ pin: PicoPin, mode: PinMode) throws(PicoKitError) {
        throw failure
    }

    func write(_ pin: PicoPin, state: PinState) throws(PicoKitError) {
        throw failure
    }

    func read(_ pin: PicoPin) throws(PicoKitError) -> PinState {
        throw failure
    }
}
```

Test the typed error at the driver boundary, not just that “some error” was
thrown. For example, a driver may turn `.timedOut` into a retry while allowing
`.ioFailure` to escape. Keep configuration failures such as `.invalidPin` and
`.invalidPeripheralPin` visible; silently replacing them with a default pin
makes wiring mistakes harder to diagnose.

## Test the `Pico` facade with injected GPIO

When application code intentionally uses the sketch-shaped facade, construct
an explicit runtime in the test:

```swift
let gpio = RecordingGPIO()
let runtime = Pico(gpio: gpio)

runtime.pinMode(3, .output)
runtime.digitalWrite(3, .high)

precondition(gpio.events.count == 2)
```

The facade is fail-fast: an injected dependency error becomes a trap through
the unchecked sketch helpers. Use the throwing `DigitalIO` helpers or the
low-level peripheral object when the test needs to assert recovery rather
than process termination.

## Serial buffering and host-only seams

`PicoSerial.available` performs a lookahead read and retains at most one byte
until `read()` consumes it. A serial test should therefore verify that calling
`available` does not discard a raw `0x00` or `0xFF`, and that the backend is not
read repeatedly while the lookahead byte is pending. Firmware applications use
the public `Serial`/`PicoSerial` API; raw bytes are not text and should remain
bytes through the driver.

The host test target has an internal `PicoSerialBackend` seam so the repository
can test buffering, connection state, and write forwarding without a USB
device. That protocol and its injected initializer are not public application
API. External drivers should test their own serial abstraction above
`PicoSerial`, then use firmware or USB echo tests for the physical path.

## Run the right tests

PicoKit's `PicoKitHostTests` is a Foundation-free executable, not XCTest. Run
it with the package build when testing core values, typed errors, fakes, and
serial buffering:

```sh
swift build
swift run PicoKitHostTests
sh Tests/docs-consistency.sh
```

Then widen the scope only for claims host tests cannot prove: use the firmware
integration scripts for SDK and bridge linkage, USB echo for CDC transfer, and
a connected peripheral or logic analyzer for bus timing and wiring. Record
which boundary passed in the test name or release note so a host-only result
cannot be mistaken for hardware validation.
