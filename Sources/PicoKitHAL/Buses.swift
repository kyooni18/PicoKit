#if !PICOKIT_PICO_SDK
import PicoKitCore
#endif

public enum I2CInstance: UInt32, Sendable { case i2c0, i2c1 }

public final class PicoI2C {
    public let instance: I2CInstance

    public init(_ instance: I2CInstance, frequency: Frequency, sda: PicoPin, scl: PicoPin) throws(PicoKitError) {
        #if PICOKIT_PICO_SDK
        let status = picokit_i2c_init(instance.rawValue, frequency.hertz, sda.rawValue, scl.rawValue)
        guard status == 0 else {
            throw PicoKitError.ioFailure(operation: "I2C setup", status: status)
        }
        self.instance = instance
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func write(address: UInt8, bytes: [UInt8], timeout: Duration) throws(PicoKitError) -> Int {
        guard (0x08...0x77).contains(address) else { throw PicoKitError.invalidAddress(address) }
        guard timeout.microseconds <= UInt64(UInt32.max) else {
            throw PicoKitError.invalidTimeout(timeout.microseconds)
        }
        #if PICOKIT_PICO_SDK
        let result = bytes.withUnsafeBufferPointer {
            picokit_i2c_write(instance.rawValue, UInt32(address), $0.baseAddress, UInt32($0.count), timeout.microseconds)
        }
        if result == -2 { throw PicoKitError.timedOut(operation: "I2C write") }
        guard result >= 0 else {
            throw PicoKitError.ioFailure(operation: "I2C write", status: result)
        }
        return Int(result)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func read(address: UInt8, count: Int, timeout: Duration) throws(PicoKitError) -> [UInt8] {
        guard (0x08...0x77).contains(address) else { throw PicoKitError.invalidAddress(address) }
        guard count >= 0 else { throw PicoKitError.ioFailure(operation: "I2C read", status: -1) }
        guard timeout.microseconds <= UInt64(UInt32.max) else {
            throw PicoKitError.invalidTimeout(timeout.microseconds)
        }
        #if PICOKIT_PICO_SDK
        var result = [UInt8](repeating: 0, count: count)
        let status = result.withUnsafeMutableBufferPointer {
            picokit_i2c_read(instance.rawValue, UInt32(address), $0.baseAddress, UInt32($0.count), timeout.microseconds)
        }
        if status == -2 { throw PicoKitError.timedOut(operation: "I2C read") }
        guard status == Int32(count) else {
            throw PicoKitError.ioFailure(operation: "I2C read", status: status)
        }
        return result
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
}

public enum SPIInstance: UInt32, Sendable { case spi0, spi1 }

public final class PicoSPI {
    public let instance: SPIInstance

    public init(_ instance: SPIInstance, frequency: Frequency, sck: PicoPin, mosi: PicoPin, miso: PicoPin) throws(PicoKitError) {
        #if PICOKIT_PICO_SDK
        let status = picokit_spi_init(instance.rawValue, frequency.hertz, sck.rawValue, mosi.rawValue, miso.rawValue)
        guard status == 0 else {
            throw PicoKitError.ioFailure(operation: "SPI setup", status: status)
        }
        self.instance = instance
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func transfer(_ bytes: [UInt8], timeout: Duration) throws(PicoKitError) -> [UInt8] {
        #if PICOKIT_PICO_SDK
        var received = [UInt8](repeating: 0, count: bytes.count)
        let status = bytes.withUnsafeBufferPointer { tx in
            received.withUnsafeMutableBufferPointer { rx in
                picokit_spi_transfer(instance.rawValue, tx.baseAddress, rx.baseAddress, UInt32(tx.count), timeout.microseconds)
            }
        }
        if status == -2 { throw PicoKitError.timedOut(operation: "SPI transfer") }
        guard status == Int32(bytes.count) else {
            throw PicoKitError.ioFailure(operation: "SPI transfer", status: status)
        }
        return received
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
}

