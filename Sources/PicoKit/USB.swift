/// USB Device controller utilities for RP2350 (Pico 2).
///
/// The RP2350 has a native USB 1.1 device controller. This module provides
/// low-level register access for USB CDC (Communications Device Class) ACM
/// (Abstract Control Model) serial communication.
///
/// NOTE: Full USB enumeration requires a proper USB stack. This module provides
/// the hardware register interface; use with an Embedded Swift USB stack or
/// link against pico-sdk's usb_common module for complete CDC-ACM support.

#if canImport(Darwin)
// This module is intended for embedded targets only.
#else

public final class PicoUSB: @unchecked Sendable {
    /// USB device controller base address (RP2350 only).
    private static let base = 0x5000_0000

    /// USB CTRL — control register
    private static let ctrlOffset = 0x00
    /// USB INTR — interrupt status
    private static let intrOffset = 0x04
    /// USB IE — interrupt enable
    private static let ieOffset = 0x08

    /// Number of endpoint registers.
    private static let endpointCount = 16

    public init() {
        precondition(Self.isRP2350(), "USB device controller is only available on RP2350 (Pico 2)")
    }

    /// Check if running on RP2350 (USB DC present).
    public static func isRP2350() -> Bool {
        // Check USB DC ID register
        let id = read(Self.base + 0x10) // USB ID
        return (id >> 16) == 0x100 // USB DC signature
    }

    /// Enable the USB device controller.
    public func enable() {
        write(Self.base + Self.ctrlOffset, read(Self.base + Self.ctrlOffset) | 1)
    }

    /// Disable the USB device controller.
    public func disable() {
        write(Self.base + Self.ctrlOffset, read(Self.base + Self.ctrlOffset) & ~1)
    }

    /// Reset the USB device controller.
    public func reset() {
        write(Self.base + Self.ctrlOffset, read(Self.base + Self.ctrlOffset) | (1 << 1))
        write(Self.base + Self.ctrlOffset, read(Self.base + Self.ctrlOffset) & ~(1 << 1))
    }

    /// Set device address.
    public func setAddress(_ address: UInt8) {
        write(Self.base + Self.ctrlOffset, (read(Self.base + Self.ctrlOffset) & ~0xFF00) | (UInt32(address) << 8))
    }

    /// Read interrupt status.
    public func interruptStatus() -> UInt32 {
        read(Self.base + Self.intrOffset)
    }

    /// Clear all pending interrupts.
    public func clearInterrupts() {
        write(Self.base + Self.intrOffset, 0xFFFFFFFF)
    }

    /// Enable specific interrupts.
    public func enableInterrupts(_ mask: UInt32) {
        write(Self.base + Self.ieOffset, mask)
    }

    /// Disable specific interrupts.
    public func disableInterrupts(_ mask: UInt32) {
        write(Self.base + Self.ieOffset, ~mask)
    }

    /// Write to endpoint TX FIFO.
    public func endpointWrite(_ endpoint: Int, _ data: UnsafeBufferPointer<UInt8>) {
        precondition(endpoint < Self.endpointCount, "endpoint must be 0-\(Self.endpointCount - 1)")
        let epBase = Self.base + 0x100 + (endpoint * 0x40)
        // EP TX CTRL: enable
        write(epBase + 0x00, read(epBase + 0x00) | 1)
        // Write data to EP TX FIFO
        let fifoPtr = UnsafeMutablePointer<UInt32>(bitPattern: epBase + 0x100)!
        var idx = 0
        while idx < data.count {
            let remaining = min(4, data.count - idx)
            var word: UInt32 = 0
            for i in 0..<remaining {
                word |= UInt32(data[idx + i]) << (i * 8)
            }
            fifoPtr.pointee = word
            idx += remaining
        }
        // Signal ready
        write(epBase + 0x04, read(epBase + 0x04) | 1) // EP TX ISR: set ready
    }

    /// Read from endpoint RX FIFO.
    public func endpointRead(_ endpoint: Int, count: Int) -> [UInt8] {
        precondition(endpoint < Self.endpointCount, "endpoint must be 0-\(Self.endpointCount - 1)")
        let epBase = Self.base + 0x100 + (endpoint * 0x40)

        // Check if data is available
        guard (read(epBase + 0x08) & 1) != 0 else { return [] } // EP RX ISR: full

        var result: [UInt8] = []
        result.reserveCapacity(count)
        let fifoPtr = UnsafePointer<UInt32>(bitPattern: epBase + 0x104)!

        for _ in 0..<count {
            let word = fifoPtr.pointee
            result.append(UInt8(word & 0xFF))
        }

        // Signal processed
        write(epBase + 0x0C, 1) // EP RX ISR: clear full
        return result
    }

    @inline(__always) private func read(_ address: Int) -> UInt32 {
        UnsafePointer<UInt32>(bitPattern: address)!.pointee
    }

    @inline(__always) private func write(_ address: Int, _ value: UInt32) {
        UnsafeMutablePointer<UInt32>(bitPattern: address)!.pointee = value
    }
}

#endif
