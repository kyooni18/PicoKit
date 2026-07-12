/// Timer and delay utilities for RP2040/RP2350.
///
/// Provides `delay(ms)` and `delayMicroseconds(us)` using the system timer,
/// plus a simple `Millis` struct for non-blocking timing.

public final class PicoTimer: @unchecked Sendable {
    /// System timer base address.
    private static let timerBase = 0x4005_4000

    /// IO bus timer base (for IO-domain accesses).
    private static let ioTimerBase = 0xD000_0000 + 0x4000

    /// Read the 64-bit free-running system counter (microseconds since boot).
    @inline(__always)
    public static func getTimeUs() -> UInt64 {
        let loAddr = Self.timerBase + 0x00
        let hiAddr = Self.timerBase + 0x04
        var lo = UnsafePointer<UInt32>(bitPattern: loAddr)!.pointee
        var hi = UnsafePointer<UInt32>(bitPattern: hiAddr)!.pointee
        // Re-read LO if HI changed (torn read protection)
        let lo2 = UnsafePointer<UInt32>(bitPattern: loAddr)!.pointee
        if lo2 != lo {
            lo = lo2
            hi = UnsafePointer<UInt32>(bitPattern: hiAddr)!.pointee
        }
        return (UInt64(hi) << 32) | UInt64(lo)
    }

    /// Block for the given number of milliseconds.
    public static func delay(_ ms: UInt32) {
        let target = Self.getTimeUs() + UInt64(ms) * 1_000
        while Self.getTimeUs() < target {}
    }

    /// Block for the given number of microseconds.
    public static func delayMicroseconds(_ us: UInt32) {
        let target = Self.getTimeUs() + UInt64(us)
        while Self.getTimeUs() < target {}
    }

    /// Configure a hardware timer interrupt.
    /// `alarm` is one of the four alarm registers (0-3).
    public static func setAlarm(_ alarm: Int, _ value: UInt32) {
        precondition(alarm < 4, "alarm must be 0-3")
        let ptr = UnsafeMutablePointer<UInt32>(bitPattern: Self.timerBase + 0x20 + (alarm * 0x14))!
        ptr.pointee = value
    }

    /// Enable or disable a specific alarm.
    public static func enableAlarm(_ alarm: Int, _ enabled: Bool) {
        precondition(alarm < 4, "alarm must be 0-3")
        let ptr = UnsafeMutablePointer<UInt32>(bitPattern: Self.timerBase + 0x40)!
        if enabled {
            ptr.pointee |= (1 << alarm)
        } else {
            ptr.pointee &= ~(1 << alarm)
        }
    }
}

/// Non-blocking millisecond timer — Arduino `millis()` compatible.
public struct ElapsedTimer: Sendable {
    private var start: UInt64

    /// Create a new timer anchored to the current system time.
    public init() {
        self.start = PicoTimer.getTimeUs()
    }

    /// Milliseconds elapsed since this timer was created.
    public func elapsed() -> UInt64 {
        (PicoTimer.getTimeUs() - start) / 1_000
    }

    /// Microseconds elapsed since this timer was created.
    public func elapsedMicroseconds() -> UInt64 {
        PicoTimer.getTimeUs() - start
    }

    /// Reset the timer anchor to now.
    public mutating func reset() {
        start = PicoTimer.getTimeUs()
    }

    /// Check if at least `ms` milliseconds have elapsed.
    public func hasElapsed(_ ms: UInt64) -> Bool {
        elapsed() >= ms
    }
}

@available(*, deprecated, renamed: "ElapsedTimer")
public typealias Millis = ElapsedTimer

/// Arduino-style global delay functions.
public func delay(_ ms: UInt32) {
    PicoTimer.delay(ms)
}

public func delayMicroseconds(_ us: UInt32) {
    PicoTimer.delayMicroseconds(us)
}

public func millis() -> UInt64 {
    PicoTimer.getTimeUs() / 1_000
}

public func micros() -> UInt64 {
    PicoTimer.getTimeUs()
}
