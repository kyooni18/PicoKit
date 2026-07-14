#if !PICOKIT_PICO_SDK
import PicoKitCore
#endif

public enum PWMChannel: Sendable { case a, b }

public final class PicoPWM {
    public let pin: PicoPin

    public init(pin: PicoPin, frequency: Frequency) throws(PicoKitError) {
        #if PICOKIT_PICO_SDK
        let status = picokit_pwm_init(pin.rawValue, frequency.hertz)
        guard status == 0 else {
            throw PicoKitError.ioFailure(operation: "PWM setup", status: status)
        }
        self.pin = pin
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func setDutyCycle(_ fraction: UInt16) throws(PicoKitError) {
        #if PICOKIT_PICO_SDK
        picokit_pwm_set_level(pin.rawValue, fraction)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func analogWrite(_ duty: UInt8) throws(PicoKitError) { try setDutyCycle(UInt16(duty) * 257) }
    public func analogWrite(_ duty: UInt16) throws(PicoKitError) { try setDutyCycle(duty) }
}

/// PWM-backed display backlight with explicit active-high/active-low polarity.
public final class PicoBacklight {
    private let pwm: PicoPWM
    private let activeHigh: Bool

    public init(pin: PicoPin, frequency: Frequency = try! .kilohertz(20), activeHigh: Bool = true) throws(PicoKitError) {
        self.pwm = try PicoPWM(pin: pin, frequency: frequency)
        self.activeHigh = activeHigh
        try setBrightness(0 as UInt16)
    }

    public func setBrightness(_ value: UInt16) throws(PicoKitError) {
        try pwm.setDutyCycle(activeHigh ? value : UInt16.max - value)
    }

    public func setBrightness(_ value: UInt8) throws(PicoKitError) {
        try setBrightness(UInt16(value) * 257)
    }

    public func off() throws(PicoKitError) { try setBrightness(0 as UInt16) }
    public func fullOn() throws(PicoKitError) { try setBrightness(UInt16.max) }
}

@inlinable
public func analogWrite(_ pin: Int, _ duty: UInt8, using pwm: PicoPWM) throws(PicoKitError) {
    let validated = try PicoPin(pin)
    guard validated == pwm.pin else {
        throw PicoKitError.ownershipConflict("PWM is configured for \(pwm.pin), not \(validated)")
    }
    try pwm.analogWrite(duty)
}

@inlinable
public func analogWrite(_ pin: Int, _ duty: UInt16, using pwm: PicoPWM) throws(PicoKitError) {
    let validated = try PicoPin(pin)
    guard validated == pwm.pin else {
        throw PicoKitError.ownershipConflict("PWM is configured for \(pwm.pin), not \(validated)")
    }
    try pwm.analogWrite(duty)
}

public enum ADCChannel: UInt32, CaseIterable, Sendable {
    case gpio26, gpio27, gpio28, gpio29, temperature
}

public final class PicoADC {
    public init() throws(PicoKitError) {
        #if PICOKIT_PICO_SDK
        picokit_adc_init()
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func read(_ channel: ADCChannel) throws(PicoKitError) -> UInt16 {
        #if PICOKIT_PICO_SDK
        let value = picokit_adc_read(channel.rawValue)
        guard value >= 0 else {
            throw PicoKitError.ioFailure(operation: "ADC read", status: value)
        }
        return UInt16(value)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
}

@inlinable
public func analogRead(_ channel: ADCChannel, using adc: PicoADC) throws(PicoKitError) -> UInt16 {
    try adc.read(channel)
}

public func analogRead(_ pin: Int, using adc: PicoADC) throws(PicoKitError) -> UInt16 {
    let channel: ADCChannel
    switch pin {
    case 26: channel = .gpio26
    case 27: channel = .gpio27
    case 28: channel = .gpio28
    case 29: channel = .gpio29
    default: throw PicoKitError.unavailable("ADC is only available on GPIO26...GPIO29")
    }
    return try adc.read(channel)
}
