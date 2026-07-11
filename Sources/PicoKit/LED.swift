/// LED control utilities — Arduino-style LED blinking and patterns.

public enum LEDPattern: Sendable {
    /// Blink on/off at a fixed interval.
    case blink(periodMs: UInt32, dutyCycle: Double)
    /// Breathe: smooth fade in and out using PWM.
    case breathe(periodMs: UInt32)
    /// Chase: sequential LED animation (for multiple pins).
    case chase(pins: [Int], stepMs: UInt32)
}

public final class LEDController {
    private let gpio: PicoGPIO
    private let pin: Int
    private let pwmSlice: PicoPWM?

    /// Create an LED controller for a GPIO pin.
    /// If `pwmSlice` is provided, PWM-based brightness control is available.
    public init(gpio: PicoGPIO, pin: Int, pwmSlice: PicoPWM? = nil) {
        self.gpio = gpio
        self.pin = pin
        self.pwmSlice = pwmSlice
        gpio.pinMode(pin, .output)
    }

    /// Turn the LED on.
    public func on() {
        if let pwm = pwmSlice {
            pwm.analogWrite(UInt8(255))
        } else {
            gpio.digitalWrite(pin, .high)
        }
    }

    /// Turn the LED off.
    public func off() {
        if let pwm = pwmSlice {
            pwm.analogWrite(UInt8(0))
        } else {
            gpio.digitalWrite(pin, .low)
        }
    }

    /// Toggle the LED state.
    public func toggle() {
        if let pwm = pwmSlice {
            // Toggle between max and zero
            if gpio.digitalRead(pin) == .high {
                pwm.analogWrite(UInt8(0))
            } else {
                pwm.analogWrite(UInt8(255))
            }
        } else {
            gpio.toggle(pin)
        }
    }

    /// Set PWM brightness (0-255).
    public func setBrightness(_ value: UInt8) {
        guard let pwm = pwmSlice else {
            gpio.digitalWrite(pin, value > 127 ? .high : .low)
            return
        }
        pwm.analogWrite(value)
    }

    /// Blink the LED: on for `onMs` ms, off for `offMs` ms, repeated `count` times.
    @discardableResult
    public func blink(onMs: UInt32 = 500, offMs: UInt32 = 500, count: Int = 1) -> Bool {
        for _ in 0..<count {
            on()
            PicoTimer.delay(onMs)
            off()
            PicoTimer.delay(offMs)
        }
        return true
    }

    /// Run a breathing pattern for `durationMs` milliseconds.
    public func breathe(durationMs: UInt32 = 4000) {
        guard let pwm = pwmSlice else { return }
        let steps: UInt32 = 100
        let stepMs = durationMs / (steps * 2)

        // Fade in
        for step in 0..<steps {
            pwm.analogWrite(UInt8(step * 255 / steps))
            PicoTimer.delay(stepMs)
        }
        // Fade out
        for step in (0..<steps).reversed() {
            pwm.analogWrite(UInt8(step * 255 / steps))
            PicoTimer.delay(stepMs)
        }
    }
}

/// Convenience: create an LED for the onboard LED of a known board.
public func onboardLED(for board: PicoBoard, using gpio: PicoGPIO) -> LEDController? {
    guard let pin = board.onboardLED else { return nil }
    return LEDController(gpio: gpio, pin: pin)
}
