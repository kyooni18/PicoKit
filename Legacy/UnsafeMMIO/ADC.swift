/// ADC driver for RP2040/RP2350.
///
/// The ADC block supports up to 5 channels:
///   - ADC0 → GPIO26
///   - ADC1 → GPIO27
///   - ADC2 → GPIO28
///   - ADC3 → GPIO29
///   - ADC4 → internal temperature sensor
///
/// Resolution is 12-bit (0…4095).

public enum ADCChannel: Int, CaseIterable, Sendable {
  case gpio26 = 0
  case gpio27 = 1
  case gpio28 = 2
  case gpio29 = 3
  case temperature = 4
}

public final class PicoADC: @unchecked Sendable {
  /// Base address of the ADC block.
  private static let base = 0x4004_0000

  /// Selects which GPIO function the ADC pins use (function 3).
  fileprivate static let adcFunction: UInt32 = 3

  /// Current sampling channel.
  public private(set) var channel: ADCChannel = .gpio26

  public init() {}

  /// Enable the ADC peripheral and select a channel.
  public func begin(channel: ADCChannel = .gpio26) {
    self.channel = channel
    // ADC_FCS: select channel, enable ADC
    write(Self.base + 0x00, (UInt32(channel.rawValue) << 8) | 2)
  }

  /// Configure GPIO pins for ADC input (function 3).
  public func configurePins(_ pins: [Int], using gpio: PicoGPIO) {
    for pin in pins {
      gpio.selectFunction(pin, Self.adcFunction)
    }
  }

  /// Trigger a conversion and return raw 12-bit value (0…4095).
  public func readRaw() -> UInt16 {
    // Select channel
    write(Self.base + 0x00, (UInt32(channel.rawValue) << 8) | 2)
    // Trigger conversion
    write(Self.base + 0x04, 1)  // ADC_CS: set ADC_START
    // Wait for conversion complete
    while (read(Self.base + 0x04) & (1 << 6)) == 0 {}  // ADC_READY
    // Read result
    return UInt16(read(Self.base + 0x08) & 0xFFF)
  }

  /// Read the input voltage in millivolts, assuming a 3.3 V reference.
  public func readMillivolts() -> Float {
    Float(readRaw()) * 3300.0 / 4095.0
  }

  /// Read the input voltage in millivolts.
  @available(*, deprecated, renamed: "readMillivolts()")
  public func readVoltage() -> Float {
    readMillivolts()
  }

  /// Read approximate temperature in degrees Celsius.
  /// Formula: temp ≈ 27 °C - (reading - 380) / 1.8
  public func readTemperature() -> Float {
    let saved = channel
    self.channel = .temperature
    let raw = readRaw()
    self.channel = saved
    return 27.0 - (Float(raw) - 380.0) / 1.8
  }

  /// Arduino-style: read analog value on a GPIO pin.
  public func analogRead(_ pin: Int) -> UInt16 {
    switch pin {
    case 26: channel = .gpio26
    case 27: channel = .gpio27
    case 28: channel = .gpio28
    case 29: channel = .gpio29
    default: preconditionFailure("ADC only supports GPIO 26-29")
    }
    return readRaw()
  }

  /// Set ADC clock divider for sampling rate control.
  /// adcClock = sysClock / (div + 1). Max adc clock is 45 MHz.
  public func setClockDivider(_ divider: UInt32) {
    write(Self.base + 0x0C, divider)  // ADC_DIV
  }

  @available(*, deprecated, renamed: "setClockDivider(_:)")
  public func setDivider(_ divider: UInt32) {
    setClockDivider(divider)
  }

  @inline(__always) private func read(_ address: Int) -> UInt32 {
    UnsafePointer<UInt32>(bitPattern: address)!.pointee
  }

  @inline(__always) private func write(_ address: Int, _ value: UInt32) {
    UnsafeMutablePointer<UInt32>(bitPattern: address)!.pointee = value
  }
}

@inlinable
public func analogRead(_ pin: Int, using adc: PicoADC) -> UInt16 {
  adc.analogRead(pin)
}
