/// Portable PicoKit foundation. It is safe to use in host tests and does not
/// access registers or import the Pico SDK.
public enum PicoChip: String, CaseIterable, Sendable {
    case rp2040
    case rp2350
}

public enum PicoBoard: String, CaseIterable, Sendable {
    case pico
    case picoW = "pico_w"
    case pico2
    case pico2W = "pico2_w"

    public var chip: PicoChip { self == .pico || self == .picoW ? .rp2040 : .rp2350 }
    public var cmakeName: String { rawValue }
    public var onboardLEDPin: PicoPin? { self == .pico || self == .pico2 ? try? PicoPin(25) : nil }
    /// Compatibility value for code that stores a board LED as an integer.
    public var onboardLED: Int? { onboardLEDPin.map { Int($0.rawValue) } }

    /// Accept historical spellings only while decoding configuration.
    public init?(configurationName: String) {
        switch configurationName.lowercased() {
        case "pico": self = .pico
        case "pico_w", "pico-w": self = .picoW
        case "pico2": self = .pico2
        case "pico2_w", "pico2-w": self = .pico2W
        default: return nil
        }
    }
}

public enum PicoKitError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidPin(Int)
    case invalidFrequency(UInt32)
    case invalidTimeout(UInt64)
    case invalidAddress(UInt8)
    case invalidPeripheralPin(peripheral: String, pin: PicoPin)
    case unavailable(String)
    case timedOut(operation: String)
    case partialTransfer(operation: String, transferred: Int, expected: Int)
    case ioFailure(operation: String, status: Int32)
    case ownershipConflict(String)

    public var description: String {
        switch self {
        case .invalidPin(let pin): "GPIO pin \(pin) is outside 0...29"
        case .invalidFrequency(let hertz): "frequency \(hertz) Hz is zero, overflows, or is unsupported"
        case .invalidTimeout(let microseconds): "timeout \(microseconds) us is zero, overflows, or is unsupported"
        case .invalidAddress(let address): "I2C address 0x\(String(address, radix: 16)) is outside 0x08...0x77"
        case .invalidPeripheralPin(let peripheral, let pin): "\(pin) cannot be used as \(peripheral)"
        case .unavailable(let feature): "\(feature) is unavailable for this board or build"
        case .timedOut(let operation): "\(operation) timed out"
        case .partialTransfer(let operation, let transferred, let expected):
            "\(operation) transferred \(transferred) of \(expected) elements"
        case .ioFailure(let operation, let status): "\(operation) failed with SDK status \(status)"
        case .ownershipConflict(let reason): reason
        }
    }
}

public struct PicoPin: RawRepresentable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: UInt32
    public init(_ value: Int) throws(PicoKitError) {
        guard (0...29).contains(value) else { throw PicoKitError.invalidPin(value) }
        rawValue = UInt32(value)
    }
    public init?(rawValue: UInt32) { guard rawValue < 30 else { return nil }; self.rawValue = rawValue }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { "GPIO\(rawValue)" }
}

public extension PicoPin {
    static let gpio0 = try! PicoPin(0)
    static let gpio1 = try! PicoPin(1)
    static let gpio2 = try! PicoPin(2)
    static let gpio3 = try! PicoPin(3)
    static let gpio4 = try! PicoPin(4)
    static let gpio5 = try! PicoPin(5)
    static let gpio6 = try! PicoPin(6)
    static let gpio7 = try! PicoPin(7)
    static let gpio8 = try! PicoPin(8)
    static let gpio9 = try! PicoPin(9)
    static let gpio10 = try! PicoPin(10)
    static let gpio11 = try! PicoPin(11)
    static let gpio12 = try! PicoPin(12)
    static let gpio13 = try! PicoPin(13)
    static let gpio14 = try! PicoPin(14)
    static let gpio15 = try! PicoPin(15)
    static let gpio16 = try! PicoPin(16)
    static let gpio17 = try! PicoPin(17)
    static let gpio18 = try! PicoPin(18)
    static let gpio19 = try! PicoPin(19)
    static let gpio20 = try! PicoPin(20)
    static let gpio21 = try! PicoPin(21)
    static let gpio22 = try! PicoPin(22)
    static let gpio23 = try! PicoPin(23)
    static let gpio24 = try! PicoPin(24)
    static let gpio25 = try! PicoPin(25)
    static let gpio26 = try! PicoPin(26)
    static let gpio27 = try! PicoPin(27)
    static let gpio28 = try! PicoPin(28)
    static let gpio29 = try! PicoPin(29)
}

public struct Duration: Hashable, Sendable, Comparable {
    public let microseconds: UInt64
    private init(microseconds: UInt64) { self.microseconds = microseconds }
    public static func microseconds(_ value: UInt64) throws(PicoKitError) -> Self { guard value > 0 else { throw PicoKitError.invalidTimeout(value) }; return Self(microseconds: value) }
    public static func milliseconds(_ value: UInt64) throws(PicoKitError) -> Self {
        let result = value.multipliedReportingOverflow(by: 1_000)
        guard !result.overflow else { throw PicoKitError.invalidTimeout(value) }
        return try microseconds(result.partialValue)
    }
    public static func seconds(_ value: UInt64) throws(PicoKitError) -> Self {
        let result = value.multipliedReportingOverflow(by: 1_000_000)
        guard !result.overflow else { throw PicoKitError.invalidTimeout(value) }
        return try microseconds(result.partialValue)
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.microseconds < rhs.microseconds }
}

public struct Frequency: Hashable, Sendable, Comparable {
    public let hertz: UInt32
    private init(hertz: UInt32) { self.hertz = hertz }
    public static func hertz(_ value: UInt32) throws(PicoKitError) -> Self { guard value > 0 else { throw PicoKitError.invalidFrequency(value) }; return Self(hertz: value) }
    public static func kilohertz(_ value: UInt32) throws(PicoKitError) -> Self {
        let result = value.multipliedReportingOverflow(by: 1_000)
        guard !result.overflow else { throw PicoKitError.invalidFrequency(value) }
        return try hertz(result.partialValue)
    }
    public static func megahertz(_ value: UInt32) throws(PicoKitError) -> Self {
        let result = value.multipliedReportingOverflow(by: 1_000_000)
        guard !result.overflow else { throw PicoKitError.invalidFrequency(value) }
        return try hertz(result.partialValue)
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.hertz < rhs.hertz }
}

public enum PinMode: CaseIterable, Sendable { case input, output }
public enum PinPull: UInt32, CaseIterable, Sendable { case none, up, down }
public enum PinDriveStrength: UInt32, CaseIterable, Sendable {
    case milliamps2, milliamps4, milliamps8, milliamps12
}
public enum PinSlewRate: UInt32, CaseIterable, Sendable { case slow, fast }
public enum PinState: CaseIterable, Sendable {
    case low, high
    public var toggled: Self { self == .low ? .high : .low }
    public var isHigh: Bool { self == .high }
}

/// Implement this protocol for test doubles or alternative boards. Peripheral
/// instances are single-threaded: do not call an instance concurrently from
/// tasks, interrupt handlers, or multiple cores.
public protocol DigitalIO: AnyObject {
    func setMode(_ pin: PicoPin, mode: PinMode) throws(PicoKitError)
    func write(_ pin: PicoPin, state: PinState) throws(PicoKitError)
    func read(_ pin: PicoPin) throws(PicoKitError) -> PinState
}

// Familiar Arduino-style spellings. The Int overload is deliberately
// throwing: invalid GPIO numbers are reported before the SDK is touched.
@inlinable
public func pinMode(_ pin: Int, _ mode: PinMode, using gpio: some DigitalIO) throws(PicoKitError) {
    try gpio.setMode(PicoPin(pin), mode: mode)
}

@inlinable
public func digitalWrite(_ pin: Int, _ state: PinState, using gpio: some DigitalIO) throws(PicoKitError) {
    try gpio.write(PicoPin(pin), state: state)
}

@inlinable
public func digitalRead(_ pin: Int, using gpio: some DigitalIO) throws(PicoKitError) -> PinState {
    try gpio.read(PicoPin(pin))
}
