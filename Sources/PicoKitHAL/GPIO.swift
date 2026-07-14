#if !PICOKIT_PICO_SDK
import PicoKitCore
#endif

/// SDK-backed hardware access. The implementation is compiled only by the
/// Pico firmware CMake target. Host tests can exercise validation via fakes.
public final class PicoGPIO: DigitalIO {
    public static var rp2040: PicoGPIO { PicoGPIO(chip: .rp2040) }
    public static var rp2350: PicoGPIO { PicoGPIO(chip: .rp2350) }

    public let chip: PicoChip

    public init(chip: PicoChip = .rp2040) {
        self.chip = chip
    }

    public func setMode(_ pin: PicoPin, mode: PinMode) throws(PicoKitError) {
        #if PICOKIT_PICO_SDK
        picokit_gpio_init(pin.rawValue)
        picokit_gpio_set_direction(pin.rawValue, mode == .output ? 1 : 0)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func configure(
        _ pin: PicoPin,
        mode: PinMode,
        initialState: PinState = .low,
        pull: PinPull = .none,
        driveStrength: PinDriveStrength = .milliamps4,
        slewRate: PinSlewRate = .slow
    ) throws(PicoKitError) {
        #if PICOKIT_PICO_SDK
        let status = picokit_gpio_configure(
            pin.rawValue,
            mode == .output ? 1 : 0,
            initialState == .high ? 1 : 0,
            pull.rawValue,
            driveStrength.rawValue,
            slewRate.rawValue
        )
        guard status == 0 else {
            throw PicoKitError.ioFailure(operation: "GPIO setup", status: status)
        }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func resetPulse(
        _ pin: PicoPin,
        activeState: PinState = .low,
        duration: Duration
    ) throws(PicoKitError) {
        try configure(pin, mode: .output, initialState: activeState.toggled)
        try write(pin, state: activeState)
        #if PICOKIT_PICO_SDK
        picokit_sleep_us(duration.microseconds)
        try write(pin, state: activeState.toggled)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func write(_ pin: PicoPin, state: PinState) throws(PicoKitError) {
        #if PICOKIT_PICO_SDK
        picokit_gpio_write(pin.rawValue, state == .high ? 1 : 0)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func read(_ pin: PicoPin) throws(PicoKitError) -> PinState {
        #if PICOKIT_PICO_SDK
        return picokit_gpio_read(pin.rawValue) == 0 ? .low : .high
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func toggle(_ pin: PicoPin) throws(PicoKitError) {
        #if PICOKIT_PICO_SDK
        picokit_gpio_toggle(pin.rawValue)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func pinMode(_ pin: Int, _ mode: PinMode) throws(PicoKitError) {
        try setMode(PicoPin(pin), mode: mode)
    }

    public func digitalWrite(_ pin: Int, _ state: PinState) throws(PicoKitError) {
        try write(PicoPin(pin), state: state)
    }

    public func digitalRead(_ pin: Int) throws(PicoKitError) -> PinState {
        try read(PicoPin(pin))
    }

    public func digitalToggle(_ pin: Int) throws(PicoKitError) {
        try toggle(PicoPin(pin))
    }
}

public final class BoardLED {
    public init(board: PicoBoard) throws(PicoKitError) {
        #if PICOKIT_PICO_SDK
        guard picokit_status_led_init() == 0 else {
            throw PicoKitError.unavailable("board status LED")
        }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func set(_ state: PinState) throws(PicoKitError) {
        #if PICOKIT_PICO_SDK
        picokit_status_led_write(state == .high ? 1 : 0)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func toggle() throws(PicoKitError) {
        #if PICOKIT_PICO_SDK
        picokit_status_led_toggle()
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
}
