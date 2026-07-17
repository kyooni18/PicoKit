/// GPIO interrupt support for RP2040/RP2350.
///
/// Configures edge-triggered interrupts on any GPIO pin. The actual interrupt
/// handler must be registered at the ARM NVIC level; this module handles the
/// GPIO-level configuration.

public enum GPIOInterruptEdge: Sendable {
  case rising
  case falling
  case eitherEdge
}

/// GPIO interrupt configuration.
public struct GPIOInterruptConfig: Sendable {
  public var pin: Int
  public var edge: GPIOInterruptEdge
  public var enabled: Bool

  public init(pin: Int, edge: GPIOInterruptEdge, enabled: Bool = true) {
    self.pin = pin
    self.edge = edge
    self.enabled = enabled
  }
}

public final class PicoInterrupts: @unchecked Sendable {
  /// GPIO interrupt register base.
  private static let ioBank0Base = 0x4001_4000

  /// GPIO_INTE — interrupt enable
  private static let inteOffset = 0x24
  /// GPIO_INTF — interrupt status (raw)
  private static let intfOffset = 0x28
  /// GPIO_INTES — interrupt status set
  private static let intesOffset = 0x2C
  /// GPIO_INTC — interrupt status clear
  private static let intcOffset = 0x30

  /// GPIO event selection: 0=level, 1=edge, 2=either
  private static let eventSelBase = 0x4001_0000

  private var configs: [Int: GPIOInterruptConfig] = [:]

  public init() {}

  /// Attach an interrupt to a GPIO pin.
  ///
  /// - Parameters:
  ///   - pin: GPIO pin number (0-29)
  ///   - edge: trigger edge
  ///   - enabled: whether to enable immediately
  public func attach(_ pin: Int, edge: GPIOInterruptEdge, enabled: Bool = true) {
    precondition((0..<30).contains(pin), "pin must be 0-29")

    // Set event selection
    let eventReg = Self.eventSelBase + 0x04 + (pin * 4)
    let eventVal: UInt32 = {
      switch edge {
      case .rising: 1
      case .falling: 1
      case .eitherEdge: 2
      }
    }()
    write(eventReg, eventVal)

    // Select which event triggers the interrupt
    // GPIOx_EV: select event source for interrupt
    let evReg = Self.ioBank0Base + 0x04 + (pin * 8) + 4
    write(evReg, 1)  // select GPIO event

    configs[pin] = GPIOInterruptConfig(pin: pin, edge: edge, enabled: enabled)

    if enabled {
      enable(pin)
    }
  }

  /// Enable interrupt for a previously configured pin.
  public func enable(_ pin: Int) {
    write(Self.ioBank0Base + Self.inteOffset, UInt32(1 << pin))
    if var config = configs[pin] {
      config.enabled = true
      configs[pin] = config
    }
  }

  /// Disable interrupt for a pin.
  public func disable(_ pin: Int) {
    write(Self.ioBank0Base + Self.inteOffset + 4, UInt32(1 << pin))  // INTECLR
    if var config = configs[pin] {
      config.enabled = false
      configs[pin] = config
    }
  }

  /// Detach (disable and clear) interrupt for a pin.
  public func detach(_ pin: Int) {
    disable(pin)
    clear(pin)
    configs.removeValue(forKey: pin)
  }

  /// Check if a pin's interrupt has fired (without clearing).
  public func isPending(_ pin: Int) -> Bool {
    (read(Self.ioBank0Base + Self.intfOffset) & (1 << pin)) != 0
  }

  /// Clear interrupt status for a pin.
  public func clear(_ pin: Int) {
    write(Self.ioBank0Base + Self.intcOffset, UInt32(1 << pin))
  }

  /// Get all pending interrupt pins.
  public func pendingPins() -> [Int] {
    let status = read(Self.ioBank0Base + Self.intfOffset)
    var pins: [Int] = []
    for pin in 0..<30 {
      if (status & (1 << pin)) != 0 {
        pins.append(pin)
      }
    }
    return pins
  }

  /// Clear all pending interrupts.
  public func clearAll() {
    write(Self.ioBank0Base + Self.intcOffset, 0xFFFF_FFFF)
  }

  @inline(__always) private func read(_ address: Int) -> UInt32 {
    UnsafePointer<UInt32>(bitPattern: address)!.pointee
  }

  @inline(__always) private func write(_ address: Int, _ value: UInt32) {
    UnsafeMutablePointer<UInt32>(bitPattern: address)!.pointee = value
  }
}
