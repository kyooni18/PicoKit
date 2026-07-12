/// Software-based bit-bang I2C for cases where hardware I2C is unavailable.
///
/// Uses GPIO pins directly with precise timing. Slower than hardware I2C but
/// works on any pair of GPIO pins.

public final class SoftwareI2C: @unchecked Sendable {
    private let sdaPin: Int
    private let sclPin: Int
    private let gpio: PicoGPIO
    private var speed: I2CBusSpeed

    /// Create a software I2C bus on arbitrary GPIO pins.
    public init(sda: Int, scl: Int, using gpio: PicoGPIO, speed: I2CBusSpeed = .standard) {
        self.sdaPin = sda
        self.sclPin = scl
        self.gpio = gpio
        self.speed = speed
        gpio.pinMode(sda, .output)
        gpio.pinMode(scl, .output)
        // Release lines (pull high)
        gpio.digitalWrite(sda, .high)
        gpio.digitalWrite(scl, .high)
    }

    private var halfPeriodUs: UInt32 {
        max(1, 500_000 / speed.hertz)
    }

    /// Generate a START condition.
    private func start() {
        // SDA high, SCL high → SDA low (while SCL high)
        gpio.digitalWrite(sdaPin, .high)
        sclHigh()
        gpio.digitalWrite(sdaPin, .low)
        delayHalfPeriod()
    }

    /// Generate a STOP condition.
    private func stop() {
        // SDA low, SCL high → SDA high (while SCL high)
        gpio.digitalWrite(sdaPin, .low)
        sclHigh()
        gpio.digitalWrite(sdaPin, .high)
        delayHalfPeriod()
    }

    private func sclHigh() {
        gpio.digitalWrite(sclPin, .high)
    }

    private func sclLow() {
        gpio.digitalWrite(sclPin, .low)
    }

    private func delayHalfPeriod() {
        PicoTimer.delayMicroseconds(halfPeriodUs)
    }

    /// Write a single bit (MSB first).
    private func writeBit(_ bit: Bool) {
        gpio.digitalWrite(sdaPin, bit ? .high : .low)
        sclHigh()
        delayHalfPeriod()
        sclLow()
        delayHalfPeriod()
    }

    /// Read a single bit.
    private func readBit() -> Bool {
        gpio.pinMode(sdaPin, .input)
        sclHigh()
        delayHalfPeriod()
        let value = gpio.digitalRead(sdaPin) == .high
        sclLow()
        delayHalfPeriod()
        gpio.pinMode(sdaPin, .output)
        return value
    }

    /// Write a byte, return ACK status.
    @discardableResult
    public func writeByte(_ byte: UInt8) -> Bool {
        for i in (0...7).reversed() {
            writeBit((byte & (1 << i)) != 0)
        }
        // Read ACK
        return !readBit()
    }

    /// Read a byte, send ACK/NACK.
    public func readByte(ack: Bool) -> UInt8 {
        var byte: UInt8 = 0
        for i in 0...7 {
            if readBit() { byte |= (1 << i) }
        }
        writeBit(!ack)
        return byte
    }

    /// Transaction: write to device, then read.
    public func transaction(address: UInt8, writeBytes: [UInt8], readCount: Int) -> [UInt8] {
        start()

        // Write address + W
        _ = writeByte((address << 1) & 0xFE)

        // Write data
        for byte in writeBytes {
            writeByte(byte)
        }

        // Restart + Read address + R
        start()
        _ = writeByte((address << 1) | 1)

        // Read data
        var result: [UInt8] = []
        for i in 0..<readCount {
            result.append(readByte(ack: i < readCount - 1))
        }

        stop()
        return result
    }

    /// Simple write: address → bytes → stop.
    public func write(address: UInt8, bytes: [UInt8]) {
        start()
        _ = writeByte((address << 1) & 0xFE)
        for byte in bytes {
            writeByte(byte)
        }
        stop()
    }

    /// Simple read: address → bytes → stop.
    public func read(address: UInt8, count: Int) -> [UInt8] {
        start()
        _ = writeByte((address << 1) | 1)
        var result: [UInt8] = []
        for i in 0..<count {
            result.append(readByte(ack: i < count - 1))
        }
        stop()
        return result
    }
}
