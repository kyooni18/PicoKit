#if !PICOKIT_PICO_SDK
import PicoKitCore
#else
import PicoKitSDKBridge
#endif

public enum GPIOInterruptEdge: UInt32, Sendable { case rising = 1, falling = 2, either = 3 }

/// Interrupt delivery is recorded by the C bridge and consumed in foreground code.
public final class PicoInterrupts {
    public init() {}

    public func enable(_ pin: PicoPin, edge: GPIOInterruptEdge) throws(PicoKitError) {
        #if PICOKIT_PICO_SDK
        let status = picokit_interrupt_enable(pin.rawValue, edge.rawValue)
        guard status == 0 else {
            throw PicoKitError.ioFailure(operation: "GPIO interrupt setup", status: status)
        }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    /// Disables both rising- and falling-edge delivery for `pin` and clears
    /// events recorded before the disable took effect.
    public func disable(_ pin: PicoPin) {
        #if PICOKIT_PICO_SDK
        picokit_interrupt_disable(pin.rawValue)
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

    public func enable(timeout: Duration, pauseOnDebug: Bool = true) throws(PicoKitError) {
        #if PICOKIT_PICO_SDK
        picokit_watchdog_enable(try picoKitWatchdogMilliseconds(timeout), pauseOnDebug ? 1 : 0)
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

@inline(__always)
func picoKitWatchdogMilliseconds(_ timeout: Duration) throws(PicoKitError) -> UInt32 {
    let milliseconds = timeout.microseconds / 1_000
        + (timeout.microseconds % 1_000 == 0 ? 0 : 1)
    guard milliseconds <= UInt64(UInt32.max) else {
        throw PicoKitError.invalidTimeout(timeout.microseconds)
    }
    return UInt32(milliseconds)
}
