/// LED control utilities — Arduino-style LED blinking and brightness.

public final class LEDController: @unchecked Sendable {
  private let gpio: PicoGPIO
  private let pin: Int
  private let pwmSlice: PicoPWM?
  private var state: PinState = .low

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
    state = .high
    if let pwm = pwmSlice {
      pwm.analogWrite(UInt8(255))
    } else {
      gpio.digitalWrite(pin, .high)
    }
  }

  /// Turn the LED off.
  public func off() {
    state = .low
    if let pwm = pwmSlice {
      pwm.analogWrite(UInt8(0))
    } else {
      gpio.digitalWrite(pin, .low)
    }
  }

  /// Toggle the LED state.
  public func toggle() {
    state = state.toggled
    if let pwm = pwmSlice {
      pwm.analogWrite(state == .high ? UInt8(255) : UInt8(0))
    } else {
      gpio.toggle(pin)
    }
  }

  /// Set PWM brightness (0-255).
  public func setBrightness(_ value: UInt8) {
    guard let pwm = pwmSlice else {
      state = value > 127 ? .high : .low
      gpio.digitalWrite(pin, state)
      return
    }
    state = value == 0 ? .low : .high
    pwm.analogWrite(value)
  }

  /// The last state requested through this controller.
  public var isOn: Bool { state.isHigh }

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
