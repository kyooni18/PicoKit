#if !PICOKIT_PICO_SDK
import PicoKitCore
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
        guard timeout.microseconds <= UInt64(UInt32.max) * 1_000 else {
            throw PicoKitError.invalidTimeout(timeout.microseconds)
        }
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
