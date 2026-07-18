import PicoKit

@testable import PicoKitHAL

private final class FakeGPIO: DigitalIO {
  var modes: [(PicoPin, PinMode)] = []
  var writes: [(PicoPin, PinState)] = []
  var state: PinState = .low
  func setMode(_ pin: PicoPin, mode: PinMode) throws(PicoKitError) { modes.append((pin, mode)) }
  func write(_ pin: PicoPin, state: PinState) throws(PicoKitError) {
    writes.append((pin, state))
    self.state = state
  }
  func read(_ pin: PicoPin) throws(PicoKitError) -> PinState { state }
}

private final class FakeSerialBackend: PicoSerialBackend {
  var isConnected = false
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
      ("PICO", .pico), ("Pico-W", .picoW),
      ("PICO2", .pico2), ("pIcO2_W", .pico2W),
      ("  pico_w\n", .picoW), ("\tpico2\t", .pico2),
    ]
    for (name, expected) in aliases {
      require(PicoBoard(configurationName: name) == expected, "board alias failed: \(name)")
    }
    require(PicoBoard(configurationName: "unknown") == nil, "unknown board accepted")
    require(PicoBoard(configurationName: " \t\n ") == nil, "whitespace-only board accepted")
    require(PicoBoard.pico.chip == .rp2040, "Pico chip mismatch")
    require(PicoBoard.pico2W.chip == .rp2350, "Pico 2 W chip mismatch")
    require(PicoBoard.pico2W.cmakeName == "pico2_w", "CMake board spelling mismatch")
    require(PicoBoard.pico.onboardLED == 25, "Pico LED mismatch")
    require(PicoBoard.picoW.onboardLED == nil, "Pico W should use BoardLED")
    require(PicoBoard.pico2.onboardLED == 25, "Pico 2 LED mismatch")
    require(PicoBoard.pico2W.onboardLED == nil, "Pico 2 W should use BoardLED")
    require(
      PicoBoard.allCases.map(\.cmakeName) == ["pico", "pico_w", "pico2", "pico2_w"],
      "board CaseIterable/CMake mapping drifted"
    )
    require(!PicoBoard.pico.isWireless, "Pico should not report wireless hardware")
    require(PicoBoard.picoW.isWireless, "Pico W wireless metadata missing")
    require(!PicoBoard.pico2.isWireless, "Pico 2 should not report wireless hardware")
    require(PicoBoard.pico2W.isWireless, "Pico 2 W wireless metadata missing")
    require(PicoChip.compiled == .rp2040, "host compiled chip default mismatch")
    require(PicoBoard.compiled == .pico, "host compiled board default mismatch")
    require(PicoGPIO.compiled.chip == .rp2040, "host compiled GPIO default mismatch")
    require(PicoGPIO().chip == .rp2040, "default GPIO chip mismatch")
    requireError(.unavailable("Pico SDK bridge"), "host BoardLED unexpectedly touched hardware") {
      _ = try BoardLED(board: .pico)
    }
    require(PicoPin.gpio18.rawValue == 18, "GPIO convenience value mismatch")

    for value in 0...29 {
      let pin = try PicoPin(value)
      require(pin.rawValue == UInt32(value), "pin validation failed: \(value)")
      require(pin.description == "GPIO\(value)", "pin description failed: \(value)")
    }
    requireError(.invalidPin(-1), "negative GPIO accepted") { _ = try PicoPin(-1) }
    requireError(.invalidPin(30), "GPIO30 accepted") { _ = try PicoPin(30) }
    require(PicoPin.gpio0 < PicoPin.gpio29, "GPIO pin ordering failed")
    require(PicoPin(rawValue: 29)?.rawValue == 29, "raw GPIO29 value rejected")
    require(PicoPin(rawValue: 30) == nil, "raw GPIO30 value accepted")

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
    requireError(
      .ownershipConflict("i2c0 SDA and SCL must use different pins"),
      "I2C accepted one pin for both roles"
    ) {
      _ = try PicoI2C(.i2c0, frequency: busFrequency, sda: .gpio0, scl: .gpio0)
    }
    requireError(
      .ioFailure(operation: "I2C writeRead", status: -1),
      "empty composed I2C read issued a prefix write"
    ) {
      _ = try PicoI2C(
        .i2c0, frequency: busFrequency, sda: .gpio0, scl: .gpio1
      ).writeRead(address: 0x48, bytes: [0], count: 0, timeout: .milliseconds(1))
    }
    requireError(
      .invalidPeripheralPin(peripheral: "uart0 TX on rp2040", pin: .gpio2),
      "RP2040 UART0 accepted an invalid TX pin"
    ) {
      _ = try PicoUART(.uart0, baudRate: busFrequency, tx: .gpio2, rx: .gpio1)
    }
    requireError(
      .invalidPeripheralPin(peripheral: "uart0 RX on rp2350", pin: .gpio5),
      "RP2350 UART0 accepted a UART1 RX pin"
    ) {
      _ = try PicoUART(.uart0, baudRate: busFrequency, tx: .gpio0, rx: .gpio5, chip: .rp2350)
    }
    requireError(
      .invalidPeripheralPin(peripheral: "uart0 TX on rp2350", pin: .gpio6),
      "RP2350 UART0 accepted a UART1 CTS pin as TX"
    ) {
      _ = try PicoUART(.uart0, baudRate: busFrequency, tx: .gpio6, rx: .gpio1, chip: .rp2350)
    }
    requireError(
      .invalidPeripheralPin(peripheral: "uart1 TX on rp2350", pin: .gpio2),
      "RP2350 UART1 accepted a UART0 CTS pin as TX"
    ) {
      _ = try PicoUART(.uart1, baudRate: busFrequency, tx: .gpio2, rx: .gpio5, chip: .rp2350)
    }
    do {
      _ = try PicoUART(.uart0, baudRate: busFrequency, tx: .gpio2, rx: .gpio3, chip: .rp2350)
      fatalError("RP2350 UART0 auxiliary TX/RX pair unexpectedly constructed on host")
    } catch let error {
      require(error == .unavailable("Pico SDK bridge"), "RP2350 UART0 auxiliary pair was rejected")
    }
    do {
      _ = try PicoUART(.uart1, baudRate: busFrequency, tx: .gpio6, rx: .gpio7, chip: .rp2350)
      fatalError("RP2350 UART1 auxiliary TX/RX pair unexpectedly constructed on host")
    } catch let error {
      require(error == .unavailable("Pico SDK bridge"), "RP2350 UART1 auxiliary pair was rejected")
    }
    requireError(
      .invalidPeripheralPin(peripheral: "spi0 chip-select", pin: .gpio2),
      "SPI chip-select conflicted with SCK"
    ) {
      _ = try PicoSPI(.spi0, frequency: busFrequency, sck: .gpio2, mosi: .gpio3, chipSelect: .gpio2)
    }
    requireError(
      .ownershipConflict("spi0 SCK, MOSI, and MISO must use different pins"),
      "SPI accepted one pin for multiple data roles"
    ) {
      _ = try PicoSPI(.spi0, frequency: busFrequency, sck: .gpio2, mosi: .gpio2, miso: .gpio0)
    }
    requireError(
      .unavailable("LSB-first SPI"),
      "LSB-first SPI reached the hardware bridge"
    ) {
      _ = try PicoSPI(
        .spi0, frequency: busFrequency, sck: .gpio2, mosi: .gpio3,
        bitOrder: .leastSignificantBitFirst)
    }
    requireError(
      .ownershipConflict("uart0 TX and RX must use different pins"),
      "UART accepted one pin for both roles"
    ) {
      _ = try PicoUART(.uart0, baudRate: busFrequency, tx: .gpio0, rx: .gpio0)
    }

    try require(try Frequency.kilohertz(400).hertz == 400_000, "frequency conversion failed")
    try require(try Frequency.megahertz(1).hertz == 1_000_000, "MHz conversion failed")
    requireError(.invalidFrequency(0), "zero frequency accepted") { _ = try Frequency.hertz(0) }
    requireError(.invalidFrequency(UInt32.max), "frequency overflow accepted") {
      _ = try Frequency.kilohertz(UInt32.max)
    }
    requireError(.invalidFrequency(UInt32.max), "MHz frequency overflow accepted") {
      _ = try Frequency.megahertz(UInt32.max)
    }

    try require(try Duration.milliseconds(10).microseconds == 10_000, "duration conversion failed")
    try require(try Duration.seconds(2).microseconds == 2_000_000, "seconds conversion failed")
    requireError(.invalidTimeout(0), "zero timeout accepted") { _ = try Duration.microseconds(0) }
    requireError(.invalidTimeout(UInt64.max), "millisecond timeout overflow accepted") {
      _ = try Duration.milliseconds(UInt64.max)
    }
    requireError(.invalidTimeout(UInt64.max), "duration overflow accepted") {
      _ = try Duration.seconds(UInt64.max)
    }
    try require(
      try picoKitWatchdogMilliseconds(.microseconds(1)) == 1,
      "sub-millisecond watchdog timeout was rounded down to zero"
    )
    try require(
      try picoKitWatchdogMilliseconds(.milliseconds(UInt64(UInt32.max))) == UInt32.max,
      "maximum UInt32 watchdog duration conversion failed"
    )
    requireError(
      .invalidTimeout(UInt64(UInt32.max) * 1_000 + 1), "watchdog timeout overflow accepted"
    ) {
      _ = try picoKitWatchdogMilliseconds(.microseconds(UInt64(UInt32.max) * 1_000 + 1))
    }
    try require(try picoKitADCChannel(for: 26) == .gpio26, "ADC GPIO mapping failed")
    try require(try picoKitADCChannel(for: 27) == .gpio27, "ADC GPIO27 mapping failed")
    try require(try picoKitADCChannel(for: 28) == .gpio28, "ADC GPIO28 mapping failed")
    try require(try picoKitADCChannel(for: 29) == .gpio29, "ADC GPIO29 mapping failed")
    requireError(.invalidPin(-1), "negative ADC GPIO accepted") {
      _ = try picoKitADCChannel(for: -1)
    }
    requireError(.unavailable("ADC is only available on GPIO26...GPIO29"), "non-ADC GPIO accepted") {
      _ = try picoKitADCChannel(for: 25)
    }
    require(ADCChannel.allCases == [.gpio26, .gpio27, .gpio28, .gpio29, .temperature], "ADC channel order drifted")
    require(GPIOInterruptEdge.rising.rawValue == 1, "rising interrupt edge value drifted")
    require(GPIOInterruptEdge.falling.rawValue == 2, "falling interrupt edge value drifted")
    require(GPIOInterruptEdge.either.rawValue == 3, "either interrupt edge value drifted")
    let interrupts = PicoInterrupts()
    requireError(.unavailable("Pico SDK bridge"), "host interrupt enable unexpectedly touched hardware") {
      try interrupts.enable(.gpio0, edge: .either)
    }
    require(interrupts.takeEvents(for: .gpio0) == 0, "host interrupt events were not empty")
    requireError(.unavailable("Pico SDK bridge"), "host ADC initialization unexpectedly touched hardware") {
      _ = try PicoADC()
    }
    requireError(.unavailable("Pico SDK bridge"), "host PWM initialization unexpectedly touched hardware") {
      _ = try PicoPWM(pin: .gpio0, frequency: busFrequency)
    }
    requireError(.invalidPin(30), "ADC GPIO30 accepted") {
      _ = try picoKitADCChannel(for: 30)
    }
    requireError(.unavailable("ADC is only available on GPIO26...GPIO29"), "non-ADC GPIO accepted")
    {
      _ = try picoKitADCChannel(for: 25)
    }
    requireError(
      .ioFailure(operation: "large transfer", status: -1), "oversized transfer count accepted"
    ) {
      _ = try picoKitTransferCount(Int(Int32.max) + 1, operation: "large transfer")
    }
    require(
      picoKitSerialWriteError(status: 0, operation: "USB serial write") == nil,
      "successful USB serial write mapped to an error"
    )
    require(
      picoKitSerialWriteError(status: -2, operation: "USB serial write")
        == .unavailable("USB serial host is not connected"),
      "disconnected USB serial write lost its explicit error"
    )
    require(
      picoKitSerialWriteError(status: -9, operation: "USB serial write")
        == .ioFailure(operation: "USB serial write", status: -9),
      "unknown USB serial write status was not preserved"
    )
    require(picoKitSerialNoDataStatus() == -3, "USB serial no-data status drifted")
    require(
      picoKitSerialReadError(status: 0, operation: "USB serial read") == nil,
      "successful USB serial read mapped to an error"
    )
    require(
      picoKitSerialReadError(status: -3, operation: "USB serial read") == nil,
      "USB serial no-data status mapped to an I/O error"
    )
    require(
      picoKitSerialReadError(status: -2, operation: "USB serial read")
        == .unavailable("USB serial host is not connected"),
      "disconnected USB serial read lost its explicit error"
    )
    require(
      picoKitSerialReadError(status: -9, operation: "USB serial read")
        == .ioFailure(operation: "USB serial read", status: -9),
      "unknown USB serial read status was not preserved"
    )

    require(PinState.low.toggled == .high, "low toggle failed")
    require(PinState.high.toggled == .low, "high toggle failed")
    require(
      PicoKitError.timedOut(operation: "read").description == "read timed out",
      "error description failed")
    require(
      PicoKitError.invalidPin(30).description == "GPIO pin 30 is outside 0...29",
      "invalid pin description failed"
    )
    require(
      PicoKitError.invalidAddress(0x01).description == "I2C address 0x1 is outside 0x08...0x77",
      "invalid I2C address description failed"
    )
    require(
      PicoKitError.unavailable("test feature").description == "test feature is unavailable for this board or build",
      "unavailable feature description failed"
    )
    require(
      PicoKitError.invalidPeripheralPin(peripheral: "spi0 SCK", pin: .gpio10).description
        == "GPIO10 cannot be used as spi0 SCK",
      "invalid peripheral pin description failed"
    )
    require(
      PicoKitError.ioFailure(operation: "GPIO read", status: -7).description
        == "GPIO read failed with SDK status -7",
      "I/O failure description failed"
    )
    require(
      PicoKitError.invalidFrequency(UInt32.max).description
        == "frequency \(UInt32.max) Hz is zero, overflows, or is unsupported",
      "invalid frequency description lost overflow semantics"
    )
    require(
      PicoKitError.invalidTimeout(UInt64.max).description
        == "timeout \(UInt64.max) us is zero, overflows, or is unsupported",
      "invalid timeout description lost overflow semantics"
    )
    require(
      PicoKitError.partialTransfer(operation: "SPI write", transferred: 2, expected: 4).description
        == "SPI write transferred 2 of 4 elements",
      "partial transfer description failed"
    )
    require(
      PicoKitError.ownershipConflict("i2c0 SDA and SCL must use different pins").description
        == "i2c0 SDA and SCL must use different pins",
      "ownership conflict description added an unrelated ownership suffix"
    )
  }

  private static func testGPIOFacade() throws {
    require(picoKitGPIOError(status: 0, operation: "GPIO write") == nil, "GPIO success mapped to error")
    require(
      picoKitGPIOError(status: -2, operation: "GPIO write")
        == .unavailable("GPIO chip does not match compiled Pico chip"),
      "GPIO chip mismatch status mapping failed"
    )
    require(
      picoKitGPIOError(status: -1, operation: "GPIO setup")
        == .ioFailure(operation: "GPIO setup", status: -1),
      "GPIO invalid argument status mapping failed"
    )
    require(
      picoKitGPIOError(status: -9, operation: "GPIO read")
        == .ioFailure(operation: "GPIO read", status: -9),
      "GPIO unknown failure status mapping failed"
    )

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
    require(!PicoSerial().connected, "host serial connection probe should be false")
    require(!PicoSerial(backend: backend).connected, "fake serial connection default mismatch")
    backend.isConnected = true
    require(PicoSerial(backend: backend).connected, "fake serial connection probe mismatch")
    backend.reads = [0, 0xFF, nil]
    let serial = PicoSerial(backend: backend)

    require(serial.available, "available did not detect a byte")
    require(serial.available, "available consumed its buffered byte")
    require(backend.readCount == 1, "available performed more than one backend read")
    require(serial.read() == 0, "buffered NUL byte was not preserved")
    require(serial.read() == 0xFF, "direct byte order was not preserved")
    require(serial.read() == nil, "empty serial input did not return nil")

    serial.write([0, 0x7F, 0xFF])
    serial.write(0x42)
    serial.print("hello")
    serial.println("world")
    serial.println()
    require(backend.byteWrites == [[0, 0x7F, 0xFF], [0x42]], "raw serial write changed bytes")
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
    let _: (USBSerial, UInt8) throws -> Void = { try $0.write($1) }
    let _: (USBSerial) -> Bool = { $0.isConnected }
    let _: (PicoSerial) -> Bool = { $0.connected }
    let _: (PicoUART) throws -> UInt8? = { try $0.read() }
    let _: (PicoI2C, UInt8, [UInt8], Int, Duration) throws -> [UInt8] = {
      try $0.writeRead(address: $1, bytes: $2, count: $3, timeout: $4)
    }
    let _: SPIMode = .mode3
    let _: SPIBitOrder = .leastSignificantBitFirst
    let _: SPIDataBits = .sixteen
    let _: (PicoI2C, UInt8, [UInt8], Duration, Bool) throws -> Int = {
      try $0.write(address: $1, bytes: $2, timeout: $3, stop: $4)
    }
    let _: (PicoI2C, UInt8, Int, Duration, Bool) throws -> [UInt8] = {
      try $0.read(address: $1, count: $2, timeout: $3, stop: $4)
    }
    let _: (PicoI2C) -> Frequency = { $0.actualFrequency }
    let _: (BoardLED) -> PicoBoard = { $0.board }
    let _: () throws -> BoardLED = { try BoardLED() }
    let _: (PicoBoard) throws -> BoardLED = { try BoardLED(board: $0) }
    let _: (BoardLED, PinState) throws -> Void = { try $0.set($1) }
    let _: (BoardLED) throws -> Void = { try $0.toggle() }
    let _: (PicoGPIO, UInt32) throws -> Void = { try $0.set(mask: $1) }
    let _: (PicoGPIO, UInt32) throws -> Void = { try $0.clear(mask: $1) }
    let _: (PicoGPIO, UInt32) throws -> Void = { try $0.toggle(mask: $1) }
    let _: (PicoSPI, [UInt8]) throws -> Void = { try $0.writeDMA($1) }
    let _: (PicoSPI, [UInt8], Duration) throws -> Void = { try $0.writeDMA($1, timeout: $2) }
    let _: (PicoSPI, [UInt16]) throws -> Void = { try $0.writeDMA($1) }
    let _: (PicoSPI, [UInt16], Duration) throws -> Void = { try $0.writeDMA($1, timeout: $2) }
    let _: (PicoSPI, [UInt8], Duration) throws -> [UInt8] = { try $0.transferDMA($1, timeout: $2) }
    let _: (PicoSPI, [UInt16], Duration) throws -> [UInt16] = {
      try $0.transferDMA($1, timeout: $2)
    }
    let _: (PicoSPI, [UInt16], Duration) throws -> Void = { try $0.write($1, timeout: $2) }
    let _: (PicoSPI, Int, UInt8) throws -> [UInt8] = {
      try $0.read(count: $1, repeatedByte: $2)
    }
    let _: (PicoSPI, Int, UInt8, Duration) throws -> [UInt8] = {
      try $0.read(count: $1, repeatedByte: $2, timeout: $3)
    }
    let _: (PicoSPI, Int, UInt16) throws -> [UInt16] = {
      try $0.read($1, repeatedWord: $2)
    }
    let _: (PicoSPI, Int, UInt16, Duration) throws -> [UInt16] = {
      try $0.read($1, repeatedWord: $2, timeout: $3)
    }
    let _: (PicoSPI, [UInt16], Duration) throws -> [UInt16] = {
      try $0.transfer($1, timeout: $2)
    }
    let _: (PicoSPI, [UInt8]) throws -> [UInt8] = { try $0.transferDMA($1) }
    let _: (PicoSPI, [UInt16]) throws -> [UInt16] = { try $0.transferDMA($1) }
    let _: (PicoUART, [UInt8]) throws -> Void = { try $0.writeDMA($1) }
    let _: (PicoUART, [UInt8], Duration) throws -> Void = { try $0.writeDMA($1, timeout: $2) }
    let _: (PicoSPI) -> Void = { $0.releaseDMAChannels() }
    let _: (PicoUART) -> Void = { $0.releaseDMAChannel() }
    let _: (PicoUART) -> PicoChip = { $0.chip }
    let _: (PicoUART) -> Frequency = { $0.actualBaudRate }
    let _: (PicoSPI) -> PicoPin? = { $0.miso }
    let _: (PicoInterrupts, PicoPin) -> Void = { $0.disable($1) }
    let _: (PicoPWM, UInt16) throws -> Void = { try $0.setCounterLevel($1) }
    let _: (PicoPWM) -> Frequency = { $0.actualFrequency }
    let _: PinPull = .up
    let _: PinDriveStrength = .milliamps12
    let _: PinSlewRate = .fast
  }
}
