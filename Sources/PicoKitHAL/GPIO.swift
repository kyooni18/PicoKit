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

    public func setMode(_ pin: PicoPin, mode: PinMode) throws {
        #if PICOKIT_PICO_SDK
        picokit_gpio_init(pin.rawValue)
        picokit_gpio_set_direction(pin.rawValue, mode == .output ? 1 : 0)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func write(_ pin: PicoPin, state: PinState) throws {
        #if PICOKIT_PICO_SDK
        picokit_gpio_write(pin.rawValue, state == .high ? 1 : 0)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func read(_ pin: PicoPin) throws -> PinState {
        #if PICOKIT_PICO_SDK
        return picokit_gpio_read(pin.rawValue) == 0 ? .low : .high
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func toggle(_ pin: PicoPin) throws {
        #if PICOKIT_PICO_SDK
        picokit_gpio_toggle(pin.rawValue)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func pinMode(_ pin: Int, _ mode: PinMode) throws {
        try setMode(PicoPin(pin), mode: mode)
    }

    public func digitalWrite(_ pin: Int, _ state: PinState) throws {
        try write(PicoPin(pin), state: state)
    }

    public func digitalRead(_ pin: Int) throws -> PinState {
        try read(PicoPin(pin))
    }

    public func digitalToggle(_ pin: Int) throws {
        try toggle(PicoPin(pin))
    }
}

public final class BoardLED {
    public init(board: PicoBoard) throws {
        #if PICOKIT_PICO_SDK
        guard picokit_status_led_init() == 0 else {
            throw PicoKitError.unavailable("board status LED")
        }
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func set(_ state: PinState) throws {
        #if PICOKIT_PICO_SDK
        picokit_status_led_write(state == .high ? 1 : 0)
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }

    public func toggle() throws {
        #if PICOKIT_PICO_SDK
        picokit_status_led_toggle()
        #else
        throw PicoKitError.unavailable("Pico SDK bridge")
        #endif
    }
}

