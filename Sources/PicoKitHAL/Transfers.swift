#if !PICOKIT_PICO_SDK
import PicoKitCore
#endif

/// The bridge reports transfer counts as signed 32-bit values. Keep the Swift
/// buffer count within that representable range before crossing the C ABI.
@inline(__always)
func picoKitTransferCount(_ count: Int, operation: String) throws(PicoKitError) -> UInt32 {
    guard count >= 0 && count <= Int(Int32.max) else {
        throw PicoKitError.ioFailure(operation: operation, status: -1)
    }
    return UInt32(count)
}
