/// SPI driver for RP2040/RP2350.
///
/// Supports SPI0 and SPI1. Configure MOSI, MISO, SCK, and CS pins before use.

public enum SPIBitOrder: Sendable {
    case msbFirst
    case lsbFirst
}

public enum SPIMode: Sendable {
    case mode0 // CPOL=0, CPHA=0
    case mode1 // CPOL=0, CPHA=1
    case mode2 // CPOL=1, CPHA=0
    case mode3 // CPOL=1, CPHA=1

    var cpol: UInt32 { rawValue & 0x2 }
    var cpha: UInt32 { rawValue & 0x1 }

}

extension SPIMode: RawRepresentable {
    public init(rawValue: UInt32) {
        switch rawValue {
        case 0: self = .mode0
        case 1: self = .mode1
        case 2: self = .mode2
        default: self = .mode3
        }
    }

    public var rawValue: UInt32 {
        switch self {
        case .mode0: 0
        case .mode1: 1
        case .mode2: 2
        case .mode3: 3
        }
    }
}

public final class PicoSPI: @unchecked Sendable {
    public enum Instance: Sendable {
        case spi0
        case spi1

        fileprivate var base: Int {
            self == .spi0 ? 0x4002_0000 : 0x4002_2000
        }
    }

    private let base: Int

    public init(
        _ instance: Instance = .spi0,
        frequencyHz: UInt32 = 1_000_000,
        mode: SPIMode = .mode0,
        bitOrder: SPIBitOrder = .msbFirst,
        clockHz: UInt32 = 48_000_000
    ) {
        base = instance.base
        configure(frequencyHz: frequencyHz, mode: mode, bitOrder: bitOrder, clockHz: clockHz)
    }

    /// Route SPI pins (SCK, MOSI, MISO) to function 0 (SPI0) or 4 (SPI1).
    public func configurePins(sck: Int, mosi: Int, miso: Int, cs: Int, using gpio: PicoGPIO) {
        let funcNum: UInt32 = base == 0x4002_0000 ? 0 : 4
        gpio.selectFunction(sck, funcNum)
        gpio.selectFunction(mosi, funcNum)
        gpio.selectFunction(miso, funcNum)
        gpio.pinMode(cs, .output)
    }

    private func configure(frequencyHz: UInt32, mode: SPIMode, bitOrder: SPIBitOrder, clockHz: UInt32) {
        // SPIMCR: enable, mode, bit order
        var mcr: UInt32 = (1 << 6) // SPIE
        mcr |= (mode.rawValue & 0x1) << 1 // CPHA
        mcr |= (mode.rawValue & 0x2) >> 1 // CPOL
        if bitOrder == .lsbFirst { mcr |= 1 << 4 } // LSBF
        write(0x00, mcr)

        // Divider: div = clockHz / frequencyHz - 1
        let divider = max(1, clockHz / frequencyHz - 1)
        write(0x04, divider & 0xFF) // SPIDIV
    }

    /// Transfer a single byte (simultaneous read/write).
    @discardableResult
    public func transfer(_ byte: UInt8) -> UInt8 {
        write(0x08, UInt32(byte)) // SPITX
        while (read(0x24) & (1 << 1)) != 0 {} // SPISR: TBF
        return UInt8(read(0x10)) // SPIRX
    }

    /// Transfer a buffer, returning received bytes.
    @discardableResult
    public func transfer(_ bytes: UnsafeBufferPointer<UInt8>) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        for byte in bytes {
            result.append(transfer(byte))
        }
        return result
    }

    /// Write bytes without reading response.
    public func writeBytes(_ bytes: UnsafeBufferPointer<UInt8>) {
        for byte in bytes {
            write(0x08, UInt32(byte))
            while (read(0x24) & (1 << 1)) != 0 {}
            _ = read(0x10) // drain RX
        }
    }

    /// Read bytes by transferring dummy bytes (0x00).
    public func readBytes(count: Int) -> [UInt8] {
        let dummy = [UInt8](repeating: 0, count: count)
        return dummy.withUnsafeBufferPointer { transfer($0) }
    }

    /// Enable or disable SPI.
    public func enable(_ enabled: Bool = true) {
        if enabled {
            write(0x00, read(0x00) | (1 << 6))
        } else {
            write(0x00, read(0x00) & ~(1 << 6))
        }
    }

    @inline(__always) private func read(_ offset: Int) -> UInt32 {
        UnsafePointer<UInt32>(bitPattern: base + offset)!.pointee
    }

    @inline(__always) private func write(_ offset: Int, _ value: UInt32) {
        UnsafeMutablePointer<UInt32>(bitPattern: base + offset)!.pointee = value
    }
}
