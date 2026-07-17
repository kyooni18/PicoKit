import PicoKit

/// Compile-and-link coverage for every operation-level GPIO facade entry point.
/// The firmware matrix builds this source for both MCU families; hardware tests
/// may also flash it to exercise the same public Swift API.
@main
struct GPIOFacadeProbe {
  static func main() {
    do {
      let gpio = PicoGPIO.compiled
      let pin = PicoPin.gpio2
      try gpio.setMode(pin, mode: .output)
      try gpio.configure(
        pin,
        mode: .output,
        initialState: .low,
        pull: .none,
        driveStrength: .milliamps4,
        slewRate: .slow
      )
      try gpio.write(pin, state: .high)
      _ = try gpio.read(pin)
      try gpio.toggle(pin)

      let mask = UInt32(1) << pin.rawValue
      try gpio.set(mask: mask)
      try gpio.clear(mask: mask)
      try gpio.toggle(mask: mask)
      try gpio.resetPulse(pin, duration: .microseconds(1))

      // The nonthrowing sketch API must remain a convenience layer over the
      // same PicoGPIO instance rather than a second SDK bridge path.
      let pico = Pico()
      pico.pinMode(Int(pin.rawValue), .output)
      pico.digitalWrite(Int(pin.rawValue), .low)
      _ = pico.digitalRead(Int(pin.rawValue))
      pico.digitalToggle(Int(pin.rawValue))
    } catch {
      while true {}
    }

    while true {}
  }
}
