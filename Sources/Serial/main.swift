import PicoKit

/// USB CDC echo test for a Pico 2 W.
@main
struct SerialExample {
  static func main() {
    var announced = false
    while true {
      if !Serial.connected {
        announced = false
        sleep(10)
      } else if !announced {
        Serial.println("PicoKit serial echo: ready")
        announced = true
      } else if let byte = Serial.read() {
        if byte == 0x0A {
          Serial.println()
        } else {
          Serial.write(byte)
        }
      } else {
        sleepMicroseconds(100)
      }
    }
  }
}
