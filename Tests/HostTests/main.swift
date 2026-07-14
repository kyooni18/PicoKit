import PicoKit
@testable import PicoKitHAL

private final class FakeGPIO: DigitalIO {
    var modes: [(PicoPin, PinMode)] = []
    var writes: [(PicoPin, PinState)] = []
    var state: PinState = .low
    func setMode(_ pin: PicoPin, mode: PinMode) throws(PicoKitError) { modes.append((pin, mode)) }
    func write(_ pin: PicoPin, state: PinState) throws(PicoKitError) { writes.append((pin, state)); self.state = state }
    func read(_ pin: PicoPin) throws(PicoKitError) -> PinState { state }
}

private final class FakeSerialBackend: PicoSerialBackend {
    var reads: [UInt8?] = []
    var textWrites: [String] = []
    var byteWrites: [[UInt8]] = []
    var readCount = 0

    func write(_ text: String) throws(PicoKitError) { textWrites.append(text) }
    func write(_ bytes: [UInt8]) throws(PicoKitError) { byteWrites.append(bytes) }
    func read() throws(PicoKitError) -> UInt8? {
        readCount += 1
        return reads.isEmpty ? nil : reads.removeFirst()
    }
}

private func require(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
    guard try condition() else { fatalError(message) }
}

private func requireError(
    _ expected: PicoKitError,
    _ message: String,
    operation: () throws -> Void
) {
    do {
        try operation()
        fatalError(message)
    } catch let error as PicoKitError {
        guard error == expected else { fatalError("\(message): \(error)") }
    } catch {
        fatalError("\(message): \(error)")
    }
}

@main
struct PicoKitHostTests {
    static func main() {
        do {
            try testCoreValues()
            try testGPIOFacade()
            testSerialFacade()
            testCompileSurface()
            print("PicoKit host validation passed")
        } catch {
            fatalError("PicoKit host validation failed: \(error)")
        }
    }

    private static func testCoreValues() throws {
        let aliases: [(String, PicoBoard)] = [
            ("pico", .pico), ("pico_w", .picoW), ("pico-w", .picoW),
            ("pico2", .pico2), ("pico2_w", .pico2W), ("pico2-w", .pico2W),
        ]
        for (name, expected) in aliases {
            require(PicoBoard(configurationName: name) == expected, "board alias failed: \(name)")
        }
        require(PicoBoard(configurationName: "unknown") == nil, "unknown board accepted")
        require(PicoBoard.pico.chip == .rp2040, "Pico chip mismatch")
        require(PicoBoard.pico2W.chip == .rp2350, "Pico 2 W chip mismatch")
        require(PicoBoard.pico2W.cmakeName == "pico2_w", "CMake board spelling mismatch")
        require(PicoBoard.pico.onboardLED == 25, "Pico LED mismatch")
        require(PicoBoard.picoW.onboardLED == nil, "Pico W should use BoardLED")
        require(PicoPin.gpio18.rawValue == 18, "GPIO convenience value mismatch")

        for value in 0...29 {
            let pin = try PicoPin(value)
            require(pin.rawValue == UInt32(value), "pin validation failed: \(value)")
            require(pin.description == "GPIO\(value)", "pin description failed: \(value)")
        }
        requireError(.invalidPin(-1), "negative GPIO accepted") { _ = try PicoPin(-1) }
        requireError(.invalidPin(30), "GPIO30 accepted") { _ = try PicoPin(30) }

        let busFrequency = try Frequency.megahertz(1)
        requireError(
            .invalidPeripheralPin(peripheral: "spi0 SCK", pin: .gpio10),
            "SPI0 accepted an SPI1 clock pin"
        ) {
            _ = try PicoSPI(.spi0, frequency: busFrequency, sck: .gpio10, mosi: .gpio11)
        }
        requireError(
            .invalidPeripheralPin(peripheral: "i2c0 SDA", pin: .gpio2),
            "I2C0 accepted an I2C1 data pin"
        ) {
            _ = try PicoI2C(.i2c0, frequency: busFrequency, sda: .gpio2, scl: .gpio3)
        }

        try require(try Frequency.kilohertz(400).hertz == 400_000, "frequency conversion failed")
        try require(try Frequency.megahertz(1).hertz == 1_000_000, "MHz conversion failed")
        requireError(.invalidFrequency(0), "zero frequency accepted") { _ = try Frequency.hertz(0) }
        requireError(.invalidFrequency(UInt32.max), "frequency overflow accepted") {
            _ = try Frequency.kilohertz(UInt32.max)
        }

        try require(try Duration.milliseconds(10).microseconds == 10_000, "duration conversion failed")
        try require(try Duration.seconds(2).microseconds == 2_000_000, "seconds conversion failed")
        requireError(.invalidTimeout(0), "zero timeout accepted") { _ = try Duration.microseconds(0) }
        requireError(.invalidTimeout(UInt64.max), "duration overflow accepted") {
            _ = try Duration.seconds(UInt64.max)
        }

        require(PinState.low.toggled == .high, "low toggle failed")
        require(PinState.high.toggled == .low, "high toggle failed")
        require(PicoKitError.timedOut(operation: "read").description == "read timed out", "error description failed")
        require(
            PicoKitError.partialTransfer(operation: "SPI write", transferred: 2, expected: 4).description ==
                "SPI write transferred 2 of 4 elements",
            "partial transfer description failed"
        )
    }

    private static func testGPIOFacade() throws {
        let fake = FakeGPIO()
        try pinMode(4, .output, using: fake)
        try digitalWrite(4, .high, using: fake)
        require(fake.modes.count == 1, "pinMode was not forwarded")
        require(fake.writes.count == 1, "digitalWrite was not forwarded")
        try require(try digitalRead(4, using: fake) == .high, "digitalRead was not forwarded")
        requireError(.invalidPin(30), "pinMode accepted invalid pin") {
            try pinMode(30, .output, using: fake)
        }

        let serialBackend = FakeSerialBackend()
        let sketch = Pico(gpio: fake, serial: PicoSerial(backend: serialBackend))
        sketch.pinMode(7, .output)
        sketch.digitalWrite(7, .high)
        require(sketch.digitalRead(7) == .high, "non-throwing Pico facade failed")
        sketch.digitalToggle(7)
        require(sketch.digitalRead(7) == .low, "digitalToggle did not flip injected GPIO state")
    }

    private static func testSerialFacade() {
        let backend = FakeSerialBackend()
        backend.reads = [0, 0xFF, nil]
        let serial = PicoSerial(backend: backend)

        require(serial.available, "available did not detect a byte")
        require(serial.available, "available consumed its buffered byte")
        require(backend.readCount == 1, "available performed more than one backend read")
        require(serial.read() == 0, "buffered NUL byte was not preserved")
        require(serial.read() == 0xFF, "direct byte order was not preserved")
        require(serial.read() == nil, "empty serial input did not return nil")

        serial.write([0, 0x7F, 0xFF])
        serial.print("hello")
        serial.println("world")
        serial.println()
        require(backend.byteWrites == [[0, 0x7F, 0xFF]], "raw serial write changed bytes")
        require(backend.textWrites == ["hello", "world", "\n", "", "\n"], "text serial writes changed")
    }

    private static func testCompileSurface() {
            let _: (Int, PinMode) -> Void = pinMode
            let _: (Int, PinState) -> Void = digitalWrite
            let _: (Int) -> Void = digitalToggle
            let _: (UInt64) -> Void = sleep
            let _: PicoSerial = Serial
            let _: () -> UInt8? = Serial.read
            let _: (PicoSerial) -> Bool = { $0.available }
            let _: (USBSerial, Duration) throws -> UInt8 = { try $0.read(timeout: $1) }
            let _: (USBSerial, [UInt8]) throws -> Void = { try $0.write($1) }
            let _: SPIMode = .mode3
            let _: SPIBitOrder = .leastSignificantBitFirst
            let _: SPIDataBits = .sixteen
            let _: (PicoGPIO, UInt32) throws -> Void = { try $0.set(mask: $1) }
            let _: (PicoGPIO, UInt32) throws -> Void = { try $0.clear(mask: $1) }
            let _: (PicoGPIO, UInt32) throws -> Void = { try $0.toggle(mask: $1) }
            let _: (PicoSPI, [UInt8]) throws -> Void = { try $0.writeDMA($1) }
            let _: (PicoSPI, [UInt16]) throws -> Void = { try $0.writeDMA($1) }
            let _: (PicoUART, [UInt8]) throws -> Void = { try $0.writeDMA($1) }
            let _: (PicoPWM, UInt16) throws -> Void = { try $0.setCounterLevel($1) }
            let _: PinPull = .up
            let _: PinDriveStrength = .milliamps12
            let _: PinSlewRate = .fast
    }
}
