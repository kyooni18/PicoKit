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

/// Converts the fixed C facade status ABI into PicoKit's typed Swift errors.
/// Kept independent of hardware access so host validation covers every mapping.
@inline(__always)
func picoKitGPIOError(status: Int32, operation: String) -> PicoKitError? {
  #if PICOKIT_PICO_SDK
    let chipMismatch = PICOKIT_GPIO_STATUS_CHIP_MISMATCH
  #else
    // Must remain synchronized with PicoKitSDKBridge.h. The bridge validation
    // gate checks the imported firmware constant and this host-test fallback.
    let chipMismatch: Int32 = -2
  #endif
  if status == chipMismatch {
    return PicoKitError.unavailable("GPIO chip does not match compiled Pico chip")
  }
  if status != 0 { return PicoKitError.ioFailure(operation: operation, status: status) }
  return nil
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
    private var facadeChip: UInt32 { chip == .rp2040 ? 0 : 1 }

    @inline(__always)
    private func check(_ status: Int32, operation: String) throws(PicoKitError) {
      if let error = picoKitGPIOError(status: status, operation: operation) { throw error }
    }
  #endif

  public func setMode(_ pin: PicoPin, mode: PinMode) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      try check(
        picokit_gpio_set_mode(facadeChip, pin.rawValue, mode == .output ? 1 : 0),
        operation: "GPIO mode"
      )
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
      let status = picokit_gpio_configure(
        facadeChip, pin.rawValue,
        mode == .output ? 1 : 0,
        initialState == .high ? 1 : 0,
        pull.rawValue,
        driveStrength.rawValue,
        slewRate.rawValue
      )
      try check(status, operation: "GPIO setup")
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  public func resetPulse(
    _ pin: PicoPin,
    activeState: PinState = .low,
    duration: Duration
  ) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      try check(
        picokit_gpio_reset_pulse(
          facadeChip, pin.rawValue, activeState == .high ? 1 : 0, duration.microseconds
        ),
        operation: "GPIO reset pulse"
      )
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  public func write(_ pin: PicoPin, state: PinState) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      try check(
        picokit_gpio_write(facadeChip, pin.rawValue, state == .high ? 1 : 0),
        operation: "GPIO write"
      )
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  public func read(_ pin: PicoPin) throws(PicoKitError) -> PinState {
    #if PICOKIT_PICO_SDK
      var value: UInt32 = 0
      try check(picokit_gpio_read(facadeChip, pin.rawValue, &value), operation: "GPIO read")
      return value == 0 ? .low : .high
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  public func toggle(_ pin: PicoPin) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      try check(picokit_gpio_toggle(facadeChip, pin.rawValue), operation: "GPIO toggle")
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  /// Sets every GPIO selected by `mask` high in one hardware operation.
  /// Bits above GPIO29 are ignored.
  public func set(mask: UInt32) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      try check(picokit_gpio_set_mask(facadeChip, mask), operation: "GPIO set mask")
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  /// Clears every GPIO selected by `mask` low in one hardware operation.
  /// Bits above GPIO29 are ignored.
  public func clear(mask: UInt32) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      try check(picokit_gpio_clear_mask(facadeChip, mask), operation: "GPIO clear mask")
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  /// Toggles every GPIO selected by `mask` in one hardware operation.
  /// Bits above GPIO29 are ignored.
  public func toggle(mask: UInt32) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      try check(picokit_gpio_toggle_mask(facadeChip, mask), operation: "GPIO toggle mask")
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
