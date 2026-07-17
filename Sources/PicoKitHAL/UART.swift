#if !PICOKIT_PICO_SDK
  import PicoKitCore
#else
  import PicoKitSDKBridge
#endif

public enum UARTInstance: UInt32, Sendable { case uart0, uart1 }

extension UARTInstance {
  fileprivate func validate(tx: PicoPin, rx: PicoPin, chip: PicoChip) throws(PicoKitError) {
    guard tx != rx else {
      throw PicoKitError.ownershipConflict("\(self) TX and RX must use different pins")
    }
    let txPins: [Int]
    let rxPins: [Int]
    switch (chip, self) {
    case (.rp2040, .uart0):
      txPins = [0, 12, 16, 28]
      rxPins = [1, 13, 17, 29]
    case (.rp2040, .uart1):
      txPins = [4, 8, 20, 24]
      rxPins = [5, 9, 21, 25]
    case (.rp2350, .uart0):
      txPins = [0, 2, 12, 14, 16, 18, 28]
      rxPins = [1, 3, 13, 15, 17, 19, 29]
    case (.rp2350, .uart1):
      txPins = [4, 6, 8, 10, 20, 22, 24, 26]
      rxPins = [5, 7, 9, 11, 21, 23, 25, 27]
    }
    guard txPins.contains(Int(tx.rawValue)) else {
      throw PicoKitError.invalidPeripheralPin(peripheral: "\(self) TX on \(chip)", pin: tx)
    }
    guard rxPins.contains(Int(rx.rawValue)) else {
      throw PicoKitError.invalidPeripheralPin(peripheral: "\(self) RX on \(chip)", pin: rx)
    }
  }
}

public final class PicoUART {
  public let instance: UARTInstance
  public let chip: PicoChip
  /// The baud rate actually selected by the SDK.
  public let actualBaudRate: Frequency

  deinit {
    releaseDMAChannel()
  }

  public init(
    _ instance: UARTInstance,
    baudRate: Frequency,
    tx: PicoPin,
    rx: PicoPin,
    chip: PicoChip = .compiled
  ) throws(PicoKitError) {
    try instance.validate(tx: tx, rx: rx, chip: chip)
    #if PICOKIT_PICO_SDK
      let compiledChip = picokit_compiled_chip() == 0 ? PicoChip.rp2040 : .rp2350
      guard chip == compiledChip else {
        throw PicoKitError.unavailable("UART chip does not match compiled Pico chip")
      }
      var actualBaudRate: UInt32 = 0
      let status = picokit_uart_init_with_actual_baud_rate(
        instance.rawValue, baudRate.hertz, tx.rawValue, rx.rawValue, &actualBaudRate
      )
      guard status == 0 else {
        throw PicoKitError.ioFailure(operation: "UART setup", status: status)
      }
      self.instance = instance
      self.chip = chip
      self.actualBaudRate = try Frequency.hertz(actualBaudRate)
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  public func write(_ bytes: [UInt8], timeout: Duration) throws(PicoKitError) -> Int {
    let count = try picoKitTransferCount(bytes.count, operation: "UART write")
    #if PICOKIT_PICO_SDK
      let result = bytes.withUnsafeBufferPointer {
        picokit_uart_write(instance.rawValue, $0.baseAddress, count, timeout.microseconds)
      }
      if result == -2 { throw PicoKitError.timedOut(operation: "UART write") }
      guard result >= 0 else {
        throw PicoKitError.ioFailure(operation: "UART write", status: result)
      }
      guard result == Int32(count) else {
        throw PicoKitError.partialTransfer(
          operation: "UART write", transferred: Int(result), expected: Int(count)
        )
      }
      return Int(result)
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  /// Writes a prepared buffer through DMA and waits for the final byte to
  /// enter the UART FIFO. It has no timeout; use `write(_:timeout:)` when a
  /// bounded control-path operation is required.
  public func writeDMA(_ bytes: [UInt8]) throws(PicoKitError) {
    let count = try picoKitTransferCount(bytes.count, operation: "UART DMA write")
    #if PICOKIT_PICO_SDK
      let status = bytes.withUnsafeBufferPointer {
        picokit_uart_write_dma(instance.rawValue, $0.baseAddress, count)
      }
      guard status == Int32(count) else {
        throw PicoKitError.ioFailure(operation: "UART DMA write", status: status)
      }
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  /// Writes a prepared buffer through DMA with a bounded wait for the DMA
  /// channel to finish. A timeout aborts the channel before this method
  /// returns, so the caller may safely release its buffer.
  public func writeDMA(_ bytes: [UInt8], timeout: Duration) throws(PicoKitError) {
    let count = try picoKitTransferCount(bytes.count, operation: "UART DMA write")
    #if PICOKIT_PICO_SDK
      let status = bytes.withUnsafeBufferPointer {
        picokit_uart_write_dma_timeout(
          instance.rawValue, $0.baseAddress, count, timeout.microseconds)
      }
      if status == -2 { throw PicoKitError.timedOut(operation: "UART DMA write") }
      guard status >= 0 else {
        throw PicoKitError.ioFailure(operation: "UART DMA write", status: status)
      }
      guard status == Int32(count) else {
        throw PicoKitError.partialTransfer(
          operation: "UART DMA write", transferred: Int(status), expected: Int(count)
        )
      }
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  /// Releases the DMA channel retained by `writeDMA(_:)`. PicoKit reuses the
  /// channel between writes to avoid repeated resource-claim overhead.
  public func releaseDMAChannel() {
    #if PICOKIT_PICO_SDK
      picokit_uart_dma_release(instance.rawValue)
    #endif
  }

  /// Returns one received byte without waiting, or `nil` when the RX FIFO is
  /// empty. Use `read(timeout:)` when the caller must wait for input.
  public func read() throws(PicoKitError) -> UInt8? {
    #if PICOKIT_PICO_SDK
      var byte: UInt8 = 0
      let result = picokit_uart_read(instance.rawValue, &byte, 0)
      if result == -2 { return nil }
      guard result == 0 else {
        throw PicoKitError.ioFailure(operation: "UART read", status: result)
      }
      return byte
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  public func read(timeout: Duration) throws(PicoKitError) -> UInt8 {
    #if PICOKIT_PICO_SDK
      var byte: UInt8 = 0
      let result = picokit_uart_read(instance.rawValue, &byte, timeout.microseconds)
      if result == -2 { throw PicoKitError.timedOut(operation: "UART read") }
      guard result == 0 else {
        throw PicoKitError.ioFailure(operation: "UART read", status: result)
      }
      return byte
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }
}
