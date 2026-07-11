/// Button and input utilities — debounced digital reading and edge detection.

public struct ButtonConfig: Sendable {
    /// GPIO pin the button is connected to.
    public var pin: Int
    /// Active state: `.low` for pull-up buttons, `.high` for pull-down.
    public var activeState: PinState
    /// Debounce time in milliseconds.
    public var debounceMs: UInt32

    public init(pin: Int, activeState: PinState = .low, debounceMs: UInt32 = 50) {
        self.pin = pin
        self.activeState = activeState
        self.debounceMs = debounceMs
    }
}

public final class Button {
    private let config: ButtonConfig
    private let gpio: PicoGPIO
    private var lastState: PinState = .low
    private var lastChangeTime: UInt64 = 0

    public init(_ config: ButtonConfig, using gpio: PicoGPIO) {
        self.config = config
        self.gpio = gpio
        gpio.pinMode(config.pin, .input)
        lastChangeTime = millis()
    }

    /// Read the debounced button state.
    /// Returns `.high` if the button is currently pressed (active).
    public func read() -> PinState {
        let raw = gpio.digitalRead(config.pin)
        let now = millis()

        if raw != lastState {
            if now - lastChangeTime >= config.debounceMs {
                lastState = raw
                lastChangeTime = now
            }
        }

        return lastState == config.activeState ? .high : .low
    }

    /// Check if the button was just pressed (rising edge detection with debounce).
    @discardableResult
    public func wasPressed() -> Bool {
        let current = read()
        if current == .high {
            let now = millis()
            if now - lastChangeTime < 200 {
                return true
            }
        }
        return false
    }

    /// Wait until the button is pressed (blocking).
    public func waitForPress() {
        while read() != .high {}
    }

    /// Wait until the button is released (blocking).
    public func waitForRelease() {
        while read() == .high {}
    }
}

/// Convenience: check if a pin has gone high since last call.
public final class EdgeDetector {
    private var lastValue: Bool = false

    public init() {}

    /// Detect rising edge (false → true transition).
    public func risingEdge(current: Bool) -> Bool {
        let edge = current && !lastValue
        lastValue = current
        return edge
    }

    /// Detect falling edge (true → false transition).
    public func fallingEdge(current: Bool) -> Bool {
        let edge = !current && lastValue
        lastValue = current
        return edge
    }

    /// Detect either edge.
    public func anyEdge(current: Bool) -> Bool {
        let edge = current != lastValue
        lastValue = current
        return edge
    }

    /// Reset state.
    public func reset() {
        lastValue = false
    }
}
