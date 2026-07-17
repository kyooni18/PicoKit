import PicoKit

/// Embedded Swift entry point. The application uses the PicoKit Swift library;
/// its Pico SDK bridge is linked by Firmware/CMakeLists.txt.
@main
struct Blink {
  static func main() {
    do {
      let serial = try USBSerial()
      let led = try BoardLED()
      let halfSecond = try Duration.milliseconds(500)
      while true {
        try led.set(.high)
        try serial.write("LED on")
        try Clock.sleep(for: halfSecond)
        try led.set(.low)
        try serial.write("LED off")
        try Clock.sleep(for: halfSecond)
      }
    } catch {
      // There is no dependable console until stdio initialization has
      // succeeded, so leave the board in a safe idle state.
      while true {}
    }
  }
}
