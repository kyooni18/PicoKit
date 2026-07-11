/// Watchdog timer for RP2040/RP2350.
///
/// The watchdog forces a reset if not喂 (pet/kick) within the timeout period.
/// Default timeout is 1 second.

public final class PicoWatchdog: @unchecked Sendable {
    /// Watchdog base address.
    private static let base = 0x4000_E000

    /// WD_CTRL register offset.
    private static let ctrlOffset = 0x04
    /// WD喂 register offset (write 0xA7B8 to feed).
    private static let feedOffset = 0x00

    /// Default timeout in microseconds.
    /// Current timeout in microseconds.
    public private(set) var timeoutUs: UInt32 = 1_000_000

    /// Whether the watchdog is currently enabled.
    public var isEnabled: Bool {
        (read(Self.base + Self.ctrlOffset) & 1) != 0
    }

    public init() {}

    /// Enable the watchdog with the given timeout (microseconds).
    /// Minimum timeout is approximately 1 ms.
    public func enable(timeoutUs: UInt32 = 1_000_000) {
        self.timeoutUs = max(1_000, timeoutUs)
        // WD_CTRL: timeout (bits 31:4), enable (bit 0)
        write(Self.base + Self.ctrlOffset, (self.timeoutUs >> 2) | 1)
    }

    /// Disable the watchdog.
    public func disable() {
        write(Self.base + Self.ctrlOffset, 0)
    }

    /// Feed (pet/kick) the watchdog to reset its countdown.
    /// Must be called before timeout expires, or the system will reset.
    public func feed() {
        write(Self.base + Self.feedOffset, 0xA7B8)
    }

    /// Check if the last reset was caused by the watchdog.
    public static func wasLastResetByWatchdog() -> Bool {
        let address = Self.base + Self.ctrlOffset
        return (UnsafePointer<UInt32>(bitPattern: address)!.pointee & (1 << 31)) != 0
    }

    @inline(__always) private func read(_ address: Int) -> UInt32 {
        UnsafePointer<UInt32>(bitPattern: address)!.pointee
    }

    @inline(__always) private func write(_ address: Int, _ value: UInt32) {
        UnsafeMutablePointer<UInt32>(bitPattern: address)!.pointee = value
    }
}
