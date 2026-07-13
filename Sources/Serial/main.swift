import PicoKit

/// USB CDC echo test for a Pico 2 W.
@main
struct SerialExample {
    static func main() {
        Serial.println("PicoKit serial echo: ready")

        while true {
            if let byte = Serial.read() {
                Serial.write([byte])
            }
        }
    }
}
