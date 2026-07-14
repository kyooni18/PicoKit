#if !PICOKIT_PICO_SDK
import PicoKitCore
#endif

public enum I2CInstance: UInt32, Sendable { case i2c0, i2c1 }

private extension I2CInstance {
    func validate(sda: PicoPin, scl: PicoPin) throws(PicoKitError) {
        let base = self == .i2c0 ? 0 : 2
        guard Int(sda.rawValue) % 4 == base else {
            throw PicoKitError.invalidPeripheralPin(peripheral: "\(self) SDA", pin: sda)
        }
        guard Int(scl.rawValue) % 4 == base + 1 else {
            throw PicoKitError.invalidPeripheralPin(peripheral: "\(self) SCL", pin: scl)
        }
    }
}

public final class PicoI2C {
    public let instance: I2CInstance

    public init(_ instance: I2CInstance, frequency: Frequency, sda: PicoPin, scl: PicoPin) throws(PicoKitError) {
        try instance.validate(sda: sda, scl: scl)
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
public enum SPIMode: UInt32, CaseIterable, Sendable { case mode0, mode1, mode2, mode3 }
public enum SPIBitOrder: UInt32, CaseIterable, Sendable { case mostSignificantBitFirst, leastSignificantBitFirst }
public enum SPIDataBits: UInt32, CaseIterable, Sendable { case eight = 8, sixteen = 16 }

private extension SPIInstance {
    func validate(sck: PicoPin, mosi: PicoPin, miso: PicoPin?) throws(PicoKitError) {
        let sckValue = Int(sck.rawValue)
        let validSCK = self == .spi0 ? [2, 6, 18, 22] : [10, 14, 26]
        guard validSCK.contains(sckValue) else {
            throw PicoKitError.invalidPeripheralPin(peripheral: "\(self) SCK", pin: sck)
        }
        try validateDataPins(mosi: mosi, miso: miso)
    }

    private func validateDataPins(mosi: PicoPin, miso: PicoPin?) throws(PicoKitError) {
        let validMOSI = self == .spi0 ? [3, 7, 19, 23] : [11, 15, 27]
        let validMISO = self == .spi0 ? [0, 4, 16, 20] : [8, 12, 24, 28]
        guard validMOSI.contains(Int(mosi.rawValue)) else {
            throw PicoKitError.invalidPeripheralPin(peripheral: "\(self) MOSI", pin: mosi)
        }
        if let miso, !validMISO.contains(Int(miso.rawValue)) {
            throw PicoKitError.invalidPeripheralPin(peripheral: "\(self) MISO", pin: miso)
        }
    }
}

public final class PicoSPI {
    public let instance: SPIInstance
    public let actualFrequency: Frequency
    public let dataBits: SPIDataBits
    public let chipSelect: PicoPin?
    private let gpio: PicoGPIO?

    public init(
        _ instance: SPIInstance,
        frequency: Frequency,
        sck: PicoPin,
        mosi: PicoPin,
        miso: PicoPin? = nil,
        mode: SPIMode = .mode0,
        bitOrder: SPIBitOrder = .mostSignificantBitFirst,
        dataBits: SPIDataBits = .eight,
        chipSelect: PicoPin? = nil,
        gpio: PicoGPIO? = nil
    ) throws(PicoKitError) {
        try instance.validate(sck: sck, mosi: mosi, miso: miso)
        #if PICOKIT_PICO_SDK
        var actual: UInt32 = 0
        let status = picokit_spi_init_config(
            instance.rawValue, frequency.hertz, sck.rawValue, mosi.rawValue,
            miso.map { Int32($0.rawValue) } ?? -1, mode.rawValue, bitOrder.rawValue,
            dataBits.rawValue, &actual
        )
        guard status == 0 else {
            throw PicoKitError.ioFailure(operation: "SPI setup", status: status)
        }
        self.instance = instance
        self.actualFrequency = try Frequency.hertz(actual)
        self.dataBits = dataBits
        self.chipSelect = chipSelect
        let selectedGPIO = gpio ?? (chipSelect == nil ? nil : PicoGPIO())
        self.gpio = selectedGPIO
        if let chipSelect, let selectedGPIO {
            try selectedGPIO.configure(chipSelect, mode: .output, initialState: .high)
        }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func select() throws(PicoKitError) {
        guard let chipSelect, let gpio else { throw PicoKitError.unavailable("SPI chip-select pin") }
        try gpio.write(chipSelect, state: .low)
    }

    public func deselect() throws(PicoKitError) {
        guard let chipSelect, let gpio else { throw PicoKitError.unavailable("SPI chip-select pin") }
        try gpio.write(chipSelect, state: .high)
    }

    public func write(_ bytes: [UInt8]) throws(PicoKitError) {
        guard dataBits == .eight else { throw PicoKitError.unavailable("8-bit SPI write while configured for 16-bit transfers") }
        #if PICOKIT_PICO_SDK
        let status = bytes.withUnsafeBufferPointer {
            picokit_spi_write(instance.rawValue, $0.baseAddress, UInt32($0.count))
        }
        guard status == Int32(bytes.count) else {
            throw PicoKitError.ioFailure(operation: "SPI write", status: status)
        }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func write(_ bytes: [UInt8], timeout: Duration) throws(PicoKitError) {
        guard dataBits == .eight else { throw PicoKitError.unavailable("8-bit SPI write while configured for 16-bit transfers") }
        #if PICOKIT_PICO_SDK
        let status = bytes.withUnsafeBufferPointer {
            picokit_spi_write_timeout(instance.rawValue, $0.baseAddress, UInt32($0.count), timeout.microseconds)
        }
        guard status >= 0 else { throw PicoKitError.ioFailure(operation: "SPI write", status: status) }
        guard status == Int32(bytes.count) else {
            throw PicoKitError.partialTransfer(operation: "SPI write", transferred: Int(status), expected: bytes.count)
        }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func write(_ words: [UInt16]) throws(PicoKitError) {
        guard dataBits == .sixteen else { throw PicoKitError.unavailable("16-bit SPI write while configured for 8-bit transfers") }
        #if PICOKIT_PICO_SDK
        let status = words.withUnsafeBufferPointer {
            picokit_spi_write16(instance.rawValue, $0.baseAddress, UInt32($0.count))
        }
        guard status == Int32(words.count) else {
            throw PicoKitError.ioFailure(operation: "SPI 16-bit write", status: status)
        }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func transfer(_ bytes: [UInt8], timeout: Duration) throws(PicoKitError) -> [UInt8] {
        guard dataBits == .eight else { throw PicoKitError.unavailable("8-bit SPI transfer while configured for 16-bit transfers") }
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
