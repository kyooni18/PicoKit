#include "PicoKitSDKBridge.h"

#include <stdbool.h>

#include "hardware/gpio.h"
#include "pico/stdlib.h"

// PicoKit deliberately exposes GPIO0...GPIO29, including on RP2350 boards
// with additional GPIO. Keep the fast mask API inside that public range.
#define PICOKIT_GPIO_COUNT 30u
#define PICOKIT_GPIO_MASK ((1u << PICOKIT_GPIO_COUNT) - 1u)

#ifndef PICOKIT_GPIO_COMPILED_CHIP
#if defined(PICO_RP2040)
#define PICOKIT_GPIO_COMPILED_CHIP 0u
#elif defined(PICO_RP2350)
#define PICOKIT_GPIO_COMPILED_CHIP 1u
#else
#error "PicoKit GPIO facade requires a compiled Pico chip"
#endif
#endif

static bool picokit_gpio_valid_pin(uint32_t pin) { return pin < PICOKIT_GPIO_COUNT; }

static int32_t picokit_gpio_validate(uint32_t chip, uint32_t pin) {
    if (chip != PICOKIT_GPIO_COMPILED_CHIP) return PICOKIT_GPIO_STATUS_CHIP_MISMATCH;
    return picokit_gpio_valid_pin(pin)
        ? PICOKIT_GPIO_STATUS_OK
        : PICOKIT_GPIO_STATUS_INVALID_ARGUMENT;
}

int32_t picokit_gpio_set_mode(uint32_t chip, uint32_t pin, uint32_t output) {
    int32_t status = picokit_gpio_validate(chip, pin);
    if (status) return status;
    if (output > 1) return PICOKIT_GPIO_STATUS_INVALID_ARGUMENT;
    gpio_init(pin);
    gpio_set_dir(pin, output != 0);
    return PICOKIT_GPIO_STATUS_OK;
}

int32_t picokit_gpio_write(uint32_t chip, uint32_t pin, uint32_t value) {
    int32_t status = picokit_gpio_validate(chip, pin);
    if (status) return status;
    if (value > 1) return PICOKIT_GPIO_STATUS_INVALID_ARGUMENT;
    gpio_put(pin, value != 0);
    return PICOKIT_GPIO_STATUS_OK;
}

int32_t picokit_gpio_read(uint32_t chip, uint32_t pin, uint32_t *value) {
    int32_t status = picokit_gpio_validate(chip, pin);
    if (status) return status;
    if (!value) return PICOKIT_GPIO_STATUS_INVALID_ARGUMENT;
    *value = gpio_get(pin) ? 1u : 0u;
    return PICOKIT_GPIO_STATUS_OK;
}

int32_t picokit_gpio_toggle(uint32_t chip, uint32_t pin) {
    int32_t status = picokit_gpio_validate(chip, pin);
    if (status) return status;
    gpio_xor_mask(1u << pin);
    return PICOKIT_GPIO_STATUS_OK;
}

int32_t picokit_gpio_set_mask(uint32_t chip, uint32_t mask) {
    if (chip != PICOKIT_GPIO_COMPILED_CHIP) return PICOKIT_GPIO_STATUS_CHIP_MISMATCH;
    gpio_set_mask(mask & PICOKIT_GPIO_MASK);
    return PICOKIT_GPIO_STATUS_OK;
}

int32_t picokit_gpio_clear_mask(uint32_t chip, uint32_t mask) {
    if (chip != PICOKIT_GPIO_COMPILED_CHIP) return PICOKIT_GPIO_STATUS_CHIP_MISMATCH;
    gpio_clr_mask(mask & PICOKIT_GPIO_MASK);
    return PICOKIT_GPIO_STATUS_OK;
}

int32_t picokit_gpio_toggle_mask(uint32_t chip, uint32_t mask) {
    if (chip != PICOKIT_GPIO_COMPILED_CHIP) return PICOKIT_GPIO_STATUS_CHIP_MISMATCH;
    gpio_xor_mask(mask & PICOKIT_GPIO_MASK);
    return PICOKIT_GPIO_STATUS_OK;
}

int32_t picokit_gpio_configure(uint32_t chip, uint32_t pin, uint32_t output,
                               uint32_t initial_value, uint32_t pull, uint32_t drive,
                               uint32_t slew) {
    int32_t status = picokit_gpio_validate(chip, pin);
    if (status) return status;
    if (output > 1 || initial_value > 1 || pull > 2 || drive > 3 || slew > 1) {
        return PICOKIT_GPIO_STATUS_INVALID_ARGUMENT;
    }
    gpio_init(pin);
    // Program the output latch before enabling output to prevent a transient
    // opposite level on reset, chip-select, and backlight pins.
    gpio_put(pin, initial_value != 0);
    gpio_set_pulls(pin, pull == 1, pull == 2);
    gpio_set_drive_strength(pin, (enum gpio_drive_strength)drive);
    gpio_set_slew_rate(pin, (enum gpio_slew_rate)slew);
    gpio_set_dir(pin, output != 0);
    return PICOKIT_GPIO_STATUS_OK;
}

int32_t picokit_gpio_reset_pulse(uint32_t chip, uint32_t pin, uint32_t active_value,
                                 uint64_t duration_us) {
    if (active_value > 1 || !duration_us) return PICOKIT_GPIO_STATUS_INVALID_ARGUMENT;
    int32_t status = picokit_gpio_configure(
        chip, pin, 1, active_value ? 0u : 1u, 0,
        GPIO_DRIVE_STRENGTH_4MA, GPIO_SLEW_RATE_SLOW
    );
    if (status) return status;
    gpio_put(pin, active_value != 0);
    sleep_us(duration_us);
    gpio_put(pin, active_value == 0);
    return PICOKIT_GPIO_STATUS_OK;
}
