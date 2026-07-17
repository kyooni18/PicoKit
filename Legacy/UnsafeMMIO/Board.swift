/// The microcontroller family used by a Pico board.
public enum PicoChip: String, CaseIterable, Sendable {
  case rp2040
  case rp2350
}

/// Supported Raspberry Pi Pico boards.
public enum PicoBoard: String, CaseIterable, Sendable {
  case pico
  case picoW = "pico-w"
  case pico2
  case pico2W = "pico2_w"

  public var chip: PicoChip {
    switch self {
    case .pico, .picoW: .rp2040
    case .pico2, .pico2W: .rp2350
    }
  }

  /// The onboard LED GPIO for boards where it is directly wired.
  /// Pico W/Pico 2 W LEDs are controlled by their wireless chip instead.
  public var onboardLED: Int? {
    switch self {
    case .pico, .pico2: 25
    case .picoW, .pico2W: nil
    }
  }
}
