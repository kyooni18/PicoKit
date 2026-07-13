#if !PICOKIT_PICO_SDK
import PicoKitCore
#endif

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

