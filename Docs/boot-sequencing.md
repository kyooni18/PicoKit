# PicoKit firmware boot sequencing

Startup is an electrical sequence as well as a Swift initialization sequence.
An external device can observe a pin before the application reaches its main
loop, and a monitor may connect after the first diagnostic write. Make each
startup phase explicit so reset, power, buses, USB, and watchdog policy do not
depend on incidental object construction order.

## A safe high-level order

Use this order as a baseline and adapt it to the device datasheets:

```text
firmware runtime and clocks
        │
        ▼
configure safety outputs at inactive levels
        │
        ▼
assert or release external reset/power enables
        │
        ▼
construct and validate peripheral owners
        │
        ▼
wait for required device settle time or bounded USB diagnostics
        │
        ▼
perform an explicit health/identity check
        │
        ▼
enable watchdog and enter the healthy foreground loop
```

PicoKit's CMake bridge and SDK perform runtime initialization before the Swift
application runs. Application code still owns external pin levels, reset
timing, peripheral construction, device identity, and the point at which the
watchdog begins measuring health.

## Establish safe electrical levels first

Configure outputs with their inactive level already in the latch:

```swift
let gpio = PicoGPIO.compiled
let reset = PicoPin.gpio6
let chipSelect = PicoPin.gpio17
let powerEnable = PicoPin.gpio20

try gpio.configure(reset, mode: .output, initialState: .high)
try gpio.configure(chipSelect, mode: .output, initialState: .high)
try gpio.configure(powerEnable, mode: .output, initialState: .low)
```

The exact inactive levels come from the schematic and device datasheet. An
active-low reset or chip select normally idles high; a power enable may idle
low. Do not attach a sensitive peripheral, enable its power rail, or switch a
shared bus until the required output states are established.

`PicoGPIO.configure` writes the output latch before enabling output mode. This
prevents a transition through the wrong level during setup, but it cannot
control external pull resistors or a device that powers up before the MCU.

## Release reset with a defined pulse

Use `resetPulse` when a device requires a synchronous active-level pulse:

```swift
try gpio.resetPulse(
    reset,
    activeState: .low,
    duration: .milliseconds(2)
)
```

The call leaves the pin as an output at the inactive level. It does not restore
the pin's previous mode, pull, drive strength, or slew rate. If the line is
later reused as an input or bus signal, configure it explicitly. A longer
power-settle interval belongs in the foreground schedule after the pulse; do
not use a reset pulse as an unbounded scheduler delay.

Keep reset, chip select, and power-control pins in one application ownership
ledger. A second GPIO owner can undo the safe level while the first driver is
still starting.

## Construct owners before enabling dependent work

Create validated peripherals once, outside the main loop:

```swift
let i2c = try PicoI2C(
    .i2c0,
    frequency: .kilohertz(400),
    sda: .gpio4,
    scl: .gpio5
)
let sensor = try SensorDriver(bus: i2c, reset: gpio, resetPin: reset)

try sensor.initialize()
```

Constructors validate pins, chip declarations, addresses, frequencies, and
resource combinations before entering their hardware path. Keep construction
failures in an initialization `do/catch` or an explicitly documented
fail-fast policy. Do not create a new bus object every loop iteration to retry
a device; recover through the existing owner and its protocol policy.

If a device needs a power enable before bus construction, perform the enable,
wait the specified settle interval, then construct or probe the bus. If it must
be held in reset while power rises, keep reset asserted until the rail is
stable, then use the specified pulse and delay.

## Treat USB diagnostics as optional by default

USB CDC is often unavailable during the first part of boot. Keep control
initialization independent of the monitor:

```swift
if Serial.connected {
    Serial.println("boot: peripherals configured")
}

if Serial.connected {
    Serial.println("boot: device ready")
}
```

For a product that genuinely requires a host handshake, use a bounded policy:

```swift
let deadline = millis() + 2_000
while !Serial.connected && millis() < deadline {
    sleep(10)
}
```

Avoid an indefinite wait in unattended firmware. `Serial.connected` is a
snapshot and a disconnect can race the next write. USB CMake options control
initialization wait, post-connect settling, DTR policy, and output timeout;
they do not turn diagnostics into a safety mechanism.

## Probe identity before normal operation

After reset and required settling, perform the smallest safe identity or
status transaction before enabling the full application workload:

```swift
do {
    let id = try sensor.readIdentity()
    guard id == sensor.expectedIdentity else {
        throw PicoKitError.ioFailure(operation: "sensor identity", status: -1)
    }
} catch {
    try? sensor.enterSafeState()
    if Serial.connected { Serial.println("boot: sensor failed") }
    enterLatchedFaultState()
}
```

The identity operation, expected bytes, timeout, and safe state are application
policy. A successful constructor proves typed configuration, not that a device
is powered, wired, awake, or responding to the intended protocol.

## Enable the watchdog after health exists

Do not enable or feed the watchdog before setup has a meaningful health check:

```swift
try sensor.initialize()
try verifyRequiredOutputs()

let watchdog = PicoWatchdog()
try watchdog.enable(timeout: .seconds(2), pauseOnDebug: true)

while true {
    let healthy = try performOneCompleteIteration()
    if healthy {
        watchdog.update()
    }
}
```

The watchdog should cover the slowest complete healthy iteration, including
bounded peripheral waits and deliberate sleeps. Updating it before health
checks can keep a failed application alive forever; never update it from an
interrupt handler as a substitute for foreground progress.

## Host and physical verification

Host builds can validate initialization policy with fakes and typed errors:

```sh
swift build
swift run PicoKitHostTests
sh Tests/gpio-facade-host.sh
sh Tests/bridge-validation.sh
```

They cannot prove startup voltage, reset pulse width, power-rail settling,
USB enumeration timing, device identity, or watchdog reset timing. For those
claims, capture the relevant GPIO/power waveform or run the physical board
matrix with the exact board, image, wiring, and toolchain recorded.

## Boot review checklist

Before calling a firmware boot path ready, verify:

1. every output has a documented safe/inactive level;
2. reset and power sequencing follows the external device requirements;
3. peripheral owners are constructed once and before dependent work;
4. USB diagnostics cannot block safety or control behavior unexpectedly;
5. identity/status checks have bounded timeouts and safe failure paths;
6. the watchdog starts only after a complete healthy iteration is defined;
7. host, firmware, and physical evidence are reported separately.

## Related documents

- [GPIO and reset sequencing](gpio-and-reset-sequencing.md) — latch order,
  electrical settings, and reset pulses.
- [USB serial and UART](serial-and-uart.md) — startup and monitor policy.
- [Interrupts and watchdog](interrupts-and-watchdog.md) — healthy-loop feed
  and reset limits.
- [Resource ownership](resource-ownership.md) — owner and handoff rules.
- [Peripheral recovery](peripheral-recovery.md) — boot probe failure policy.
