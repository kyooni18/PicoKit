import PicoKit

@main
struct SerialEcho {
    static func main() {
        SplitSourceSupport.announce()
        while true {
            if let byte = Serial.read() {
                Serial.write([byte])
            }
        }
    }
}
