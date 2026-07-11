/// Embedded Swift entry point for the Raspberry Pi Pico 2 W.
///
/// The Pico SDK C shim is intentional: it selects the board-native status LED
/// (CYW43 GPIO 0 on Pico 2 W) and keeps SDK inline register helpers on the C
/// side, where they compile correctly for RP2350.
@main
struct Blink {
    static func main() {
        picokit_stdio_init()
        guard picokit_status_led_init() == 0 else {
            while true {}
        }

        while true {
            picokit_status_led_write(1)
            picokit_sleep_ms(500)
            picokit_status_led_write(0)
            picokit_sleep_ms(500)
        }
    }
}
