#if !PICOKIT_PICO_SDK
import PicoKitCore
#endif

public enum UARTInstance: UInt32, Sendable { case uart0, uart1 }

public final class PicoUART {
    public let instance: UARTInstance

    public init(_ instance: UARTInstance, baudRate: Frequency, tx: PicoPin, rx: PicoPin) throws(PicoKitError) {
        #if PICOKIT_PICO_SDK
        let status = picokit_uart_init(instance.rawValue, baudRate.hertz, tx.rawValue, rx.rawValue)
        guard status == 0 else {
            throw PicoKitError.ioFailure(operation: "UART setup", status: status)
        }
        self.instance = instance
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func write(_ bytes: [UInt8], timeout: Duration) throws(PicoKitError) -> Int {
        #if PICOKIT_PICO_SDK
        let result = bytes.withUnsafeBufferPointer {
            picokit_uart_write(instance.rawValue, $0.baseAddress, UInt32($0.count), timeout.microseconds)
        }
        if result == -2 { throw PicoKitError.timedOut(operation: "UART write") }
        guard result >= 0 else {
            throw PicoKitError.ioFailure(operation: "UART write", status: result)
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
        #if PICOKIT_PICO_SDK
        let status = bytes.withUnsafeBufferPointer {
            picokit_uart_write_dma(instance.rawValue, $0.baseAddress, UInt32($0.count))
        }
        guard status == Int32(bytes.count) else {
            throw PicoKitError.ioFailure(operation: "UART DMA write", status: status)
        }
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
