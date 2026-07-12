/// Button and input utilities — debounced digital reading and edge detection.

public struct ButtonConfig: Hashable, Sendable {
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

public final class Button: @unchecked Sendable {
    public let config: ButtonConfig
    private let gpio: PicoGPIO
    private var stableState: PinState
    private var rawState: PinState
    private var lastChangeTime: UInt64 = 0

    public init(_ config: ButtonConfig, using gpio: PicoGPIO) {
        self.config = config
        self.gpio = gpio
        gpio.pinMode(config.pin, .input)
        let initialState = gpio.digitalRead(config.pin)
        stableState = initialState
        rawState = initialState
        lastChangeTime = millis()
    }

    private func update() -> PinState {
        let raw = gpio.digitalRead(config.pin)
        let now = millis()

        if raw != rawState {
            rawState = raw
            lastChangeTime = now
        }
        if rawState != stableState, now - lastChangeTime >= config.debounceMs {
            stableState = rawState
        }
        return stableState
    }

    /// Read the debounced button state.
    /// Returns `.high` if the button is currently pressed (active).
    public func read() -> PinState {
        update() == config.activeState ? .high : .low
    }

    /// Whether the button is currently pressed.
    public var isPressed: Bool {
        read().isHigh
    }

    /// Check for a debounced transition into the pressed state.
    @discardableResult
    public func wasPressed() -> Bool {
        let previous = stableState
        return update() == config.activeState && previous != config.activeState
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
public final class EdgeDetector: @unchecked Sendable {
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
