# Runtime model and testing

PicoKit supports a small fail-fast sketch facade and explicit throwing
peripheral objects. The choice affects error handling, but both paths use the
same Pico SDK bridge on firmware builds.

## Sketch and low-level runtime

Global helpers use a default `pico` runtime:

```swift
pinMode(15, .output)
digitalWrite(15, .high)
Serial.println("ready")
sleep(500)
```

They validate inputs and call `preconditionFailure` if the corresponding
low-level operation fails. This is useful when all configuration is fixed in
source. Use `PicoGPIO`, `USBSerial`, `PicoUART`, `PicoI2C`, `PicoSPI`, and
other throwing types for external configuration, reusable drivers, timeout
recovery, or diagnostic error reporting.

An explicit `Pico` instance exposes the same sketch operations and accepts a
custom `DigitalIO` implementation:

```swift
final class FakeGPIO: DigitalIO {
    var states: [UInt32: PinState] = [:]

    func setMode(_ pin: PicoPin, mode: PinMode) throws {}
    func write(_ pin: PicoPin, state: PinState) throws {
        states[pin.rawValue] = state
    }
    func read(_ pin: PicoPin) throws -> PinState {
        states[pin.rawValue] ?? .low
    }
}

let runtime = Pico(gpio: FakeGPIO())
runtime.pinMode(3, .output)
runtime.digitalWrite(3, .high)
```

## Ownership and concurrency

Give each hardware resource one logical owner. Do not create competing active
instances for the same UART, I2C controller, SPI controller, PWM slice,
watchdog, DMA channel set, or shared USB stdio state.

Peripheral objects do not provide synchronization. `Pico` and `PicoSerial`
being `@unchecked Sendable` allows embedded compilation; it does not make the
hardware safe for concurrent access from tasks, cores, or interrupt handlers.

## Interrupt model

The C bridge records GPIO edge bits in atomic per-pin storage. Foreground Swift
retrieves and clears them:

```swift
let interrupts = PicoInterrupts()
let input = try PicoPin(15)
try interrupts.enable(input, edge: .either)

while true {
    let events = interrupts.takeEvents(for: input)
    if events != 0 {
        // Process outside IRQ context.
    }
}
```

Repeated identical edges can coalesce before polling, so this is notification,
not an exact edge counter. Disabling a pin clears pending state. The bridge
never calls Swift from the IRQ handler; do not allocate, sleep, log, or access
peripheral objects in interrupt context.

## Watchdog

Enable the watchdog once the main loop can prove it is healthy:

```swift
let watchdog = PicoWatchdog()
try watchdog.enable(timeout: .seconds(2), pauseOnDebug: true)

while true {
    performOneIteration()
    watchdog.update()
}
```

Maximum timeout is 8,388 ms on RP2040 and 16,777 ms on RP2350. Choose enough
headroom for the slowest healthy iteration, including bounded peripheral waits.

## Host behavior

A normal `swift build` compiles PicoKit without the Pico SDK. Value validation,
errors, protocols, fakes, and buffering can be tested, while hardware calls
throw `PicoKitError.unavailable("Pico SDK bridge")`. `Clock.now()` and IRQ
polling return zero, and watchdog update is a no-op. This behavior prevents host
tests from pretending physical I/O occurred.

## Validation commands

Use the smallest relevant gate first, then widen before publishing:

```sh
swift build
swift run PicoKitHostTests
sh Tests/api-reference.sh
sh Tests/docs-links.sh
sh Tests/docs-consistency.sh
sh Tests/integration/generated-project.sh
sh Tests/integration/generated-templates.sh
```

Other integration gates cover direct CMake discovery, USB-disabled builds,
compiler overrides, board aliases, and CMake option bounds. Set
`PICO_HARDWARE_TEST=1` only when the run is allowed to flash a detected board
and verify binary USB CDC echo. Select the family with `PICO_TEST_BOARD`.

## Deliberate limits

PicoKit does not provide an async scheduler, PIO API, wireless stack, USB
device classes beyond stdio, multicore coordination, runtime ownership
registry, line protocol, or asynchronous DMA API. Device-specific register
maps, transaction policy, calibration, framing, and conversion remain in
focused application drivers. Use PIO or focused C for cycle-exact waveforms,
continuous capture, or protocols that cannot tolerate foreground scheduling.
