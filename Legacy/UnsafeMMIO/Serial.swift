/// A byte output device. UART, USB CDC, buffers, and test doubles can all
/// conform without bringing host-only APIs into embedded firmware.
public protocol ByteSink: AnyObject {
    func write(_ bytes: UnsafeBufferPointer<UInt8>)
}

public protocol ByteSource: AnyObject {
    func read() -> UInt8?
}

public typealias SerialPort = ByteSink & ByteSource

public extension ByteSink {
    func write(_ byte: UInt8) {
        var byte = byte
        withUnsafePointer(to: &byte) { pointer in
            write(UnsafeBufferPointer(start: pointer, count: 1))
        }
    }

    func write<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
        for byte in bytes { write(byte) }
    }

    func write(_ text: String) {
        write(text.utf8)
    }

    func print(_ value: some CustomStringConvertible, terminator: String = "\r\n") {
        write(String(describing: value))
        write(terminator)
    }
}

/// A minimal PL011 UART driver for UART0/UART1 on RP2040 and RP2350.
/// Configure the matching GPIO pins with `configurePins` before use.
public final class PicoUART: SerialPort, @unchecked Sendable {
    public enum Instance: Sendable {
        case uart0
        case uart1

        fileprivate var base: Int { self == .uart0 ? 0x4003_4000 : 0x4003_8000 }
    }

    private let base: Int

    public init(_ instance: Instance = .uart0, baudRate: UInt32 = 115_200, clockHz: UInt32 = 48_000_000) {
        precondition(baudRate > 0 && clockHz > 0)
        base = instance.base
        configure(baudRate: baudRate, clockHz: clockHz)
    }

    /// Routes the selected GPIO pins to the UART peripheral (function 2).
    public func configurePins(tx: Int, rx: Int, using gpio: PicoGPIO) {
        gpio.selectFunction(tx, 2)
        gpio.selectFunction(rx, 2)
    }

    public func write(_ bytes: UnsafeBufferPointer<UInt8>) {
        for byte in bytes {
            while (read(0x18) & (1 << 5)) != 0 {} // UARTFR.TXFF
            write(0x00, UInt32(byte))
        }
    }

    public func read() -> UInt8? {
        guard (read(0x18) & (1 << 4)) == 0 else { return nil } // UARTFR.RXFE
        return UInt8(truncatingIfNeeded: read(0x00))
    }

    private func configure(baudRate: UInt32, clockHz: UInt32) {
        write(0x30, 0) // UARTCR: disable while changing divisors
        let divisor = (UInt64(clockHz) * 64) / (UInt64(baudRate) * 16)
        write(0x24, UInt32(divisor / 64))
        write(0x28, UInt32(divisor % 64))
        write(0x2C, (3 << 5) | (1 << 4)) // 8 data bits, FIFO enabled
        write(0x30, (1 << 9) | (1 << 8) | 1) // RXE, TXE, UARTEN
    }

    @inline(__always) private func read(_ offset: Int) -> UInt32 {
        UnsafePointer<UInt32>(bitPattern: base + offset)!.pointee
    }

    @inline(__always) private func write(_ offset: Int, _ value: UInt32) {
        UnsafeMutablePointer<UInt32>(bitPattern: base + offset)!.pointee = value
    }
}
