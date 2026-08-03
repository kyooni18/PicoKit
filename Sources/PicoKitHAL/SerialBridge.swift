#if !PICOKIT_PICO_SDK
  import PicoKitCore
#endif

/// Pumps raw bytes between the board's USB CDC serial endpoint and one hardware
/// UART. The bridge is intentionally byte-oriented: framing, escaping, and
/// application-level flow control remain the responsibility of the peer.
public final class SerialBridge {
  public let usb: PicoSerial
  public let uart: PicoUART
  public let chunkSize: Int
  public let writeTimeout: Duration

  public init(
    uart: PicoUART,
    usb: PicoSerial = PicoSerial(),
    chunkSize: Int = 64,
    writeTimeout: Duration = try! .milliseconds(100)
  ) throws(PicoKitError) {
    guard chunkSize > 0 else {
      throw PicoKitError.ioFailure(operation: "SerialBridge setup", status: -1)
    }
    self.usb = usb
    self.uart = uart
    self.chunkSize = chunkSize
    self.writeTimeout = writeTimeout
  }

  /// Forwards at most one chunk in each direction and returns whether any
  /// bytes moved. Call this from a foreground loop for cooperative bridging.
  @discardableResult
  public func pump() throws(PicoKitError) -> Bool {
    var moved = false
    let usbBytes = usb.read(upToCount: chunkSize)
    if !usbBytes.isEmpty {
      _ = try uart.write(usbBytes, timeout: writeTimeout)
      moved = true
    }

    let uartBytes = try uart.read(upToCount: chunkSize)
    if !uartBytes.isEmpty {
      usb.write(uartBytes)
      moved = true
    }
    return moved
  }

  /// Runs the bridge until the UART is closed or an I/O error is thrown.
  /// The short idle delay prevents a disconnected or silent peer from causing
  /// a busy loop while keeping interactive byte forwarding responsive.
  public func run(idleDelay: Duration = try! .milliseconds(1)) throws(PicoKitError) -> Never {
    while true {
      if !(try pump()) { sleepMicroseconds(idleDelay.microseconds) }
    }
  }
}
