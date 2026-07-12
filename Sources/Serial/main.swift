import PicoKit

/// Minimal USB serial smoke test for a Pico 2 W.
@main
struct SerialExample {
    static func main() {
        Serial.println("PicoKit Serial example: ready")

        var count = 0
        while true {
            Serial.println("serial heartbeat \(count)")
            count += 1
            sleep(1_000)
        }
    }
}
