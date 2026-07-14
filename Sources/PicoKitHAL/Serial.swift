#if !PICOKIT_PICO_SDK
import PicoKitCore
#endif

public final class USBSerial {
    public init() throws(PicoKitError) {
        #if PICOKIT_PICO_SDK
        picokit_stdio_init()
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func write(_ text: String) throws(PicoKitError) {
        #if PICOKIT_PICO_SDK
        text.withCString { picokit_stdio_write($0) }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Writes raw bytes without interpreting them as UTF-8 or a C string.
    public func write(_ bytes: [UInt8]) throws(PicoKitError) {
        #if PICOKIT_PICO_SDK
        guard !bytes.isEmpty else { return }
        bytes.withUnsafeBufferPointer {
            picokit_stdio_write_bytes($0.baseAddress, UInt32($0.count))
        }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Returns the next USB CDC byte immediately, or `nil` when no input is waiting.
    public func read() throws(PicoKitError) -> UInt8? {
        #if PICOKIT_PICO_SDK
        var byte: UInt8 = 0
        let result = picokit_stdio_read(&byte, 0)
        if result == -2 { return nil }
        guard result == 0 else {
            throw PicoKitError.ioFailure(operation: "USB serial read", status: result)
        }
        return byte
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Waits for one USB CDC byte until `timeout` expires.
    public func read(timeout: Duration) throws(PicoKitError) -> UInt8 {
        #if PICOKIT_PICO_SDK
        var byte: UInt8 = 0
        let result = picokit_stdio_read(&byte, timeout.microseconds)
        if result == -2 { throw PicoKitError.timedOut(operation: "USB serial read") }
        guard result == 0 else {
            throw PicoKitError.ioFailure(operation: "USB serial read", status: result)
        }
        return byte
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
}

#if PICOKIT_PICO_SDK

/// USB serial convenience API for firmware builds. Keep this concrete: calling
/// a typed-throwing requirement through an existential currently erases it to
/// `any Error`, which Embedded Swift cannot represent.
public final class PicoSerial: @unchecked Sendable {
    private lazy var usb = try! USBSerial()
    private var pendingByte: UInt8?

    public init() {}

    public func write(_ text: String) {
        try! usb.write(text)
    }

    public func write(_ bytes: [UInt8]) {
        try! usb.write(bytes)
    }

    public func print(_ text: String) { write(text) }

    public func println(_ text: String = "") {
        write(text)
        write("\n")
    }

    public var available: Bool {
        if pendingByte != nil { return true }
        pendingByte = try! usb.read()
        return pendingByte != nil
    }

    public func read() -> UInt8? {
        if let pendingByte {
            self.pendingByte = nil
            return pendingByte
        }
        return try! usb.read()
    }
}

/// Concrete firmware facade that preserves typed errors for Embedded Swift.
public final class Pico: @unchecked Sendable {
    public let gpio = PicoGPIO()
    public let serial = PicoSerial()

    public init() {}

    public func pinMode(_ pin: Int, _ mode: PinMode) {
        try! gpio.setMode(PicoPin(pin), mode: mode)
    }

    public func digitalWrite(_ pin: Int, _ state: PinState) {
        try! gpio.write(PicoPin(pin), state: state)
    }

    public func digitalRead(_ pin: Int) -> PinState {
        try! gpio.read(PicoPin(pin))
    }

    public func sleep(_ milliseconds: UInt64) {
        guard milliseconds != 0 else { return }
        try! Clock.sleep(for: Duration.milliseconds(milliseconds))
    }

    public func sleepMicroseconds(_ microseconds: UInt64) {
        guard microseconds != 0 else { return }
        try! Clock.sleep(for: Duration.microseconds(microseconds))
    }
}

#else

protocol PicoSerialBackend: AnyObject {
    func write(_ text: String) throws(PicoKitError)
    func write(_ bytes: [UInt8]) throws(PicoKitError)
    func read() throws(PicoKitError) -> UInt8?
}

private final class SDKSerialBackend: PicoSerialBackend {
    private lazy var usb = picoKitUnchecked { try USBSerial() }

    func write(_ text: String) throws(PicoKitError) { try usb.write(text) }
    func write(_ bytes: [UInt8]) throws(PicoKitError) { try usb.write(bytes) }
    func read() throws(PicoKitError) -> UInt8? { try usb.read() }
}

/// Convert a low-level failure into a firmware trap for the convenience API.
@inline(__always)
private func picoKitUnchecked<T>(_ operation: () throws -> T) -> T {
    do {
        return try operation()
    } catch {
        preconditionFailure("PicoKit operation failed: \(error)")
    }
}

/// USB serial access with no setup ceremony or throwing calls.
public final class PicoSerial: @unchecked Sendable {
    private let backend: any PicoSerialBackend
    private var pendingByte: UInt8?

    public convenience init() {
        self.init(backend: SDKSerialBackend())
    }

    init(backend: any PicoSerialBackend) {
        self.backend = backend
    }

    public func write(_ text: String) {
        picoKitUnchecked { try backend.write(text) }
    }

    public func write(_ bytes: [UInt8]) {
        picoKitUnchecked { try backend.write(bytes) }
    }

    public func print(_ text: String) { write(text) }

    public func println(_ text: String = "") {
        write(text)
        write("\n")
    }

    /// Checking availability reads and retains at most one byte.
    public var available: Bool {
        if pendingByte != nil { return true }
        pendingByte = picoKitUnchecked { try backend.read() }
        return pendingByte != nil
    }

    /// Returns the next host byte without waiting, or `nil` when none is available.
    public func read() -> UInt8? {
        if let pendingByte {
            self.pendingByte = nil
            return pendingByte
        }
        return picoKitUnchecked { try backend.read() }
    }
}

/// A small, non-throwing facade over the low-level PicoKit peripherals.
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

#endif

public let pico = Pico()
public let Serial = pico.serial

public func pinMode(_ pin: Int, _ mode: PinMode) { pico.pinMode(pin, mode) }
public func digitalWrite(_ pin: Int, _ state: PinState) { pico.digitalWrite(pin, state) }
public func digitalRead(_ pin: Int) -> PinState { pico.digitalRead(pin) }
public func sleep(_ milliseconds: UInt64) { pico.sleep(milliseconds) }
public func sleepMicroseconds(_ microseconds: UInt64) { pico.sleepMicroseconds(microseconds) }
