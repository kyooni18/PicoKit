#if !PICOKIT_PICO_SDK
  import PicoKitCore
#else
  import PicoKitSDKBridge
#endif

public enum PWMChannel: Sendable { case a, b }

public final class PicoPWM {
  public let pin: PicoPin
  /// The counter's maximum representable level for this configured frequency.
  public let counterTop: UInt16
  /// The frequency actually produced after clock-divider and wrap quantization.
  public let actualFrequency: Frequency
  private let slice: UInt32
  private let channel: UInt32
  private let wrap: UInt32

  deinit {
    #if PICOKIT_PICO_SDK
      picokit_pwm_release(pin.rawValue)
    #endif
  }

  public init(pin: PicoPin, frequency: Frequency) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      var slice: UInt32 = 0
      var channel: UInt32 = 0
      var wrap: UInt32 = 0
      var actualFrequency: UInt32 = 0
      let status = picokit_pwm_init_with_actual_frequency(
        pin.rawValue, frequency.hertz, &slice, &channel, &wrap, &actualFrequency
      )
      if status == -2 {
        throw PicoKitError.ownershipConflict("PWM slice already has an incompatible or active channel owner")
      }
      guard status == 0 else {
        throw PicoKitError.ioFailure(operation: "PWM setup", status: status)
      }
      self.pin = pin
      self.slice = slice
      self.channel = channel
      self.wrap = wrap
      self.counterTop = UInt16(wrap)
      self.actualFrequency = try Frequency.hertz(actualFrequency)
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  public func setDutyCycle(_ fraction: UInt16) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      picokit_pwm_set_level(slice, channel, wrap, fraction)
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  /// Writes a value already scaled for this PWM counter. Values above
  /// `counterTop` saturate to full duty. Use this in a tight loop when the
  /// application can produce counter units directly and can skip the normal
  /// UInt16 duty-to-counter division.
  public func setCounterLevel(_ level: UInt16) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      picokit_pwm_set_counter_level(slice, channel, wrap, level)
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  public func analogWrite(_ duty: UInt8) throws(PicoKitError) {
    try setDutyCycle(UInt16(duty) * 257)
  }
  public func analogWrite(_ duty: UInt16) throws(PicoKitError) { try setDutyCycle(duty) }
}

/// PWM-backed display backlight with explicit active-high/active-low polarity.
public final class PicoBacklight {
  private let pwm: PicoPWM
  private let activeHigh: Bool

  public init(pin: PicoPin, frequency: Frequency = try! .kilohertz(20), activeHigh: Bool = true)
    throws(PicoKitError)
  {
    self.pwm = try PicoPWM(pin: pin, frequency: frequency)
    self.activeHigh = activeHigh
    try setBrightness(0 as UInt16)
  }

  public func setBrightness(_ value: UInt16) throws(PicoKitError) {
    try pwm.setDutyCycle(activeHigh ? value : UInt16.max - value)
  }

  public func setBrightness(_ value: UInt8) throws(PicoKitError) {
    try setBrightness(UInt16(value) * 257)
  }

  public func off() throws(PicoKitError) { try setBrightness(0 as UInt16) }
  public func fullOn() throws(PicoKitError) { try setBrightness(UInt16.max) }
}

@inlinable
public func analogWrite(_ pin: Int, _ duty: UInt8, using pwm: PicoPWM) throws(PicoKitError) {
  let validated = try PicoPin(pin)
  guard validated == pwm.pin else {
    throw PicoKitError.ownershipConflict("PWM is configured for \(pwm.pin), not \(validated)")
  }
  try pwm.analogWrite(duty)
}

@inlinable
public func analogWrite(_ pin: Int, _ duty: UInt16, using pwm: PicoPWM) throws(PicoKitError) {
  let validated = try PicoPin(pin)
  guard validated == pwm.pin else {
    throw PicoKitError.ownershipConflict("PWM is configured for \(pwm.pin), not \(validated)")
  }
  try pwm.analogWrite(duty)
}

public enum ADCChannel: UInt32, CaseIterable, Sendable {
  case gpio26, gpio27, gpio28, gpio29, temperature
}

public final class PicoADC {
  public init() throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      picokit_adc_init()
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  public func read(_ channel: ADCChannel) throws(PicoKitError) -> UInt16 {
    #if PICOKIT_PICO_SDK
      let value = picokit_adc_read(channel.rawValue)
      guard value >= 0 else {
        throw PicoKitError.ioFailure(operation: "ADC read", status: value)
      }
      return UInt16(value)
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }
}

@inlinable
public func analogRead(_ channel: ADCChannel, using adc: PicoADC) throws(PicoKitError) -> UInt16 {
  try adc.read(channel)
}

@inline(__always)
func picoKitADCChannel(for pin: Int) throws(PicoKitError) -> ADCChannel {
  let validated = try PicoPin(pin)
  switch validated.rawValue {
  case 26: return .gpio26
  case 27: return .gpio27
  case 28: return .gpio28
  case 29: return .gpio29
  default: throw PicoKitError.unavailable("ADC is only available on GPIO26...GPIO29")
  }
}

public func analogRead(_ pin: Int, using adc: PicoADC) throws(PicoKitError) -> UInt16 {
  try adc.read(picoKitADCChannel(for: pin))
}
