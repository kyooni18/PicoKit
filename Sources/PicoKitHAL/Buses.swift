#if !PICOKIT_PICO_SDK
import PicoKitCore
#else
import PicoKitSDKBridge
#endif

public enum I2CInstance: UInt32, Sendable { case i2c0, i2c1 }

private extension I2CInstance {
    func validate(sda: PicoPin, scl: PicoPin) throws(PicoKitError) {
        guard sda != scl else {
            throw PicoKitError.ownershipConflict("\(self) SDA and SCL must use different pins")
        }
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
    /// The bus frequency actually selected by the SDK.
    public let actualFrequency: Frequency

    public init(_ instance: I2CInstance, frequency: Frequency, sda: PicoPin, scl: PicoPin) throws(PicoKitError) {
        try instance.validate(sda: sda, scl: scl)
        #if PICOKIT_PICO_SDK
        var actualFrequency: UInt32 = 0
        let status = picokit_i2c_init_with_actual_frequency(
            instance.rawValue, frequency.hertz, sda.rawValue, scl.rawValue, &actualFrequency
        )
        guard status == 0 else {
            throw PicoKitError.ioFailure(operation: "I2C setup", status: status)
        }
        self.instance = instance
        self.actualFrequency = try Frequency.hertz(actualFrequency)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Writes one transaction. Set `stop` to `false` when the next operation
    /// must begin with a repeated START, such as a register-address write
    /// followed immediately by `read`.
    public func write(
        address: UInt8,
        bytes: [UInt8],
        timeout: Duration,
        stop: Bool = true
    ) throws(PicoKitError) -> Int {
        guard (0x08...0x77).contains(address) else { throw PicoKitError.invalidAddress(address) }
        guard timeout.microseconds <= UInt64(UInt32.max) else {
            throw PicoKitError.invalidTimeout(timeout.microseconds)
        }
        let count = try picoKitTransferCount(bytes.count, operation: "I2C write")
        // The Pico SDK rejects zero-length I2C transactions with an assertion.
        // Treat an empty write as a validated no-op instead of entering that
        // SDK path; this is also consistent with the transfer APIs' count
        // semantics.
        guard count != 0 else { return 0 }
        #if PICOKIT_PICO_SDK
        let result = bytes.withUnsafeBufferPointer {
            picokit_i2c_write(
                instance.rawValue, UInt32(address), $0.baseAddress, count,
                timeout.microseconds, stop ? 0 : 1
            )
        }
        if result == -2 { throw PicoKitError.timedOut(operation: "I2C write") }
        guard result >= 0 else {
            throw PicoKitError.ioFailure(operation: "I2C write", status: result)
        }
        if result != Int32(count) {
            throw PicoKitError.partialTransfer(
                operation: "I2C write", transferred: Int(result), expected: Int(count)
            )
        }
        return Int(result)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Reads one transaction. Set `stop` to `false` when another operation
    /// must follow without releasing the I2C bus.
    public func read(
        address: UInt8,
        count: Int,
        timeout: Duration,
        stop: Bool = true
    ) throws(PicoKitError) -> [UInt8] {
        guard (0x08...0x77).contains(address) else { throw PicoKitError.invalidAddress(address) }
        guard count >= 0 else { throw PicoKitError.ioFailure(operation: "I2C read", status: -1) }
        guard timeout.microseconds <= UInt64(UInt32.max) else {
            throw PicoKitError.invalidTimeout(timeout.microseconds)
        }
        let transferCount = try picoKitTransferCount(count, operation: "I2C read")
        // The Pico SDK rejects zero-length I2C transactions with an
        // assertion. Return the requested empty result without touching the
        // peripheral.
        guard transferCount != 0 else { return [] }
        #if PICOKIT_PICO_SDK
        var result = [UInt8](repeating: 0, count: count)
        let status = result.withUnsafeMutableBufferPointer {
            picokit_i2c_read(
                instance.rawValue, UInt32(address), $0.baseAddress, transferCount,
                timeout.microseconds, stop ? 0 : 1
            )
        }
        if status == -2 { throw PicoKitError.timedOut(operation: "I2C read") }
        if status >= 0 && status != Int32(count) {
            throw PicoKitError.partialTransfer(
                operation: "I2C read", transferred: Int(status), expected: count
            )
        }
        guard status == Int32(count) else {
            throw PicoKitError.ioFailure(operation: "I2C read", status: status)
        }
        return result
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Writes a command or register prefix and immediately reads the response
    /// with a repeated START between the two transactions. The timeout applies
    /// independently to the write and read portions.
    public func writeRead(
        address: UInt8,
        bytes: [UInt8],
        count: Int,
        timeout: Duration
    ) throws(PicoKitError) -> [UInt8] {
        // Validate the complete composed transaction before issuing its
        // write portion; invalid read arguments must never cause a prefix
        // write as a side effect.
        guard (0x08...0x77).contains(address) else { throw PicoKitError.invalidAddress(address) }
        guard count >= 0 else { throw PicoKitError.ioFailure(operation: "I2C read", status: -1) }
        guard timeout.microseconds <= UInt64(UInt32.max) else {
            throw PicoKitError.invalidTimeout(timeout.microseconds)
        }
        _ = try picoKitTransferCount(count, operation: "I2C read")
        _ = try write(address: address, bytes: bytes, timeout: timeout, stop: false)
        return try read(address: address, count: count, timeout: timeout)
    }
}

public enum SPIInstance: UInt32, Sendable { case spi0, spi1 }
public enum SPIMode: UInt32, CaseIterable, Sendable { case mode0, mode1, mode2, mode3 }
public enum SPIBitOrder: UInt32, CaseIterable, Sendable { case mostSignificantBitFirst, leastSignificantBitFirst }
public enum SPIDataBits: UInt32, CaseIterable, Sendable { case eight = 8, sixteen = 16 }

private extension SPIInstance {
    func validate(sck: PicoPin, mosi: PicoPin, miso: PicoPin?) throws(PicoKitError) {
        guard sck != mosi, sck != miso, mosi != miso else {
            throw PicoKitError.ownershipConflict("\(self) SCK, MOSI, and MISO must use different pins")
        }
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
    public let miso: PicoPin?
    public let chipSelect: PicoPin?
    private let gpio: PicoGPIO?

    deinit {
        releaseDMAChannels()
    }

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
        if let chipSelect, chipSelect == sck || chipSelect == mosi || chipSelect == miso {
            throw PicoKitError.invalidPeripheralPin(peripheral: "\(instance) chip-select", pin: chipSelect)
        }
        #if PICOKIT_PICO_SDK
        let compiledChip = picokit_compiled_chip() == 0 ? PicoChip.rp2040 : .rp2350
        if chipSelect != nil, let gpio, gpio.chip != compiledChip {
            throw PicoKitError.unavailable("SPI chip-select GPIO does not match compiled Pico chip")
        }
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
        self.miso = miso
        self.chipSelect = chipSelect
        // An omitted chip-select GPIO must still match the compiled target.
        // PicoGPIO's public default remains RP2040 for host/API compatibility,
        // so firmware chooses the bridge-reported chip explicitly here.
        let selectedGPIO = gpio ?? (chipSelect == nil ? nil : PicoGPIO(chip: compiledChip))
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
        let count = try picoKitTransferCount(bytes.count, operation: "SPI write")
        #if PICOKIT_PICO_SDK
        let status = bytes.withUnsafeBufferPointer {
            picokit_spi_write(instance.rawValue, $0.baseAddress, count)
        }
        guard status == Int32(count) else {
            throw PicoKitError.ioFailure(operation: "SPI write", status: status)
        }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Reads 8-bit frames while transmitting `repeatedByte` on MOSI for each
    /// frame. The operation is blocking and requires a configured MISO pin.
    public func read(count: Int, repeatedByte: UInt8 = 0) throws(PicoKitError) -> [UInt8] {
        guard dataBits == .eight else { throw PicoKitError.unavailable("8-bit SPI read while configured for 16-bit transfers") }
        guard miso != nil else { throw PicoKitError.unavailable("SPI MISO pin") }
        let transferCount = try picoKitTransferCount(count, operation: "SPI read")
        #if PICOKIT_PICO_SDK
        var received = [UInt8](repeating: 0, count: count)
        let status = received.withUnsafeMutableBufferPointer {
            picokit_spi_read(instance.rawValue, repeatedByte, $0.baseAddress, transferCount)
        }
        guard status == Int32(count) else {
            throw PicoKitError.ioFailure(operation: "SPI read", status: status)
        }
        return received
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Reads 8-bit frames with a bounded wait for each frame. The timeout
    /// covers the complete operation and requires a configured MISO pin.
    public func read(
        count: Int,
        repeatedByte: UInt8 = 0,
        timeout: Duration
    ) throws(PicoKitError) -> [UInt8] {
        guard dataBits == .eight else { throw PicoKitError.unavailable("8-bit SPI read while configured for 16-bit transfers") }
        guard miso != nil else { throw PicoKitError.unavailable("SPI MISO pin") }
        let transferCount = try picoKitTransferCount(count, operation: "SPI read")
        #if PICOKIT_PICO_SDK
        var received = [UInt8](repeating: 0, count: count)
        let status = received.withUnsafeMutableBufferPointer {
            picokit_spi_read_timeout(instance.rawValue, repeatedByte, $0.baseAddress, transferCount, timeout.microseconds)
        }
        if status == -2 { throw PicoKitError.timedOut(operation: "SPI read") }
        guard status == Int32(count) else {
            throw PicoKitError.ioFailure(operation: "SPI read", status: status)
        }
        return received
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Reads 16-bit frames while transmitting `repeatedWord` on MOSI for each
    /// frame. The operation is blocking and requires 16-bit data mode and MISO.
    public func read(_ count: Int, repeatedWord: UInt16 = 0) throws(PicoKitError) -> [UInt16] {
        guard dataBits == .sixteen else { throw PicoKitError.unavailable("16-bit SPI read while configured for 8-bit transfers") }
        guard miso != nil else { throw PicoKitError.unavailable("SPI MISO pin") }
        let transferCount = try picoKitTransferCount(count, operation: "SPI 16-bit read")
        #if PICOKIT_PICO_SDK
        var received = [UInt16](repeating: 0, count: count)
        let status = received.withUnsafeMutableBufferPointer {
            picokit_spi_read16(instance.rawValue, repeatedWord, $0.baseAddress, transferCount)
        }
        guard status == Int32(count) else {
            throw PicoKitError.ioFailure(operation: "SPI 16-bit read", status: status)
        }
        return received
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Reads 16-bit frames with a bounded wait for each frame. The timeout
    /// covers the complete operation and requires 16-bit mode and MISO.
    public func read(
        _ count: Int,
        repeatedWord: UInt16 = 0,
        timeout: Duration
    ) throws(PicoKitError) -> [UInt16] {
        guard dataBits == .sixteen else { throw PicoKitError.unavailable("16-bit SPI read while configured for 8-bit transfers") }
        guard miso != nil else { throw PicoKitError.unavailable("SPI MISO pin") }
        let transferCount = try picoKitTransferCount(count, operation: "SPI 16-bit read")
        #if PICOKIT_PICO_SDK
        var received = [UInt16](repeating: 0, count: count)
        let status = received.withUnsafeMutableBufferPointer {
            picokit_spi_read16_timeout(instance.rawValue, repeatedWord, $0.baseAddress, transferCount, timeout.microseconds)
        }
        if status == -2 { throw PicoKitError.timedOut(operation: "SPI 16-bit read") }
        guard status == Int32(count) else {
            throw PicoKitError.ioFailure(operation: "SPI 16-bit read", status: status)
        }
        return received
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func write(_ bytes: [UInt8], timeout: Duration) throws(PicoKitError) {
        guard dataBits == .eight else { throw PicoKitError.unavailable("8-bit SPI write while configured for 16-bit transfers") }
        let count = try picoKitTransferCount(bytes.count, operation: "SPI write")
        #if PICOKIT_PICO_SDK
        let status = bytes.withUnsafeBufferPointer {
            picokit_spi_write_timeout(instance.rawValue, $0.baseAddress, count, timeout.microseconds)
        }
        guard status >= 0 else { throw PicoKitError.ioFailure(operation: "SPI write", status: status) }
        guard status == Int32(count) else {
            throw PicoKitError.partialTransfer(operation: "SPI write", transferred: Int(status), expected: Int(count))
        }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func write(_ words: [UInt16]) throws(PicoKitError) {
        guard dataBits == .sixteen else { throw PicoKitError.unavailable("16-bit SPI write while configured for 8-bit transfers") }
        let count = try picoKitTransferCount(words.count, operation: "SPI 16-bit write")
        #if PICOKIT_PICO_SDK
        let status = words.withUnsafeBufferPointer {
            picokit_spi_write16(instance.rawValue, $0.baseAddress, count)
        }
        guard status == Int32(count) else {
            throw PicoKitError.ioFailure(operation: "SPI 16-bit write", status: status)
        }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Writes a 16-bit buffer with a bounded wait for each frame. A stalled
    /// peripheral is reported as a partial transfer.
    public func write(_ words: [UInt16], timeout: Duration) throws(PicoKitError) {
        guard dataBits == .sixteen else { throw PicoKitError.unavailable("16-bit SPI write while configured for 8-bit transfers") }
        let count = try picoKitTransferCount(words.count, operation: "SPI 16-bit write")
        #if PICOKIT_PICO_SDK
        let status = words.withUnsafeBufferPointer {
            picokit_spi_write16_timeout(instance.rawValue, $0.baseAddress, count, timeout.microseconds)
        }
        guard status >= 0 else {
            throw PicoKitError.ioFailure(operation: "SPI 16-bit write", status: status)
        }
        guard status == Int32(count) else {
            throw PicoKitError.partialTransfer(
                operation: "SPI 16-bit write", transferred: Int(status), expected: Int(count)
            )
        }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Writes an 8-bit buffer through a DMA channel and waits for completion.
    /// Use this for large, prepared output buffers; small control transfers are
    /// usually better served by `write(_:)`.
    public func writeDMA(_ bytes: [UInt8]) throws(PicoKitError) {
        guard dataBits == .eight else { throw PicoKitError.unavailable("8-bit SPI DMA write while configured for 16-bit transfers") }
        let count = try picoKitTransferCount(bytes.count, operation: "SPI DMA write")
        #if PICOKIT_PICO_SDK
        let status = bytes.withUnsafeBufferPointer {
            picokit_spi_write_dma(instance.rawValue, $0.baseAddress, count)
        }
        guard status == Int32(count) else {
            throw PicoKitError.ioFailure(operation: "SPI DMA write", status: status)
        }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Writes an 8-bit buffer through DMA with a bounded wait. A timeout
    /// aborts both retained SPI DMA channels before returning.
    public func writeDMA(_ bytes: [UInt8], timeout: Duration) throws(PicoKitError) {
        guard dataBits == .eight else { throw PicoKitError.unavailable("8-bit SPI DMA write while configured for 16-bit transfers") }
        let count = try picoKitTransferCount(bytes.count, operation: "SPI DMA write")
        #if PICOKIT_PICO_SDK
        let status = bytes.withUnsafeBufferPointer {
            picokit_spi_write_dma_timeout(instance.rawValue, $0.baseAddress, count, timeout.microseconds)
        }
        if status == -2 { throw PicoKitError.timedOut(operation: "SPI DMA write") }
        guard status >= 0 else { throw PicoKitError.ioFailure(operation: "SPI DMA write", status: status) }
        guard status == Int32(count) else {
            throw PicoKitError.partialTransfer(operation: "SPI DMA write", transferred: Int(status), expected: Int(count))
        }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Performs a full-duplex 8-bit transfer through paired DMA channels and
    /// waits for both channels to finish.
    public func transferDMA(_ bytes: [UInt8]) throws(PicoKitError) -> [UInt8] {
        guard dataBits == .eight else { throw PicoKitError.unavailable("8-bit SPI DMA transfer while configured for 16-bit transfers") }
        guard miso != nil else { throw PicoKitError.unavailable("SPI MISO pin") }
        let count = try picoKitTransferCount(bytes.count, operation: "SPI 8-bit DMA transfer")
        #if PICOKIT_PICO_SDK
        var received = [UInt8](repeating: 0, count: bytes.count)
        let status = bytes.withUnsafeBufferPointer { tx in
            received.withUnsafeMutableBufferPointer { rx in
                picokit_spi_transfer_dma(instance.rawValue, tx.baseAddress, rx.baseAddress, count)
            }
        }
        guard status == Int32(count) else {
            throw PicoKitError.ioFailure(operation: "SPI 8-bit DMA transfer", status: status)
        }
        return received
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Performs a bounded full-duplex 8-bit DMA transfer and aborts both
    /// channels before reporting a timeout.
    public func transferDMA(_ bytes: [UInt8], timeout: Duration) throws(PicoKitError) -> [UInt8] {
        guard dataBits == .eight else { throw PicoKitError.unavailable("8-bit SPI DMA transfer while configured for 16-bit transfers") }
        guard miso != nil else { throw PicoKitError.unavailable("SPI MISO pin") }
        let count = try picoKitTransferCount(bytes.count, operation: "SPI 8-bit DMA transfer")
        #if PICOKIT_PICO_SDK
        var received = [UInt8](repeating: 0, count: bytes.count)
        let status = bytes.withUnsafeBufferPointer { tx in
            received.withUnsafeMutableBufferPointer { rx in
                picokit_spi_transfer_dma_timeout(instance.rawValue, tx.baseAddress, rx.baseAddress, count, timeout.microseconds)
            }
        }
        if status == -2 { throw PicoKitError.timedOut(operation: "SPI 8-bit DMA transfer") }
        guard status >= 0 else { throw PicoKitError.ioFailure(operation: "SPI 8-bit DMA transfer", status: status) }
        guard status == Int32(count) else {
            throw PicoKitError.partialTransfer(operation: "SPI 8-bit DMA transfer", transferred: Int(status), expected: Int(count))
        }
        return received
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Writes a 16-bit buffer through a DMA channel and waits for completion.
    public func writeDMA(_ words: [UInt16]) throws(PicoKitError) {
        guard dataBits == .sixteen else { throw PicoKitError.unavailable("16-bit SPI DMA write while configured for 8-bit transfers") }
        let count = try picoKitTransferCount(words.count, operation: "SPI 16-bit DMA write")
        #if PICOKIT_PICO_SDK
        let status = words.withUnsafeBufferPointer {
            picokit_spi_write16_dma(instance.rawValue, $0.baseAddress, count)
        }
        guard status == Int32(count) else {
            throw PicoKitError.ioFailure(operation: "SPI DMA write", status: status)
        }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Writes a 16-bit buffer through DMA with a bounded wait.
    public func writeDMA(_ words: [UInt16], timeout: Duration) throws(PicoKitError) {
        guard dataBits == .sixteen else { throw PicoKitError.unavailable("16-bit SPI DMA write while configured for 8-bit transfers") }
        let count = try picoKitTransferCount(words.count, operation: "SPI 16-bit DMA write")
        #if PICOKIT_PICO_SDK
        let status = words.withUnsafeBufferPointer {
            picokit_spi_write16_dma_timeout(instance.rawValue, $0.baseAddress, count, timeout.microseconds)
        }
        if status == -2 { throw PicoKitError.timedOut(operation: "SPI 16-bit DMA write") }
        guard status >= 0 else { throw PicoKitError.ioFailure(operation: "SPI 16-bit DMA write", status: status) }
        guard status == Int32(count) else {
            throw PicoKitError.partialTransfer(operation: "SPI 16-bit DMA write", transferred: Int(status), expected: Int(count))
        }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Performs a full-duplex 16-bit transfer through paired DMA channels and
    /// waits for both channels to finish.
    public func transferDMA(_ words: [UInt16]) throws(PicoKitError) -> [UInt16] {
        guard dataBits == .sixteen else { throw PicoKitError.unavailable("16-bit SPI DMA transfer while configured for 8-bit transfers") }
        guard miso != nil else { throw PicoKitError.unavailable("SPI MISO pin") }
        let count = try picoKitTransferCount(words.count, operation: "SPI 16-bit DMA transfer")
        #if PICOKIT_PICO_SDK
        var received = [UInt16](repeating: 0, count: words.count)
        let status = words.withUnsafeBufferPointer { tx in
            received.withUnsafeMutableBufferPointer { rx in
                picokit_spi_transfer16_dma(instance.rawValue, tx.baseAddress, rx.baseAddress, count)
            }
        }
        guard status == Int32(count) else {
            throw PicoKitError.ioFailure(operation: "SPI 16-bit DMA transfer", status: status)
        }
        return received
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Performs a bounded full-duplex 16-bit DMA transfer.
    public func transferDMA(_ words: [UInt16], timeout: Duration) throws(PicoKitError) -> [UInt16] {
        guard dataBits == .sixteen else { throw PicoKitError.unavailable("16-bit SPI DMA transfer while configured for 8-bit transfers") }
        guard miso != nil else { throw PicoKitError.unavailable("SPI MISO pin") }
        let count = try picoKitTransferCount(words.count, operation: "SPI 16-bit DMA transfer")
        #if PICOKIT_PICO_SDK
        var received = [UInt16](repeating: 0, count: words.count)
        let status = words.withUnsafeBufferPointer { tx in
            received.withUnsafeMutableBufferPointer { rx in
                picokit_spi_transfer16_dma_timeout(instance.rawValue, tx.baseAddress, rx.baseAddress, count, timeout.microseconds)
            }
        }
        if status == -2 { throw PicoKitError.timedOut(operation: "SPI 16-bit DMA transfer") }
        guard status >= 0 else { throw PicoKitError.ioFailure(operation: "SPI 16-bit DMA transfer", status: status) }
        guard status == Int32(count) else {
            throw PicoKitError.partialTransfer(operation: "SPI 16-bit DMA transfer", transferred: Int(status), expected: Int(count))
        }
        return received
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Releases the two DMA channels retained by SPI DMA operations. PicoKit
    /// reuses them between calls to avoid repeated claim and cleanup work.
    public func releaseDMAChannels() {
        #if PICOKIT_PICO_SDK
        picokit_spi_dma_release(instance.rawValue)
        #endif
    }

    public func transfer(_ bytes: [UInt8], timeout: Duration) throws(PicoKitError) -> [UInt8] {
        guard dataBits == .eight else { throw PicoKitError.unavailable("8-bit SPI transfer while configured for 16-bit transfers") }
        guard miso != nil else { throw PicoKitError.unavailable("SPI MISO pin") }
        let count = try picoKitTransferCount(bytes.count, operation: "SPI transfer")
        #if PICOKIT_PICO_SDK
        var received = [UInt8](repeating: 0, count: bytes.count)
        let status = bytes.withUnsafeBufferPointer { tx in
            received.withUnsafeMutableBufferPointer { rx in
                picokit_spi_transfer(instance.rawValue, tx.baseAddress, rx.baseAddress, count, timeout.microseconds)
            }
        }
        if status == -2 { throw PicoKitError.timedOut(operation: "SPI transfer") }
        guard status == Int32(count) else {
            throw PicoKitError.ioFailure(operation: "SPI transfer", status: status)
        }
        return received
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Performs a full-duplex transfer of 16-bit frames.
    public func transfer(_ words: [UInt16], timeout: Duration) throws(PicoKitError) -> [UInt16] {
        guard dataBits == .sixteen else {
            throw PicoKitError.unavailable("16-bit SPI transfer while configured for 8-bit transfers")
        }
        guard miso != nil else { throw PicoKitError.unavailable("SPI MISO pin") }
        let count = try picoKitTransferCount(words.count, operation: "SPI 16-bit transfer")
        #if PICOKIT_PICO_SDK
        var received = [UInt16](repeating: 0, count: words.count)
        let status = words.withUnsafeBufferPointer { tx in
            received.withUnsafeMutableBufferPointer { rx in
                picokit_spi_transfer16(
                    instance.rawValue, tx.baseAddress, rx.baseAddress, count, timeout.microseconds
                )
            }
        }
        if status == -2 { throw PicoKitError.timedOut(operation: "SPI 16-bit transfer") }
        guard status == Int32(count) else {
            throw PicoKitError.ioFailure(operation: "SPI 16-bit transfer", status: status)
        }
        return received
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
}
