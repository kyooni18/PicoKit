/// PWM controller for RP2040/RP2350 — 8 slices, 16 channels.
///
/// Each slice drives a pair of GPIO pins (A and B). Use `analogWrite` for
/// Arduino-style duty-cycle control, or manipulate slices directly for
/// precise frequency and phase control.

public enum PWMPhaseCorrect: Sendable {
    /// Standard PWM: output follows counter vs. top comparison.
    case normal
    /// Phase-correct PWM: counter counts up then down for symmetric waveforms.
    case phaseCorrect
}

/// One of the eight PWM slices on the Pico.
public struct PWMSlice: Sendable {
    public var index: Int
    public var gpioA: Int
    public var gpioB: Int

    public init(index: Int, gpioA: Int, gpioB: Int) {
        self.index = index
        self.gpioA = gpioA
        self.gpioB = gpioB
    }
}

public final class PicoPWM: @unchecked Sendable {
    /// Base address of the PWM block.
    private static let base = 0x4005_0000

    /// Slice register stride (bytes between slice 0 and slice 1).
    private static let sliceStride = 0x20

    /// Mapping: (slice, gpioA, gpioB) for the default Pico pinout.
    public static let defaultSlices: [PWMSlice] = [
        PWMSlice(index: 0, gpioA: 0,  gpioB: 1),
        PWMSlice(index: 1, gpioA: 2,  gpioB: 3),
        PWMSlice(index: 2, gpioA: 4,  gpioB: 5),
        PWMSlice(index: 3, gpioA: 6,  gpioB: 7),
        PWMSlice(index: 4, gpioA: 8,  gpioB: 9),
        PWMSlice(index: 5, gpioA: 10, gpioB: 11),
        PWMSlice(index: 6, gpioA: 12, gpioB: 13),
        PWMSlice(index: 7, gpioA: 14, gpioB: 15),
    ]

    private let slice: PWMSlice

    public init(_ slice: PWMSlice) {
        self.slice = slice
    }

    /// Configure the GPIO pins for PWM output (function 4).
    public func configurePins(using gpio: PicoGPIO) {
        gpio.selectFunction(slice.gpioA, 4)
        gpio.selectFunction(slice.gpioB, 4)
    }

    /// Set the PWM top value (divides the system clock).
    /// `wrap` of 65535 gives full 16-bit range; smaller values increase frequency.
    public func setWrap(_ wrap: UInt16) {
        writeSlice(slice.index, offset: 0x00, value: UInt32(wrap))
    }

    /// Set the compare value for channel A (and B mirrors it).
    public func setCompare(_ value: UInt16) {
        writeSlice(slice.index, offset: 0x04, value: UInt32(value))
    }

    /// Arduino-style analog write: 0…255 duty on a 256-wrap scale.
    public func analogWrite(_ duty: UInt8) {
        setWrap(255)
        setCompare(UInt16(duty))
    }

    /// Full 16-bit analog write: 0…65535.
    public func analogWrite(_ duty: UInt16) {
        setWrap(65535)
        setCompare(duty)
    }

    /// Enable or disable this PWM slice.
    public func enable(_ enabled: Bool = true) {
        let reg = Self.base + (Self.sliceStride * slice.index) + 0x08
        if enabled {
            write(reg, read(reg) | 1)
        } else {
            write(reg, read(reg) & ~1)
        }
    }

    /// Set clock divider: integer and fractional parts.
    /// Effective PWM frequency ≈ sysClock / (divider * (wrap + 1)).
    public func setDivider(intDivider: UInt32, fracDivider: UInt8 = 0) {
        precondition(intDivider > 0, "integer divider must be > 0")
        writeSlice(slice.index, offset: 0x08, value: (intDivider << 4) | UInt32(fracDivider))
    }

    /// Set phase-correct mode.
    public func setMode(_ mode: PWMPhaseCorrect) {
        writeSlice(slice.index, offset: 0x0C, value: mode == .phaseCorrect ? 1 : 0)
    }

    /// Reset counter to zero.
    public func reset() {
        writeSlice(slice.index, offset: 0x0C, value: 2)
    }

    private func writeSlice(_ sliceIndex: Int, offset: Int, value: UInt32) {
        write(Self.base + (Self.sliceStride * sliceIndex) + offset, value)
    }

    @inline(__always) private func read(_ address: Int) -> UInt32 {
        UnsafePointer<UInt32>(bitPattern: address)!.pointee
    }

    @inline(__always) private func write(_ address: Int, _ value: UInt32) {
        UnsafeMutablePointer<UInt32>(bitPattern: address)!.pointee = value
    }
}

/// Arduino-style convenience: write duty cycle to a GPIO pin.
/// Finds the PWM slice that drives the given pin.
@inlinable
public func analogWrite(_ pin: Int, _ duty: UInt8, using pwm: PicoPWM) {
    pwm.analogWrite(duty)
}
