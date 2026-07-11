#include "pico/stdlib.h"
#include "pico/status_led.h"

// Keep Pico SDK inline functions on the C side. The current Embedded Swift
// importer can otherwise lower some RP2350 memory-mapped GPIO helpers as ARM
// coprocessor instructions, which do not run on Cortex-M33.
void picokit_stdio_init(void) {
    stdio_init_all();
}

int picokit_status_led_init(void) {
    return status_led_init() ? 0 : -1;
}

void picokit_status_led_write(uint32_t value) {
    status_led_set_state(value != 0);
}

void picokit_gpio_init(uint32_t pin) {
    gpio_init(pin);
}

void picokit_gpio_set_output(uint32_t pin) {
    gpio_set_dir(pin, true);
}

void picokit_gpio_write(uint32_t pin, uint32_t value) {
    gpio_put(pin, value != 0);
}

void picokit_sleep_ms(uint32_t milliseconds) {
    sleep_ms(milliseconds);
}
