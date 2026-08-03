#if !PICOKIT_PICO_SDK
  import PicoKitCore
#else
  import PicoKitSDKBridge
#endif

public enum UARTInstance: UInt32, Sendable { case uart0, uart1 }

public enum UARTDataBits: UInt32, CaseIterable, Sendable {
  case five = 5
  case six = 6
  case seven = 7
  case eight = 8
}

public enum UARTParity: UInt32, CaseIterable, Sendable {
  case none, even, odd
}

public enum UARTStopBits: UInt32, CaseIterable, Sendable {
  case one = 1
  case two = 2
}

public enum UARTFlowControl: UInt32, CaseIterable, Sendable {
  case none, hardware
}

public struct UARTConfiguration: Sendable, Equatable {
  public let baudRate: Frequency
  public let dataBits: UARTDataBits
  public let parity: UARTParity
  public let stopBits: UARTStopBits
  public let flowControl: UARTFlowControl

  public init(
    baudRate: Frequency,
    dataBits: UARTDataBits = .eight,
    parity: UARTParity = .none,
    stopBits: UARTStopBits = .one,
    flowControl: UARTFlowControl = .none
  ) {
    self.baudRate = baudRate
    self.dataBits = dataBits
    self.parity = parity
    self.stopBits = stopBits
    self.flowControl = flowControl
  }
}

public struct UARTStatistics: Sendable, Equatable {
  public let rxOverflow: UInt64
  public let framingErrors: UInt64
  public let parityErrors: UInt64

  public init(rxOverflow: UInt64 = 0, framingErrors: UInt64 = 0, parityErrors: UInt64 = 0) {
    self.rxOverflow = rxOverflow
    self.framingErrors = framingErrors
    self.parityErrors = parityErrors
  }
}

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
  public let tx: PicoPin
  public let rx: PicoPin
  public let configuration: UARTConfiguration
  private let dmaOwnerToken: UInt32
  private let ownerToken: UInt32
  private var isClosed = false
  /// The baud rate actually selected by the SDK.
  public let actualBaudRate: Frequency

  deinit { close() }

  public convenience init(
    _ instance: UARTInstance,
    baudRate: Frequency,
    tx: PicoPin,
    rx: PicoPin,
    dataBits: UARTDataBits = .eight,
    parity: UARTParity = .none,
    stopBits: UARTStopBits = .one,
    flowControl: UARTFlowControl = .none,
    chip: PicoChip = .compiled
  ) throws(PicoKitError) {
    try self.init(
      instance,
      configuration: UARTConfiguration(
        baudRate: baudRate, dataBits: dataBits, parity: parity,
        stopBits: stopBits, flowControl: flowControl
      ),
      tx: tx,
      rx: rx,
      chip: chip
    )
  }

  public init(
    _ instance: UARTInstance,
    configuration: UARTConfiguration,
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
      let ownerToken = picokit_dma_owner_token()
      var actualBaudRate: UInt32 = 0
      let status = picokit_uart_init_configured(
        instance.rawValue,
        ownerToken,
        configuration.baudRate.hertz,
        tx.rawValue,
        rx.rawValue,
        configuration.dataBits.rawValue,
        configuration.stopBits.rawValue,
        configuration.parity.rawValue,
        configuration.flowControl.rawValue,
        &actualBaudRate
      )
      if status == -3 {
        throw PicoKitError.ownershipConflict("UART instance or pins are owned by another PicoUART")
      }
      guard status == 0 else {
        throw PicoKitError.ioFailure(operation: "UART setup", status: status)
      }
      self.instance = instance
      self.chip = chip
      self.tx = tx
      self.rx = rx
      self.configuration = configuration
      self.ownerToken = ownerToken
      self.dmaOwnerToken = ownerToken
      self.actualBaudRate = try Frequency.hertz(actualBaudRate)
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  private func ensureOpen(operation: String) throws(PicoKitError) {
    guard !isClosed else { throw PicoKitError.unavailable("UART is closed: \(operation)") }
  }

  public func close() {
    guard !isClosed else { return }
    isClosed = true
    #if PICOKIT_PICO_SDK
      picokit_uart_dma_release(instance.rawValue, dmaOwnerToken)
      picokit_uart_close(instance.rawValue, ownerToken, tx.rawValue, rx.rawValue)
    #endif
  }

  public var statistics: UARTStatistics {
    guard !isClosed else { return UARTStatistics() }
    #if PICOKIT_PICO_SDK
      var overflow: UInt64 = 0
      var framing: UInt64 = 0
      var parity: UInt64 = 0
      picokit_uart_get_statistics(
        instance.rawValue, ownerToken, &overflow, &framing, &parity
      )
      return UARTStatistics(
        rxOverflow: overflow, framingErrors: framing, parityErrors: parity
      )
    #else
      return UARTStatistics()
    #endif
  }

  public func resetStatistics() throws(PicoKitError) {
    try ensureOpen(operation: "reset statistics")
    #if PICOKIT_PICO_SDK
      picokit_uart_reset_statistics(instance.rawValue, ownerToken)
    #endif
  }

  public func write(_ bytes: [UInt8], timeout: Duration) throws(PicoKitError) -> Int {
    try ensureOpen(operation: "write")
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
    try ensureOpen(operation: "DMA write")
    let count = try picoKitTransferCount(bytes.count, operation: "UART DMA write")
    #if PICOKIT_PICO_SDK
      let status = bytes.withUnsafeBufferPointer {
        picokit_uart_write_dma(instance.rawValue, dmaOwnerToken, $0.baseAddress, count)
      }
      if status == -3 {
        throw PicoKitError.ownershipConflict("UART DMA is owned by another PicoUART")
      }
      guard status == Int32(count) else {
        throw PicoKitError.ioFailure(operation: "UART DMA write", status: status)
      }
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  /// Writes a prepared buffer through DMA with a bounded wait for the DMA
  /// channel to finish. A timeout aborts the channel before this method returns.
  public func writeDMA(_ bytes: [UInt8], timeout: Duration) throws(PicoKitError) {
    try ensureOpen(operation: "DMA write")
    let count = try picoKitTransferCount(bytes.count, operation: "UART DMA write")
    #if PICOKIT_PICO_SDK
      let status = bytes.withUnsafeBufferPointer {
        picokit_uart_write_dma_timeout(
          instance.rawValue, dmaOwnerToken, $0.baseAddress, count, timeout.microseconds)
      }
      if status == -2 { throw PicoKitError.timedOut(operation: "UART DMA write") }
      if status == -3 {
        throw PicoKitError.ownershipConflict("UART DMA is owned by another PicoUART")
      }
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

  public func releaseDMAChannel() {
    guard !isClosed else { return }
    #if PICOKIT_PICO_SDK
      picokit_uart_dma_release(instance.rawValue, dmaOwnerToken)
    #endif
  }

  /// Returns all bytes currently waiting in the RX FIFO, up to `count`.
  public func read(upToCount count: Int) throws(PicoKitError) -> [UInt8] {
    try ensureOpen(operation: "read")
    let transferCount = try picoKitTransferCount(count, operation: "UART read")
    guard transferCount != 0 else { return [] }
    #if PICOKIT_PICO_SDK
      var received = [UInt8](repeating: 0, count: count)
      let status = received.withUnsafeMutableBufferPointer {
        picokit_uart_read_bytes(instance.rawValue, ownerToken, $0.baseAddress, transferCount, 0)
      }
      if status == -3 {
        throw PicoKitError.ownershipConflict("UART is owned by another PicoUART")
      }
      guard status >= 0 else {
        throw PicoKitError.ioFailure(operation: "UART read", status: status)
      }
      return Array(received.prefix(Int(status)))
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  /// Reads exactly `count` bytes, applying the timeout to the complete read.
  public func read(count: Int, timeout: Duration) throws(PicoKitError) -> [UInt8] {
    try ensureOpen(operation: "read")
    let transferCount = try picoKitTransferCount(count, operation: "UART read")
    guard transferCount != 0 else { return [] }
    #if PICOKIT_PICO_SDK
      var received = [UInt8](repeating: 0, count: count)
      let status = received.withUnsafeMutableBufferPointer {
        picokit_uart_read_bytes(
          instance.rawValue, ownerToken, $0.baseAddress, transferCount, timeout.microseconds)
      }
      if status == -2 { throw PicoKitError.timedOut(operation: "UART read") }
      if status == -3 {
        throw PicoKitError.ownershipConflict("UART is owned by another PicoUART")
      }
      if status >= 0 && status != Int32(count) {
        throw PicoKitError.partialTransfer(
          operation: "UART read", transferred: Int(status), expected: count
        )
      }
      guard status == Int32(count) else {
        throw PicoKitError.ioFailure(operation: "UART read", status: status)
      }
      return received
    #else
      throw PicoKitError.unavailable("Pico SDK bridge")
    #endif
  }

  public func read() throws(PicoKitError) -> UInt8? {
    try read(upToCount: 1).first
  }

  public func read(timeout: Duration) throws(PicoKitError) -> UInt8 {
    try read(count: 1, timeout: timeout)[0]
  }
}
