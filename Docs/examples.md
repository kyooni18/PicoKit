# Explained PicoKit examples

These examples are complete firmware entry points, not isolated API fragments.
Create a project with SwiftPico, replace `Sources/<App>/main.swift` with one
example, then build, flash, and monitor it:

```sh
swiftpico init --board pico2_w --name Example --template blink
cd Example
./swiftpico build
./swiftpico flash
./swiftpico monitor --reconnect
```

Change pin numbers to match your board and wiring. Pico GPIO uses 3.3 V logic;
do not connect a 5 V signal directly to a GPIO. Each example gives one
peripheral a single long-lived owner and keeps setup outside the main loop.

## 1. Blink with the sketch API

Use this first to confirm that the toolchain, firmware build, and selected GPIO
all work. Connect an LED in series with a suitable resistor between GPIO15 and
ground, or replace the GPIO calls with `BoardLED` as shown in the next example.

```swift
import PicoKit

@main
struct Blink {
    static func main() {
        pinMode(15, .output)

        while true {
            digitalWrite(15, .high)
            sleep(500)
            digitalWrite(15, .low)
            sleep(500)
        }
    }
}
```

`pinMode` configures GPIO15 once. The loop drives it high and low for 500 ms
each, producing a one-second cycle. `sleep` blocks the current core, which is
appropriate for a first blink but not for a loop that must service several
time-sensitive devices.

The sketch API intentionally fails fast if the pin or hardware operation is
invalid. Use the low-level version below when firmware should handle setup
errors itself.

## 2. Board LED with recoverable setup

`BoardLED()` follows the board selected by `PICO_BOARD`, so it works with
boards whose status LED is not a plain GPIO25. This example also shows the
standard low-level `do`/`catch` shape.

```swift
import PicoKit

@main
struct BoardBlink {
    static func main() {
        do {
            let led = try BoardLED()
            let interval = try Duration.milliseconds(250)

            while true {
                try led.toggle()
                try Clock.sleep(for: interval)
            }
        } catch {
            // With no working output device, stop in a known state.
            while true {}
        }
    }
}
```

Construction validates that PicoKit knows the compiled board. `Duration` is
created once rather than on every iteration. In production firmware, the catch
path can record a diagnostic through another channel or enter a defined safe
state; it should not repeatedly retry an invalid fixed configuration.

## 3. Pull-up button controlling the board LED

Wire a momentary button between GPIO15 and ground. The internal pull-up keeps
the input high while released, so a pressed button reads low.

```swift
import PicoKit

@main
struct ButtonLED {
    static func main() {
        do {
            let gpio = PicoGPIO.compiled
            let button = try PicoPin(15)
            let led = try BoardLED()

            try gpio.configure(button, mode: .input, pull: .up)

            while true {
                let pressed = try gpio.read(button) == .low
                try led.set(pressed ? .high : .low)
                try delay(5)
            }
        } catch {
            while true {}
        }
    }
}
```

The short delay reduces needless polling and provides basic debounce, but it is
not a robust button state machine. A real user interface should require a
stable level for a chosen interval before accepting a transition.

## 4. Exact USB serial byte echo

This example is useful for testing USB CDC in both directions. It echoes bytes,
not strings, so NUL and non-UTF-8 data are preserved.

```swift
import PicoKit

@main
struct SerialEcho {
    static func main() {
        var announced = false
        while true {
            if !Serial.connected {
                announced = false
                sleep(10)
            } else if !announced {
                Serial.println("serial-echo: ready")
                announced = true
            } else if let byte = Serial.read() {
                Serial.write(byte)
            } else {
                sleepMicroseconds(100)
            }
        }
    }
}
```

`Serial.read()` is nonblocking. The short idle sleep prevents a busy loop, and
resetting `announced` makes every new monitor session receive the readiness
line. Run `./swiftpico monitor --reconnect`, type into the terminal, and verify
that each byte returns.

Use `USBSerial.read(timeout:)` instead when lack of input by a deadline is a
meaningful error. A connected but idle host throws `PicoKitError.timedOut`,
while a disconnected host throws
`PicoKitError.unavailable("USB serial host is not connected")`:

```swift
let serial = try USBSerial()
let byte = try serial.read(timeout: .seconds(5))
try serial.write(byte)
```

## 5. PWM LED fade

Connect an LED and resistor to GPIO0. PWM changes average brightness without a
software-timed on/off loop.

```swift
import PicoKit

@main
struct Fade {
    static func main() {
        do {
            let pwm = try PicoPWM(pin: .gpio0, frequency: .kilohertz(1))
            var duty: UInt16 = 0
            var rising = true

            while true {
                try pwm.setDutyCycle(duty)
                try delay(10)

                if rising {
                    if duty >= 64_000 {
                        rising = false
                    } else {
                        duty += 1_000
                    }
                } else if duty <= 1_000 {
                    rising = true
                } else {
                    duty -= 1_000
                }
            }
        } catch {
            while true {}
        }
    }
}
```

The PWM object is constructed once; only its duty value changes. `UInt16`
spans the full duty range. The visible fade is not perceptually linear because
human brightness perception and LED output are nonlinear; an application can
apply a lookup table when that matters.

## 6. Stream ADC samples over USB

Connect a 0–3.3 V analog signal to GPIO26. Never exceed the ADC input range.

```swift
import PicoKit

@main
struct ADCLogger {
    static func main() {
        do {
            let adc = try PicoADC()
            while !Serial.connected { sleep(10) }
            Serial.println("sample,raw")
            var index: UInt32 = 0

            while true {
                let raw = try adc.read(.gpio26)
                Serial.println("\(index),\(raw)")
                index &+= 1
                try delay(100)
            }
        } catch {
            Serial.println("adc: failed")
            while true {}
        }
    }
}
```

PicoKit returns a raw sample because voltage conversion depends on the board's
reference and calibration. The 100 ms delay also keeps USB logging outside a
high-rate sampling path. For continuous capture, use a dedicated DMA/C design
instead of printing every sample.

## 7. Read an I2C device register

This example targets a device at address `0x3C`, using I2C0 on GPIO4/GPIO5.
Connect SDA and SCL with appropriate pull-up resistors if the module does not
already provide them. Replace the address and register with values from the
device datasheet.

```swift
import PicoKit

@main
struct I2CRegisterRead {
    static func main() {
        do {
            let i2c = try PicoI2C(
                .i2c0,
                frequency: .kilohertz(400),
                sda: .gpio4,
                scl: .gpio5
            )

            let bytes = try i2c.writeRead(
                address: 0x3C,
                bytes: [0x00],
                count: 1,
                timeout: .milliseconds(100)
            )

            Serial.println("register value: \(bytes[0])")
            while true { sleep(1_000) }
        } catch {
            Serial.println("i2c: transaction failed")
            while true {}
        }
    }
}
```

`writeRead` sends the register prefix without ending the transaction, issues a
repeated START, and reads the requested count. It validates the address and
reports a short positive transfer as `partialTransfer`. A real driver should
interpret the returned byte and decide whether a timeout is retryable.

## 8. Read an SPI JEDEC identifier

Many SPI flash devices answer command `0x9F` with a three-byte manufacturer and
device identifier. Check the target device datasheet before using this wiring:
SCK GPIO18, MOSI GPIO19, MISO GPIO16, and active-low CS GPIO17.

```swift
import PicoKit

@main
struct SPIIdentifier {
    static func main() {
        do {
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
            let response = try spi.transfer(
                [0x9F, 0x00, 0x00, 0x00],
                timeout: .milliseconds(100)
            )
            try spi.deselect()

            Serial.println("manufacturer: \(response[1])")
            Serial.println("device: \(response[2]), \(response[3])")
            while true { sleep(1_000) }
        } catch {
            Serial.println("spi: transaction failed")
            while true {}
        }
    }
}
```

SPI receives one byte while transmitting each byte, so `response[0]`
corresponds to the command phase and is discarded. Chip select must surround
the complete transaction. For production code, use a small helper that also
attempts to deselect if transfer throws, leaving the device in a known state.

## 9. GPIO interrupt event polling

Wire a button between GPIO15 and ground. The interrupt handler stays in C and
only records edge flags; foreground Swift consumes them and performs the work.

```swift
import PicoKit

@main
struct InterruptButton {
    static func main() {
        do {
            let gpio = PicoGPIO.compiled
            let pin = try PicoPin(15)
            let interrupts = PicoInterrupts()
            let led = try BoardLED()

            try gpio.configure(pin, mode: .input, pull: .up)
            try interrupts.enable(pin, edge: .falling)

            while true {
                if interrupts.takeEvents(for: pin) != 0 {
                    try led.toggle()
                }
                try delay(1)
            }
        } catch {
            while true {}
        }
    }
}
```

Identical edges can coalesce before `takeEvents` runs, so this design signals
that activity occurred; it is not an exact press counter. Debounce remains an
application policy. Never sleep, allocate, print, or call Swift from the IRQ
handler itself.

## 10. Watchdog-protected loop

Enable the watchdog after setup succeeds. Update it only after one complete,
healthy iteration so a stuck operation eventually resets the board.

```swift
import PicoKit

@main
struct WatchedLoop {
    static func main() {
        do {
            let watchdog = PicoWatchdog()
            let led = try BoardLED()
            try watchdog.enable(timeout: .seconds(2), pauseOnDebug: true)

            while true {
                try led.toggle()
                try delay(500)
                watchdog.update()
            }
        } catch {
            // Do not feed the watchdog after an unrecoverable failure.
            while true {}
        }
    }
}
```

The timeout must exceed the slowest healthy loop, including bounded bus waits.
RP2040 supports at most 8,388 ms and RP2350 16,777 ms. `pauseOnDebug` prevents
an ordinary debugger stop from looking like a firmware hang.

## 11. Test GPIO logic on the host

Application logic that depends only on `DigitalIO` can run without a board.
This example records the configured mode and state in a fake implementation:

```swift
import PicoKit

final class FakeGPIO: DigitalIO {
    var configuredPin: PicoPin?
    var output: PinState = .low

    func setMode(_ pin: PicoPin, mode: PinMode) throws {
        configuredPin = pin
    }

    func write(_ pin: PicoPin, state: PinState) throws {
        output = state
    }

    func read(_ pin: PicoPin) throws -> PinState {
        output
    }
}

let fake = FakeGPIO()
let app = Pico(gpio: fake)

app.pinMode(7, .output)
app.digitalWrite(7, .high)

assert(fake.configuredPin == .gpio7)
assert(fake.output == .high)
```

This verifies application decisions, not electrical behavior. Host builds do
not emulate the Pico SDK; direct peripheral calls correctly report
`PicoKitError.unavailable`. Use firmware builds and physical tests for pin mux,
timing, USB enumeration, voltage levels, and wiring.

## Where to go next

- Use [USB serial and UART](serial-and-uart.md) for connection settings, UART
  pin pairs, partial transfers, and DMA ownership.
- Use [PWM, ADC, I2C, and SPI](buses-and-analog.md) for bus semantics, frame
  widths, chip select, repeated START, and DMA.
- Use [Runtime and testing](runtime-and-testing.md) for concurrency boundaries,
  interrupts, hardware gates, and deliberate limits.
- Use the [API reference](api-reference.md) for every exact declaration.
