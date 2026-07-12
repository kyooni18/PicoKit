import PicoKit

private final class FakeGPIO: DigitalIO {
    var modes: [(PicoPin, PinMode)] = []
    var writes: [(PicoPin, PinState)] = []
    var state: PinState = .low
    func setMode(_ pin: PicoPin, mode: PinMode) throws { modes.append((pin, mode)) }
    func write(_ pin: PicoPin, state: PinState) throws { writes.append((pin, state)); self.state = state }
    func read(_ pin: PicoPin) throws -> PinState { state }
}

@main
struct PicoKitHostTests {
    static func main() {
        do {
            guard PicoBoard(configurationName: "pico-w") == .picoW,
                  PicoBoard.pico2W.cmakeName == "pico2_w",
                  try PicoPin(29).rawValue == 29,
                  try Frequency.kilohertz(400).hertz == 400_000,
                  try Duration.milliseconds(10).microseconds == 10_000
            else { fatalError("PicoKit core validation failed") }
            do {
                _ = try PicoPin(30)
                fatalError("invalid GPIO pin accepted")
            } catch PicoKitError.invalidPin(30) {}
            catch { fatalError("wrong validation error: \(error)") }
            let fake = FakeGPIO()
            try pinMode(4, .output, using: fake)
            try digitalWrite(4, .high, using: fake)
            guard fake.modes.count == 1, fake.writes.count == 1,
                  try digitalRead(4, using: fake) == .high
            else { fatalError("Arduino-style GPIO helpers failed") }
            do {
                try pinMode(30, .output, using: fake)
                fatalError("pinMode accepted an invalid pin")
            } catch PicoKitError.invalidPin(30) {}
            catch { fatalError("wrong pinMode error: \(error)") }

            let sketch = Pico(gpio: fake)
            sketch.pinMode(7, .output)
            sketch.digitalWrite(7, .high)
            guard sketch.digitalRead(7) == .high else {
                fatalError("non-throwing Pico facade failed")
            }

            // Keep the shortest global spelling in the compile surface too.
            let _: (Int, PinMode) -> Void = pinMode
            let _: (Int, PinState) -> Void = digitalWrite
            let _: (UInt64) -> Void = sleep
            let _: PicoSerial = Serial
            print("PicoKit host validation passed")
        } catch {
            fatalError("PicoKit host validation failed: \(error)")
        }
    }
}
