import PicoKit

/// USB CDC echo test for a Pico 2 W.
@main
struct SerialExample {
    static func main() {
        Serial.println("PicoKit serial echo: ready")

        while true {
            if let byte = Serial.read() {
                if byte == 0x0A {
                    Serial.println()
                } else {
                    Serial.write(byte)
                }
            }
        }
    }
}
