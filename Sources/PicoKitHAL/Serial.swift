#if !PICOKIT_PICO_SDK
  import PicoKitCore
#else
  import PicoKitSDKBridge
#endif

func picoKitSerialWriteError(status: Int32, operation: String) -> PicoKitError? {
  #if PICOKIT_PICO_SDK
    let disconnected = PICOKIT_STDIO_STATUS_DISCONNECTED
  #else
    // Kept in lockstep with PicoKitSDKBridge.h and exercised by host tests.
    let disconnected: Int32 = -2
  #endif
  if status == disconnected {
    return .unavailable("USB serial host is not connected")
  }
  if status != 0 { return .ioFailure(operation: operation, status: status) }
  return nil
}

func picoKitSerialNoDataStatus() -> Int32 {
  #if PICOKIT_PICO_SDK
    return Int32(PICOKIT_STDIO_STATUS_NO_DATA)
  #else
    // Kept in lockstep with PicoKitSDKBridge.h and exercised by host tests.
    return -3
  #endif
}

func picoKitSerialReadError(status: Int32, operation: String) -> PicoKitError? {
  #if PICOKIT_PICO_SDK
    let disconnected = PICOKIT_STDIO_STATUS_DISCONNECTED
  #else
    let disconnected: Int32 = -2
  #endif
  if status == disconnected {
    return .unavailable("USB serial host is not connected")
  }
  if status != 0 && status != picoKitSerialNoDataStatus() {
    return .ioFailure(operation: operation, status: status)
  }
  return nil
}

public final class USBSerial {
  public init() throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      picokit_stdio_init()
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  /// Reports whether the USB CDC host has opened the firmware's serial
  /// interface. This is a snapshot; the host may disconnect immediately
  /// after the value is read.
  public var isConnected: Bool {
    #if PICOKIT_PICO_SDK
      return picokit_stdio_connected() != 0
    #else
      return false
    #endif
  }

  public func write(_ text: String) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      let status = text.withCString { picokit_stdio_write($0) }
      if let error = picoKitSerialWriteError(status: status, operation: "USB serial write") {
        throw error
      }
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  /// Writes one raw byte without allocating an array.
  public func write(_ byte: UInt8) throws(PicoKitError) {
    #if PICOKIT_PICO_SDK
      let status = picokit_stdio_write_byte(byte)
      if let error = picoKitSerialWriteError(status: status, operation: "USB serial write") {
        throw error
      }
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  /// Writes raw bytes without interpreting them as UTF-8 or a C string.
  public func write(_ bytes: [UInt8]) throws(PicoKitError) {
    let count = try picoKitTransferCount(bytes.count, operation: "USB serial write")
    #if PICOKIT_PICO_SDK
      guard !bytes.isEmpty else { return }
      let status = bytes.withUnsafeBufferPointer {
        picokit_stdio_write_bytes($0.baseAddress, count)
      }
      if let error = picoKitSerialWriteError(status: status, operation: "USB serial write") {
        throw error
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
      if let error = picoKitSerialReadError(status: result, operation: "USB serial read") {
        throw error
      }
      if result == picoKitSerialNoDataStatus() { return nil }
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
      if let error = picoKitSerialReadError(status: result, operation: "USB serial read") {
        throw error
      }
      if result == picoKitSerialNoDataStatus() {
        throw PicoKitError.timedOut(operation: "USB serial read")
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
  /// USB serial convenience API for one foreground owner. It deliberately has
  /// no `Sendable` conformance because its initialization and lookahead state
  /// are mutable.
  public final class PicoSerial {
    private var isInitialized = false
    private var pendingByte: UInt8?

    public init() {}

    /// Reports whether the USB CDC host has opened the serial interface.
    /// Treat this as a snapshot and continue to handle disconnected writes.
    @inline(__always)
    public var connected: Bool {
      initializeIfNeeded()
      return picokit_stdio_connected() != 0
    }

    @inline(__always)
    private func initializeIfNeeded() {
      guard !isInitialized else { return }
      picokit_stdio_init()
      isInitialized = true
    }

    @inline(__always)
    public func write(_ text: String) {
      initializeIfNeeded()
      text.withCString { _ = picokit_stdio_write($0) }
    }

    @inline(__always)
    public func write(_ byte: UInt8) {
      initializeIfNeeded()
      _ = picokit_stdio_write_byte(byte)
    }

    @inline(__always)
    public func write(_ bytes: [UInt8]) {
      guard !bytes.isEmpty else { return }
      guard bytes.count <= Int(UInt32.max) else {
        preconditionFailure("USB serial write exceeds UInt32 transfer capacity")
      }
      initializeIfNeeded()
      bytes.withUnsafeBufferPointer {
        _ = picokit_stdio_write_bytes($0.baseAddress, UInt32($0.count))
      }
    }

    @inline(__always)
    public func print(_ text: String) { write(text) }

    @inline(__always)
    public func println(_ text: String = "") {
      initializeIfNeeded()
      text.withCString { _ = picokit_stdio_write_line($0) }
    }

    @inline(__always)
    public var available: Bool {
      if pendingByte != nil { return true }
      initializeIfNeeded()
      var byte: UInt8 = 0
      let result = picokit_stdio_read(&byte, 0)
      if result == 0 {
        pendingByte = byte
      } else if result != PICOKIT_STDIO_STATUS_NO_DATA
        && result != PICOKIT_STDIO_STATUS_DISCONNECTED
      {
        preconditionFailure("USB serial read failed: \(result)")
      }
      return pendingByte != nil
    }

    @inline(__always)
    public func read() -> UInt8? {
      if let pendingByte {
        self.pendingByte = nil
        return pendingByte
      }
      initializeIfNeeded()
      var byte: UInt8 = 0
      let result = picokit_stdio_read(&byte, 0)
      if result == 0 { return byte }
      if result == PICOKIT_STDIO_STATUS_NO_DATA
        || result == PICOKIT_STDIO_STATUS_DISCONNECTED
      { return nil }
      preconditionFailure("USB serial read failed: \(result)")
    }
  }

  @inline(__always)
  private func picoKitSketchMilliseconds(_ milliseconds: UInt64) -> UInt64 {
    let result = milliseconds.multipliedReportingOverflow(by: 1_000)
    guard !result.overflow else {
      preconditionFailure("Delay in milliseconds overflows microseconds: \(milliseconds)")
    }
    return result.partialValue
  }

  /// Nonthrowing global convenience API. The unchecked conformance permits
  /// global storage; callers must still keep hardware access single-owner.
  public final class Pico: @unchecked Sendable {
    public let gpio: PicoGPIO
    public let serial: PicoSerial

    public init() {
      self.gpio = PicoGPIO.compiled
      self.serial = PicoSerial()
    }

    @inline(__always)
    public func pinMode(_ pin: Int, _ mode: PinMode) {
      try! gpio.pinMode(pin, mode)
    }

    @inline(__always)
    public func digitalWrite(_ pin: Int, _ state: PinState) {
      try! gpio.digitalWrite(pin, state)
    }

    @inline(__always)
    public func digitalRead(_ pin: Int) -> PinState {
      try! gpio.digitalRead(pin)
    }

    /// Atomically flips one GPIO output without a read-modify-write cycle.
    @inline(__always)
    public func digitalToggle(_ pin: Int) {
      try! gpio.digitalToggle(pin)
    }

    @inline(__always)
    public func sleep(_ milliseconds: UInt64) {
      guard milliseconds != 0 else { return }
      picokit_sleep_us(picoKitSketchMilliseconds(milliseconds))
    }

    @inline(__always)
    public func sleepMicroseconds(_ microseconds: UInt64) {
      guard microseconds != 0 else { return }
      picokit_sleep_us(microseconds)
    }
  }

#else

  protocol PicoSerialBackend: AnyObject {
    var isConnected: Bool { get }
    func write(_ text: String) throws(PicoKitError)
    func write(_ bytes: [UInt8]) throws(PicoKitError)
    func read() throws(PicoKitError) -> UInt8?
  }

  private final class SDKSerialBackend: PicoSerialBackend {
    private lazy var usb = picoKitUnchecked { try USBSerial() }

    // Host builds intentionally have no SDK-backed USB device. Keep the
    // connection probe non-throwing and side-effect free; write/read paths
    // still use the lazy backend and retain their existing trap behavior.
    var isConnected: Bool { false }

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

  /// USB serial access with no setup ceremony or throwing calls. One owner
  /// must serialize access; the mutable lookahead byte is not Sendable.
  public final class PicoSerial {
    private let backend: any PicoSerialBackend
    private var pendingByte: UInt8?

    public convenience init() {
      self.init(backend: SDKSerialBackend())
    }

    init(backend: any PicoSerialBackend) {
      self.backend = backend
    }

    /// Reports whether the USB CDC host has opened the serial interface.
    /// Treat this as a snapshot and continue to handle disconnected writes.
    public var connected: Bool { backend.isConnected }

    public func write(_ text: String) {
      picoKitUnchecked { try backend.write(text) }
    }

    public func write(_ bytes: [UInt8]) {
      picoKitUnchecked { try backend.write(bytes) }
    }

    public func write(_ byte: UInt8) {
      write([byte])
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
  /// The unchecked conformance permits global storage, not concurrent access.
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

    public func digitalToggle(_ pin: Int) {
      let validated = picoKitUnchecked { try PicoPin(pin) }
      let state = picoKitUnchecked { try gpio.read(validated) }
      picoKitUnchecked { try gpio.write(validated, state: state.toggled) }
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
// swift-format-ignore
public let Serial = pico.serial

@inline(__always)
public func pinMode(_ pin: Int, _ mode: PinMode) { pico.pinMode(pin, mode) }
@inline(__always)
public func digitalWrite(_ pin: Int, _ state: PinState) { pico.digitalWrite(pin, state) }
@inline(__always)
public func digitalRead(_ pin: Int) -> PinState { pico.digitalRead(pin) }
@inline(__always)
public func digitalToggle(_ pin: Int) { pico.digitalToggle(pin) }
@inline(__always)
public func sleep(_ milliseconds: UInt64) { pico.sleep(milliseconds) }
@inline(__always)
public func sleepMicroseconds(_ microseconds: UInt64) { pico.sleepMicroseconds(microseconds) }
