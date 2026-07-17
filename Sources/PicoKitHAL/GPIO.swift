#if !PICOKIT_PICO_SDK
  import PicoKitCore
#else
  import PicoKitSDKBridge
#endif

extension PicoChip {
  /// The chip selected by the firmware build. Host builds use RP2040 as
  /// their validation default.
  public static var compiled: Self {
    #if PICOKIT_PICO_SDK
      return picokit_compiled_chip() == 0 ? .rp2040 : .rp2350
    #else
      return .rp2040
    #endif
  }
}

/// SDK-backed hardware access. The implementation is compiled only by the
/// Pico firmware CMake target. Host tests can exercise validation via fakes.
public final class PicoGPIO: DigitalIO {
  public static var rp2040: PicoGPIO { PicoGPIO(chip: .rp2040) }
  public static var rp2350: PicoGPIO { PicoGPIO(chip: .rp2350) }

  /// Creates a GPIO controller for the chip selected by the firmware build.
  /// Host builds use RP2040 as their validation default.
  public static var compiled: PicoGPIO {
    PicoGPIO(chip: .compiled)
  }

  public let chip: PicoChip

  public init(chip: PicoChip = .compiled) {
    self.chip = chip
  }

  #if PICOKIT_PICO_SDK
    @inline(__always)
    private func validateCompiledChip() throws(PicoKitError) {
      let compiledChip = picokit_compiled_chip() == 0 ? PicoChip.rp2040 : .rp2350
      guard chip == compiledChip else {
        throw PicoKitError.unavailable("GPIO chip does not match compiled Pico chip")
      }
    }
  #endif

  public func setMode(_ pin: PicoPin, mode: PinMode) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      try validateCompiledChip()
      picokit_gpio_init(pin.rawValue)
      picokit_gpio_set_direction(pin.rawValue, mode == .output ? 1 : 0)
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  public func configure(
    _ pin: PicoPin,
    mode: PinMode,
    initialState: PinState = .low,
    pull: PinPull = .none,
    driveStrength: PinDriveStrength = .milliamps4,
    slewRate: PinSlewRate = .slow
  ) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      try validateCompiledChip()
      let status = picokit_gpio_configure(
        pin.rawValue,
        mode == .output ? 1 : 0,
        initialState == .high ? 1 : 0,
        pull.rawValue,
        driveStrength.rawValue,
        slewRate.rawValue
      )
      guard status == 0 else {
        throw PicoKitError.ioFailure(operation: "GPIO setup", status: status)
      }
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  public func resetPulse(
    _ pin: PicoPin,
    activeState: PinState = .low,
    duration: Duration
  ) throws(PicoKitError) {
    try configure(pin, mode: .output, initialState: activeState.toggled)
    try write(pin, state: activeState)
    #if PICOKIT_PICO_SDK
      picokit_sleep_us(duration.microseconds)
      try write(pin, state: activeState.toggled)
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  public func write(_ pin: PicoPin, state: PinState) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      try validateCompiledChip()
      picokit_gpio_write(pin.rawValue, state == .high ? 1 : 0)
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  public func read(_ pin: PicoPin) throws(PicoKitError) -> PinState {
    #if PICOKIT_PICO_SDK
      try validateCompiledChip()
      return picokit_gpio_read(pin.rawValue) == 0 ? .low : .high
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  public func toggle(_ pin: PicoPin) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      try validateCompiledChip()
      picokit_gpio_toggle(pin.rawValue)
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  /// Sets every GPIO selected by `mask` high in one hardware operation.
  /// Bits above GPIO29 are ignored.
  public func set(mask: UInt32) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      try validateCompiledChip()
      picokit_gpio_set_mask(mask)
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  /// Clears every GPIO selected by `mask` low in one hardware operation.
  /// Bits above GPIO29 are ignored.
  public func clear(mask: UInt32) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      try validateCompiledChip()
      picokit_gpio_clear_mask(mask)
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  /// Toggles every GPIO selected by `mask` in one hardware operation.
  /// Bits above GPIO29 are ignored.
  public func toggle(mask: UInt32) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      try validateCompiledChip()
      picokit_gpio_toggle_mask(mask)
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  public func pinMode(_ pin: Int, _ mode: PinMode) throws(PicoKitError) {
    try setMode(PicoPin(pin), mode: mode)
  }

  public func digitalWrite(_ pin: Int, _ state: PinState) throws(PicoKitError) {
    try write(PicoPin(pin), state: state)
  }

  public func digitalRead(_ pin: Int) throws(PicoKitError) -> PinState {
    try read(PicoPin(pin))
  }

  public func digitalToggle(_ pin: Int) throws(PicoKitError) {
    try toggle(PicoPin(pin))
  }
}

extension PicoBoard {
  fileprivate var picokitCompiledBoardCode: UInt32 {
    switch self {
    case .pico: 0
    case .picoW: 1
    case .pico2: 2
    case .pico2W: 3
    }
  }
}

extension PicoBoard {
  /// The exact board selected by the firmware build. Host builds use Pico as
  /// their validation default; custom firmware boards return `nil`.
  public static var compiled: Self? {
    #if PICOKIT_PICO_SDK
      switch picokit_compiled_board() {
      case 0: return .pico
      case 1: return .picoW
      case 2: return .pico2
      case 3: return .pico2W
      default: return nil
      }
    #else
      return .pico
    #endif
  }
}

public final class BoardLED {
  /// The board declaration supplied by the application. The concrete LED
  /// implementation still comes from the firmware target's `PICO_BOARD`.
  public let board: PicoBoard

  /// Creates a board LED using the exact board selected by the firmware
  /// build, without hardcoding a Pico board in the application source.
  public convenience init() throws(PicoKitError) {
    guard let board = PicoBoard.compiled else {
      throw PicoKitError.unavailable("unknown compiled Pico board")
    }
    try self.init(board: board)
  }

  public init(board: PicoBoard) throws(PicoKitError) {
    self.board = board
    #if PICOKIT_PICO_SDK
      let compiledChip = picokit_compiled_chip() == 0 ? PicoChip.rp2040 : .rp2350
      guard board.chip == compiledChip else {
        throw PicoKitError.unavailable("BoardLED board does not match compiled Pico chip")
      }
      guard picokit_compiled_board() == board.picokitCompiledBoardCode else {
        throw PicoKitError.unavailable("BoardLED board does not match compiled Pico board")
      }
      guard picokit_status_led_init() == 0 else {
        throw PicoKitError.unavailable("board status LED")
      }
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  public func set(_ state: PinState) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      picokit_status_led_write(state == .high ? 1 : 0)
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  public func toggle() throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      picokit_status_led_toggle()
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }
}
