/// I2C driver for RP2040/RP2350 — Wire-compatible API.
///
/// Supports I2C0 and I2C1 with standard (100 kHz) and fast (400 kHz) modes.

public enum I2CBusSpeed: Sendable {
    case standard   // 100 kHz
    case `fast`     // 400 kHz
    case fastPlus   // 1 MHz

    var kHz: UInt32 {
        switch self {
        case .standard: 100
        case .fast: 400
        case .fastPlus: 1000
        }
    }
}

public final class PicoI2C: @unchecked Sendable {
    public enum Instance: Sendable {
        case i2c0
        case i2c1

        fileprivate var base: Int {
            self == .i2c0 ? 0x4002_4000 : 0x4002_8000
        }
    }

    private let base: Int

    public init(_ instance: Instance = .i2c0, speed: I2CBusSpeed = .standard, clockHz: UInt32 = 48_000_000) {
        base = instance.base
        configure(speed: speed, clockHz: clockHz)
    }

    /// Route SDA/SCL GPIO pins to the I2C peripheral (function 2).
    public func configurePins(sda: Int, scl: Int, using gpio: PicoGPIO) {
        gpio.selectFunction(sda, 2)
        gpio.selectFunction(scl, 2)
    }

    private func configure(speed: I2CBusSpeed, clockHz: UInt32) {
        // I2C_IC_CON: enable, 7-bit addressing
        write(0x00, (1 << 1) | 1)
        // Calculate divider: div = clockHz / (speed * 1000 * 2) — approximate
        let divider = clockHz / (speed.kHz * 1000)
        write(0x6C, UInt32(divider)) // I2C_IC_SS_SCL_HCNT
        write(0x70, UInt32(divider)) // I2C_IC_SS_SCL_LCNT
    }

    /// Begin a transmission to `address`. Returns true if ACK received.
    @discardableResult
    public func beginTransmission(_ address: UInt8) -> Bool {
        write(0x24, UInt32(address)) // I2C_IC_TX_ABRT_SOURCE — use DATA_CMD
        // Write address with START + WRITE
        write(0x2C, (UInt32(address) << 8) | (1 << 0) | (1 << 5)) // I2C_IC_DATA_CMD: DATA + START + WRITE
        // Wait for transmission
        while (read(0x20) & (1 << 4)) != 0 {} // I2C_IC_STATUS: TNACK
        return (read(0x20) & (1 << 4)) == 0
    }

    /// Write bytes to the previously addressed device.
    public func writeBytes(_ bytes: UnsafeBufferPointer<UInt8>) {
        for byte in bytes {
            write(0x2C, UInt32(byte) | (1 << 0)) // DATA + TX
            while (read(0x14) & 1) == 0 {} // I2C_IC_RAW_INTR: TDF (TX data ready)
        }
    }

    /// Write a single byte.
    public func write(_ byte: UInt8) {
        write(0x2C, UInt32(byte) | (1 << 0))
        while (read(0x14) & 1) == 0 {}
    }

    /// Send STOP condition.
    public func endTransmission() {
        write(0x2C, (1 << 5) | (1 << 6)) // STOP + START (combined)
        while (read(0x28) & 1) != 0 {} // I2C_IC_TRANSFER_IN_PROGRESS
    }

    /// Read `count` bytes from `address`, sending STOP after.
    public func readBytes(_ address: UInt8, count: Int) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(count)

        // Restart with READ direction
        write(0x2C, (UInt32(address) << 8) | (1 << 0) | (1 << 1) | (1 << 5)) // DATA + RD + START
        while (read(0x20) & (1 << 4)) != 0 {}

        for i in 0..<count {
            // For last byte, send NACK; otherwise ACK
            let ack: UInt32 = (i == count - 1) ? 0 : (1 << 7)
            write(0x34, ack) // I2C_IC_RX_TL: set receive threshold

            // Request receive
            while (read(0x14) & (1 << 1)) == 0 {} // RDF (RX data ready)
            result.append(UInt8(read(0x30))) // I2C_IC_DATA_RX
        }

        // STOP
        write(0x2C, (1 << 6))
        while (read(0x28) & 1) != 0 {}

        return result
    }

    /// Request `count` bytes from `address` (simplified transaction).
    public func requestFrom(_ address: UInt8, count: Int) -> [UInt8] {
        readBytes(address, count: count)
    }

    @inline(__always) private func read(_ offset: Int) -> UInt32 {
        UnsafePointer<UInt32>(bitPattern: base + offset)!.pointee
    }

    @inline(__always) private func write(_ offset: Int, _ value: UInt32) {
        UnsafeMutablePointer<UInt32>(bitPattern: base + offset)!.pointee = value
    }
}
