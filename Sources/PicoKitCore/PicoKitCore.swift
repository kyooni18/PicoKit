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
    case unavailable(String)
    case timedOut(operation: String)
    case ioFailure(operation: String, status: Int32)
    case ownershipConflict(String)

    public var description: String {
        switch self {
        case .invalidPin(let pin): "GPIO pin \(pin) is outside 0...29"
        case .invalidFrequency(let hertz): "frequency \(hertz) Hz must be greater than zero"
        case .invalidTimeout(let microseconds): "timeout \(microseconds) us must be greater than zero"
        case .invalidAddress(let address): "I2C address 0x\(String(address, radix: 16)) is outside 0x08...0x77"
        case .unavailable(let feature): "\(feature) is unavailable for this board or build"
        case .timedOut(let operation): "\(operation) timed out"
        case .ioFailure(let operation, let status): "\(operation) failed with SDK status \(status)"
        case .ownershipConflict(let peripheral): "\(peripheral) is already owned by another PicoKit instance"
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
