#if !PICOKIT_PICO_SDK
import PicoKitCore
#endif

/// SDK-backed hardware access. The implementation is compiled only by the
/// Pico firmware CMake target. Host tests can exercise validation via fakes.
public final class PicoGPIO: DigitalIO {
    public static var rp2040: PicoGPIO { PicoGPIO(chip: .rp2040) }
    public static var rp2350: PicoGPIO { PicoGPIO(chip: .rp2350) }
    public let chip: PicoChip
    public init(chip: PicoChip = .rp2040) { self.chip = chip }

    public func setMode(_ pin: PicoPin, mode: PinMode) throws {
        #if PICOKIT_PICO_SDK
        picokit_gpio_init(pin.rawValue)
        picokit_gpio_set_direction(pin.rawValue, mode == .output ? 1 : 0)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
    public func write(_ pin: PicoPin, state: PinState) throws {
        #if PICOKIT_PICO_SDK
        picokit_gpio_write(pin.rawValue, state == .high ? 1 : 0)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
    public func read(_ pin: PicoPin) throws -> PinState {
        #if PICOKIT_PICO_SDK
        return picokit_gpio_read(pin.rawValue) == 0 ? .low : .high
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
    public func toggle(_ pin: PicoPin) throws {
        #if PICOKIT_PICO_SDK
        picokit_gpio_toggle(pin.rawValue)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Arduino-style names for callers that keep a concrete GPIO instance.
    public func pinMode(_ pin: Int, _ mode: PinMode) throws {
        try setMode(PicoPin(pin), mode: mode)
    }
    public func digitalWrite(_ pin: Int, _ state: PinState) throws {
        try write(PicoPin(pin), state: state)
    }
    public func digitalRead(_ pin: Int) throws -> PinState {
        try read(PicoPin(pin))
    }
    public func digitalToggle(_ pin: Int) throws {
        try toggle(PicoPin(pin))
    }
}

public final class BoardLED {
    public init(board: PicoBoard) throws {
        #if PICOKIT_PICO_SDK
        guard picokit_status_led_init() == 0 else { throw PicoKitError.unavailable("board status LED") }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
    public func set(_ state: PinState) throws {
        #if PICOKIT_PICO_SDK
        picokit_status_led_write(state == .high ? 1 : 0)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
    public func toggle() throws {
        #if PICOKIT_PICO_SDK
        picokit_status_led_toggle()
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
}

public enum Clock {
    public static func now() -> UInt64 {
        #if PICOKIT_PICO_SDK
        return picokit_time_us()
        #else
        return 0
        #endif
    }
    /// This blocks the calling core; it is not callable from an interrupt.
    public static func sleep(for duration: Duration) throws {
        #if PICOKIT_PICO_SDK
        picokit_sleep_us(duration.microseconds)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
}

/// Arduino-compatible timing spellings. A zero delay is a valid no-op.
public func delay(_ milliseconds: UInt64) throws {
    guard milliseconds != 0 else { return }
    try Clock.sleep(for: Duration.milliseconds(milliseconds))
}

public func delayMicroseconds(_ microseconds: UInt64) throws {
    guard microseconds != 0 else { return }
    try Clock.sleep(for: Duration.microseconds(microseconds))
}

public func millis() -> UInt64 { Clock.now() / 1_000 }
public func micros() -> UInt64 { Clock.now() }

public final class USBSerial {
    public init() throws {
        #if PICOKIT_PICO_SDK
        picokit_stdio_init()
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
    public func write(_ text: String) throws {
        #if PICOKIT_PICO_SDK
        text.withCString { picokit_stdio_write($0) }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
}

// MARK: - High-level convenience API

/// Convert a low-level failure into a firmware trap for the convenience API.
///
/// The low-level API remains throwing so applications that need to recover can
/// do so. The convenience API is intended for small sketches, where an invalid
/// pin or unavailable SDK feature is a programming/configuration error and a
/// fail-fast message is more useful than forcing `try` through every call.
@inline(__always)
private func picoKitUnchecked<T>(_ operation: () throws -> T) -> T {
    do {
        return try operation()
    } catch {
        preconditionFailure("PicoKit operation failed: \(error)")
    }
}

/// A small, non-throwing facade over the low-level PicoKit peripherals.
///
/// Use the module-level helpers for the shortest sketch syntax, or create a
/// `Pico` with a custom `DigitalIO` implementation for tests and GPIO
/// expanders. The low-level `PicoGPIO` and protocol APIs remain available when
/// explicit error handling is needed.
/// `Pico` is intended to be used from one foreground execution context, like
/// the low-level peripheral instances it wraps.
public final class Pico: @unchecked Sendable {
    public let gpio: any DigitalIO
    public let serial: PicoSerial

    public init(gpio: any DigitalIO = PicoGPIO(), serial: PicoSerial = PicoSerial()) {
        self.gpio = gpio
        self.serial = serial
    }

    public func pinMode(_ pin: Int, _ mode: PinMode) {
        picoKitUnchecked { try gpio.setMode(PicoPin(pin), mode: mode) }
    }

    public func digitalWrite(_ pin: Int, _ state: PinState) {
        picoKitUnchecked { try gpio.write(PicoPin(pin), state: state) }
    }

    public func digitalRead(_ pin: Int) -> PinState {
        picoKitUnchecked { try gpio.read(PicoPin(pin)) }
    }

    public func sleep(_ milliseconds: UInt64) {
        guard milliseconds != 0 else { return }
        picoKitUnchecked { try Clock.sleep(for: Duration.milliseconds(milliseconds)) }
    }

    public func sleepMicroseconds(_ microseconds: UInt64) {
        guard microseconds != 0 else { return }
        picoKitUnchecked { try Clock.sleep(for: Duration.microseconds(microseconds)) }
    }
}

/// The default high-level Pico runtime used by the global helpers.
public let pico = Pico()

/// USB serial output with no setup ceremony or throwing calls.
///
/// The underlying USB stdio peripheral is initialized lazily on the first
/// write, which keeps importing PicoKit side-effect free.
/// Serial output is single-context, matching the Pico SDK stdio contract.
public final class PicoSerial: @unchecked Sendable {
    private lazy var usb = picoKitUnchecked { try USBSerial() }

    public init() {}

    public func write(_ text: String) {
        picoKitUnchecked { try usb.write(text) }
    }

    public func print(_ text: String) {
        write(text)
    }

    public func println(_ text: String = "") {
        write(text)
        write("\n")
    }
}

/// Arduino-style global serial port.
public let Serial = pico.serial

/// Non-throwing GPIO helpers backed by the default `pico` runtime.
public func pinMode(_ pin: Int, _ mode: PinMode) {
    pico.pinMode(pin, mode)
}

public func digitalWrite(_ pin: Int, _ state: PinState) {
    pico.digitalWrite(pin, state)
}

public func digitalRead(_ pin: Int) -> PinState {
    pico.digitalRead(pin)
}

/// Block the current core for the requested number of milliseconds.
public func sleep(_ milliseconds: UInt64) {
    pico.sleep(milliseconds)
}

/// Block the current core for the requested number of microseconds.
public func sleepMicroseconds(_ microseconds: UInt64) {
    pico.sleepMicroseconds(microseconds)
}

public enum UARTInstance: UInt32, Sendable { case uart0, uart1 }
public final class PicoUART {
    public init(_ instance: UARTInstance, baudRate: Frequency, tx: PicoPin, rx: PicoPin) throws {
        #if PICOKIT_PICO_SDK
        let status = picokit_uart_init(instance.rawValue, baudRate.hertz, tx.rawValue, rx.rawValue)
        guard status == 0 else { throw PicoKitError.ioFailure(operation: "UART setup", status: status) }
        self.instance = instance
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
    public let instance: UARTInstance
    public func write(_ bytes: [UInt8], timeout: Duration) throws -> Int {
        #if PICOKIT_PICO_SDK
        let result = bytes.withUnsafeBufferPointer { picokit_uart_write(instance.rawValue, $0.baseAddress, UInt32($0.count), timeout.microseconds) }
        if result == -2 { throw PicoKitError.timedOut(operation: "UART write") }
        guard result >= 0 else { throw PicoKitError.ioFailure(operation: "UART write", status: result) }
        return Int(result)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
    public func read(timeout: Duration) throws -> UInt8 {
        #if PICOKIT_PICO_SDK
        var byte: UInt8 = 0
        let result = picokit_uart_read(instance.rawValue, &byte, timeout.microseconds)
        if result == -2 { throw PicoKitError.timedOut(operation: "UART read") }
        guard result == 0 else { throw PicoKitError.ioFailure(operation: "UART read", status: result) }
        return byte
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
}

public enum PWMChannel: Sendable { case a, b }
public final class PicoPWM {
    public init(pin: PicoPin, frequency: Frequency) throws {
        #if PICOKIT_PICO_SDK
        let status = picokit_pwm_init(pin.rawValue, frequency.hertz)
        guard status == 0 else { throw PicoKitError.ioFailure(operation: "PWM setup", status: status) }
        self.pin = pin
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
    public let pin: PicoPin
    public func setDutyCycle(_ fraction: UInt16) throws {
        #if PICOKIT_PICO_SDK
        picokit_pwm_set_level(pin.rawValue, fraction)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Arduino-style 8-bit duty cycle (0 = off, 255 = fully on).
    public func analogWrite(_ duty: UInt8) throws {
        try setDutyCycle(UInt16(duty) * 257)
    }

    /// Full-resolution duty cycle (0...65535).
    public func analogWrite(_ duty: UInt16) throws {
        try setDutyCycle(duty)
    }
}

/// Write an 8-bit duty cycle to the pin owned by `pwm`.
@inlinable
public func analogWrite(_ pin: Int, _ duty: UInt8, using pwm: PicoPWM) throws {
    let validated = try PicoPin(pin)
    guard validated == pwm.pin else {
        throw PicoKitError.ownershipConflict("PWM is configured for \(pwm.pin), not \(validated)")
    }
    try pwm.analogWrite(duty)
}

@inlinable
public func analogWrite(_ pin: Int, _ duty: UInt16, using pwm: PicoPWM) throws {
    let validated = try PicoPin(pin)
    guard validated == pwm.pin else {
        throw PicoKitError.ownershipConflict("PWM is configured for \(pwm.pin), not \(validated)")
    }
    try pwm.analogWrite(duty)
}

public enum ADCChannel: UInt32, CaseIterable, Sendable { case gpio26, gpio27, gpio28, gpio29, temperature }
public final class PicoADC {
    public init() throws {
        #if PICOKIT_PICO_SDK
        picokit_adc_init()
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
    public func read(_ channel: ADCChannel) throws -> UInt16 {
        #if PICOKIT_PICO_SDK
        let value = picokit_adc_read(channel.rawValue)
        guard value >= 0 else { throw PicoKitError.ioFailure(operation: "ADC read", status: value) }
        return UInt16(value)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
}

/// Arduino-style ADC helpers. External ADC-capable pins are GPIO26...GPIO29.
@inlinable
public func analogRead(_ channel: ADCChannel, using adc: PicoADC) throws -> UInt16 {
    try adc.read(channel)
}

public func analogRead(_ pin: Int, using adc: PicoADC) throws -> UInt16 {
    let channel: ADCChannel
    switch pin {
    case 26: channel = .gpio26
    case 27: channel = .gpio27
    case 28: channel = .gpio28
    case 29: channel = .gpio29
    default: throw PicoKitError.unavailable("ADC is only available on GPIO26...GPIO29")
    }
    return try adc.read(channel)
}

public enum I2CInstance: UInt32, Sendable { case i2c0, i2c1 }
public final class PicoI2C {
    public init(_ instance: I2CInstance, frequency: Frequency, sda: PicoPin, scl: PicoPin) throws {
        #if PICOKIT_PICO_SDK
        let status = picokit_i2c_init(instance.rawValue, frequency.hertz, sda.rawValue, scl.rawValue)
        guard status == 0 else { throw PicoKitError.ioFailure(operation: "I2C setup", status: status) }
        self.instance = instance
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
    public let instance: I2CInstance
    public func write(address: UInt8, bytes: [UInt8], timeout: Duration) throws -> Int {
        guard (0x08...0x77).contains(address) else { throw PicoKitError.invalidAddress(address) }
        #if PICOKIT_PICO_SDK
        let result = bytes.withUnsafeBufferPointer { picokit_i2c_write(instance.rawValue, UInt32(address), $0.baseAddress, UInt32($0.count), timeout.microseconds) }
        if result == -2 { throw PicoKitError.timedOut(operation: "I2C write") }
        guard result >= 0 else { throw PicoKitError.ioFailure(operation: "I2C write", status: result) }
        return Int(result)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
    public func read(address: UInt8, count: Int, timeout: Duration) throws -> [UInt8] {
        guard (0x08...0x77).contains(address) else { throw PicoKitError.invalidAddress(address) }
        guard count >= 0 else { throw PicoKitError.ioFailure(operation: "I2C read", status: -1) }
        #if PICOKIT_PICO_SDK
        var result = [UInt8](repeating: 0, count: count)
        let status = result.withUnsafeMutableBufferPointer { picokit_i2c_read(instance.rawValue, UInt32(address), $0.baseAddress, UInt32($0.count), timeout.microseconds) }
        if status == -2 { throw PicoKitError.timedOut(operation: "I2C read") }
        guard status == count else { throw PicoKitError.ioFailure(operation: "I2C read", status: status) }
        return result
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
}

public enum SPIInstance: UInt32, Sendable { case spi0, spi1 }
public final class PicoSPI {
    public init(_ instance: SPIInstance, frequency: Frequency, sck: PicoPin, mosi: PicoPin, miso: PicoPin) throws {
        #if PICOKIT_PICO_SDK
        let status = picokit_spi_init(instance.rawValue, frequency.hertz, sck.rawValue, mosi.rawValue, miso.rawValue)
        guard status == 0 else { throw PicoKitError.ioFailure(operation: "SPI setup", status: status) }
        self.instance = instance
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
    public let instance: SPIInstance
    public func transfer(_ bytes: [UInt8], timeout: Duration) throws -> [UInt8] {
        #if PICOKIT_PICO_SDK
        var received = [UInt8](repeating: 0, count: bytes.count)
        let status = bytes.withUnsafeBufferPointer { tx in
            received.withUnsafeMutableBufferPointer { rx in
                picokit_spi_transfer(instance.rawValue, tx.baseAddress, rx.baseAddress, UInt32(tx.count), timeout.microseconds)
            }
        }
        if status == -2 { throw PicoKitError.timedOut(operation: "SPI transfer") }
        guard status == bytes.count else { throw PicoKitError.ioFailure(operation: "SPI transfer", status: status) }
        return received
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
}

public enum GPIOInterruptEdge: UInt32, Sendable { case rising = 1, falling = 2, either = 3 }
/// Interrupt delivery is recorded by the C bridge. Read events from normal
/// foreground code; never call Swift or allocate memory in the IRQ handler.
public final class PicoInterrupts {
    public init() {}
    public func enable(_ pin: PicoPin, edge: GPIOInterruptEdge) throws {
        #if PICOKIT_PICO_SDK
        let status = picokit_interrupt_enable(pin.rawValue, edge.rawValue)
        guard status == 0 else { throw PicoKitError.ioFailure(operation: "GPIO interrupt setup", status: status) }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
    public func takeEvents(for pin: PicoPin) -> UInt32 {
        #if PICOKIT_PICO_SDK
        return picokit_interrupt_take(pin.rawValue)
        #else
        return 0
        #endif
    }
}

public final class PicoWatchdog {
    public init() {}
    public func enable(timeout: Duration, pauseOnDebug: Bool = true) throws {
        #if PICOKIT_PICO_SDK
        guard timeout.microseconds <= UInt64(UInt32.max) * 1_000 else { throw PicoKitError.invalidTimeout(timeout.microseconds) }
        picokit_watchdog_enable(UInt32(timeout.microseconds / 1_000), pauseOnDebug ? 1 : 0)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
    public func update() {
        #if PICOKIT_PICO_SDK
        picokit_watchdog_update()
        #endif
    }
}
