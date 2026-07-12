/// Arduino-style digital I/O primitives that work with a real Pico GPIO
/// controller or a test double.
public enum PinMode: CaseIterable, Sendable {
    case input
    case output
}

public enum PinState: CaseIterable, Sendable {
    case low
    case high

    public var toggled: Self { self == .low ? .high : .low }

    public var isHigh: Bool { self == .high }

    public init(_ isHigh: Bool) {
        self = isHigh ? .high : .low
    }
}

/// The small surface needed by `pinMode`, `digitalWrite`, and `digitalRead`.
///
/// Implement this protocol to use the Arduino-style helpers with an external
/// GPIO expander or a mock in tests.
public protocol DigitalIO: AnyObject {
    func pinMode(_ pin: Int, _ mode: PinMode)
    func digitalWrite(_ pin: Int, _ state: PinState)
    func digitalRead(_ pin: Int) -> PinState
}

@inlinable public func pinMode(_ pin: Int, _ mode: PinMode, using gpio: some DigitalIO) {
    gpio.pinMode(pin, mode)
}

@inlinable public func digitalWrite(_ pin: Int, _ state: PinState, using gpio: some DigitalIO) {
    gpio.digitalWrite(pin, state)
}

@inlinable public func digitalRead(_ pin: Int, using gpio: some DigitalIO) -> PinState {
    gpio.digitalRead(pin)
}

/// Memory-mapped GPIO for the RP2040 and RP2350 families.
///
/// It deliberately has no dependency on Foundation, so it can be imported by
/// an Embedded Swift firmware target. Create it only on the microcontroller.
public final class PicoGPIO: DigitalIO, @unchecked Sendable {
    /// Compatibility spelling for `PicoChip`.
    public typealias Chip = PicoChip

    public static let rp2040 = PicoGPIO(chip: .rp2040)
    public static let rp2350 = PicoGPIO(chip: .rp2350)

    private static let sioBase = 0xD000_0000
    private static let ioBank0Base = 0x4001_4000
    private static let padsBank0Base = 0x4001_C000

    public let chip: Chip
    public let pinCount: Int

    public init(chip: Chip = .rp2040) {
        self.chip = chip
        // Both chips expose GPIO 0...29 on the Pico-family boards.
        self.pinCount = 30
    }

    public func pinMode(_ pin: Int, _ mode: PinMode) {
        check(pin)
        selectSIO(pin)
        switch mode {
        case .output:
            write(PicoGPIO.sioBase + 0x24, bit(pin)) // GPIO_OE_SET
        case .input:
            write(PicoGPIO.sioBase + 0x28, bit(pin)) // GPIO_OE_CLR
            // PADS_BANK0 GPIOx: input-enable.
            let pad = PicoGPIO.padsBank0Base + 0x04 + (pin * 4)
            write(pad, read(pad) | (1 << 6))
        }
    }

    public func digitalWrite(_ pin: Int, _ state: PinState) {
        check(pin)
        write(PicoGPIO.sioBase + (state == .high ? 0x14 : 0x18), bit(pin))
    }

    public func digitalRead(_ pin: Int) -> PinState {
        check(pin)
        return (read(PicoGPIO.sioBase + 0x04) & bit(pin)) == 0 ? .low : .high
    }

    public func toggle(_ pin: Int) {
        check(pin)
        write(PicoGPIO.sioBase + 0x1C, bit(pin)) // GPIO_OUT_XOR
    }

    /// Select a peripheral function from the RP2040/RP2350 function table.
    public func selectFunction(_ pin: Int, _ function: UInt32) {
        check(pin)
        precondition(function < 32, "GPIO function must fit in five bits")
        let control = PicoGPIO.ioBank0Base + 0x04 + (pin * 8)
        write(control, (read(control) & ~0x1F) | function)
    }

    private func selectSIO(_ pin: Int) { selectFunction(pin, 5) }

    private func check(_ pin: Int) {
        precondition((0..<pinCount).contains(pin), "Pico GPIO pin must be in 0...\(pinCount - 1)")
    }

    @inline(__always) private func bit(_ pin: Int) -> UInt32 { 1 << UInt32(pin) }

    @inline(__always) private func read(_ address: Int) -> UInt32 {
        UnsafePointer<UInt32>(bitPattern: address)!.pointee
    }

    @inline(__always) private func write(_ address: Int, _ value: UInt32) {
        UnsafeMutablePointer<UInt32>(bitPattern: address)!.pointee = value
    }
}
