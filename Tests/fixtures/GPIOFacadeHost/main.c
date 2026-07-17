#include "PicoKitSDKBridge.h"
#include "hardware/gpio.h"
#include "pico/stdlib.h"

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

enum action {
    ACTION_INIT,
    ACTION_DIRECTION,
    ACTION_WRITE,
    ACTION_READ,
    ACTION_TOGGLE_MASK,
    ACTION_SET_MASK,
    ACTION_CLEAR_MASK,
    ACTION_PULLS,
    ACTION_DRIVE,
    ACTION_SLEW,
    ACTION_SLEEP,
};

struct event {
    enum action action;
    uint64_t first;
    uint64_t second;
};

static struct event events[32];
static uint32_t event_count;
static bool input_value;

static void record(enum action action, uint64_t first, uint64_t second) {
    assert(event_count < sizeof(events) / sizeof(events[0]));
    events[event_count++] = (struct event){action, first, second};
}

static void reset_events(void) { event_count = 0; }

static void expect(uint32_t index, enum action action, uint64_t first, uint64_t second) {
    assert(index < event_count);
    assert(events[index].action == action);
    assert(events[index].first == first);
    assert(events[index].second == second);
}

void gpio_init(uint32_t pin) { record(ACTION_INIT, pin, 0); }
void gpio_set_dir(uint32_t pin, bool output) { record(ACTION_DIRECTION, pin, output); }
void gpio_put(uint32_t pin, bool value) { record(ACTION_WRITE, pin, value); }
bool gpio_get(uint32_t pin) { record(ACTION_READ, pin, 0); return input_value; }
void gpio_xor_mask(uint32_t mask) { record(ACTION_TOGGLE_MASK, mask, 0); }
void gpio_set_mask(uint32_t mask) { record(ACTION_SET_MASK, mask, 0); }
void gpio_clr_mask(uint32_t mask) { record(ACTION_CLEAR_MASK, mask, 0); }
void gpio_set_pulls(uint32_t pin, bool up, bool down) {
    record(ACTION_PULLS, pin, (uint64_t)up | ((uint64_t)down << 1));
}
void gpio_set_drive_strength(uint32_t pin, enum gpio_drive_strength drive) {
    record(ACTION_DRIVE, pin, (uint64_t)drive);
}
void gpio_set_slew_rate(uint32_t pin, enum gpio_slew_rate slew) {
    record(ACTION_SLEW, pin, (uint64_t)slew);
}
void sleep_us(uint64_t microseconds) { record(ACTION_SLEEP, microseconds, 0); }

int main(void) {
    assert(picokit_gpio_set_mode(0, 2, 1) == PICOKIT_GPIO_STATUS_CHIP_MISMATCH);
    assert(picokit_gpio_set_mode(1, 30, 1) == PICOKIT_GPIO_STATUS_INVALID_ARGUMENT);
    assert(picokit_gpio_set_mode(1, 2, 2) == PICOKIT_GPIO_STATUS_INVALID_ARGUMENT);
    assert(event_count == 0);

    assert(picokit_gpio_set_mode(1, 2, 1) == PICOKIT_GPIO_STATUS_OK);
    assert(event_count == 2);
    expect(0, ACTION_INIT, 2, 0);
    expect(1, ACTION_DIRECTION, 2, 1);

    reset_events();
    assert(picokit_gpio_configure(1, 7, 1, 1, 1, 3, 1) == PICOKIT_GPIO_STATUS_OK);
    assert(event_count == 6);
    expect(0, ACTION_INIT, 7, 0);
    expect(1, ACTION_WRITE, 7, 1);
    expect(2, ACTION_PULLS, 7, 1);
    expect(3, ACTION_DRIVE, 7, 3);
    expect(4, ACTION_SLEW, 7, 1);
    expect(5, ACTION_DIRECTION, 7, 1);

    reset_events();
    struct rejected_configuration {
        uint32_t chip;
        uint32_t pin;
        uint32_t output;
        uint32_t initial_value;
        uint32_t pull;
        uint32_t drive;
        uint32_t slew;
        int32_t expected;
    };
    const struct rejected_configuration rejected_configurations[] = {
        {0, 7, 1, 0, 0, 0, 0, PICOKIT_GPIO_STATUS_CHIP_MISMATCH},
        {1, 30, 1, 0, 0, 0, 0, PICOKIT_GPIO_STATUS_INVALID_ARGUMENT},
        {1, 7, 2, 0, 0, 0, 0, PICOKIT_GPIO_STATUS_INVALID_ARGUMENT},
        {1, 7, 1, 2, 0, 0, 0, PICOKIT_GPIO_STATUS_INVALID_ARGUMENT},
        {1, 7, 1, 0, 3, 0, 0, PICOKIT_GPIO_STATUS_INVALID_ARGUMENT},
        {1, 7, 1, 0, 0, 4, 0, PICOKIT_GPIO_STATUS_INVALID_ARGUMENT},
        {1, 7, 1, 0, 0, 0, 2, PICOKIT_GPIO_STATUS_INVALID_ARGUMENT},
    };
    for (size_t index = 0;
         index < sizeof(rejected_configurations) / sizeof(rejected_configurations[0]);
         ++index) {
        const struct rejected_configuration *configuration = &rejected_configurations[index];
        assert(picokit_gpio_configure(
            configuration->chip, configuration->pin, configuration->output,
            configuration->initial_value, configuration->pull, configuration->drive,
            configuration->slew
        ) == configuration->expected);
        assert(event_count == 0);
    }

    assert(picokit_gpio_write(0, 5, 1) == PICOKIT_GPIO_STATUS_CHIP_MISMATCH);
    assert(picokit_gpio_write(1, 30, 1) == PICOKIT_GPIO_STATUS_INVALID_ARGUMENT);
    assert(picokit_gpio_write(1, 5, 2) == PICOKIT_GPIO_STATUS_INVALID_ARGUMENT);
    assert(event_count == 0);

    assert(picokit_gpio_write(1, 5, 1) == PICOKIT_GPIO_STATUS_OK);
    expect(0, ACTION_WRITE, 5, 1);
    reset_events();

    uint32_t value = 0;
    input_value = true;
    assert(picokit_gpio_read(1, 5, &value) == PICOKIT_GPIO_STATUS_OK);
    assert(value == 1);
    expect(0, ACTION_READ, 5, 0);
    reset_events();
    assert(picokit_gpio_read(1, 5, NULL) == PICOKIT_GPIO_STATUS_INVALID_ARGUMENT);
    assert(picokit_gpio_read(0, 5, &value) == PICOKIT_GPIO_STATUS_CHIP_MISMATCH);
    assert(picokit_gpio_read(1, 30, &value) == PICOKIT_GPIO_STATUS_INVALID_ARGUMENT);
    assert(event_count == 0);

    assert(picokit_gpio_toggle(1, 4) == PICOKIT_GPIO_STATUS_OK);
    expect(0, ACTION_TOGGLE_MASK, 1u << 4, 0);
    reset_events();
    assert(picokit_gpio_toggle(0, 4) == PICOKIT_GPIO_STATUS_CHIP_MISMATCH);
    assert(picokit_gpio_toggle(1, 30) == PICOKIT_GPIO_STATUS_INVALID_ARGUMENT);
    assert(event_count == 0);

    const uint32_t outside_public_range = 0xc0000000u;
    assert(picokit_gpio_set_mask(1, outside_public_range | 3u) == PICOKIT_GPIO_STATUS_OK);
    assert(picokit_gpio_clear_mask(1, outside_public_range | 5u) == PICOKIT_GPIO_STATUS_OK);
    assert(picokit_gpio_toggle_mask(1, outside_public_range | 9u) == PICOKIT_GPIO_STATUS_OK);
    expect(0, ACTION_SET_MASK, 3, 0);
    expect(1, ACTION_CLEAR_MASK, 5, 0);
    expect(2, ACTION_TOGGLE_MASK, 9, 0);
    reset_events();
    assert(picokit_gpio_set_mask(0, 1) == PICOKIT_GPIO_STATUS_CHIP_MISMATCH);
    assert(picokit_gpio_clear_mask(0, 1) == PICOKIT_GPIO_STATUS_CHIP_MISMATCH);
    assert(picokit_gpio_toggle_mask(0, 1) == PICOKIT_GPIO_STATUS_CHIP_MISMATCH);
    assert(event_count == 0);

    assert(picokit_gpio_reset_pulse(1, 9, 0, 25) == PICOKIT_GPIO_STATUS_OK);
    assert(event_count == 9);
    expect(0, ACTION_INIT, 9, 0);
    expect(1, ACTION_WRITE, 9, 1);
    expect(2, ACTION_PULLS, 9, 0);
    expect(3, ACTION_DRIVE, 9, GPIO_DRIVE_STRENGTH_4MA);
    expect(4, ACTION_SLEW, 9, GPIO_SLEW_RATE_SLOW);
    expect(5, ACTION_DIRECTION, 9, 1);
    expect(6, ACTION_WRITE, 9, 0);
    expect(7, ACTION_SLEEP, 25, 0);
    expect(8, ACTION_WRITE, 9, 1);
    reset_events();
    assert(picokit_gpio_reset_pulse(1, 9, 0, 0) == PICOKIT_GPIO_STATUS_INVALID_ARGUMENT);
    assert(picokit_gpio_reset_pulse(1, 9, 2, 1) == PICOKIT_GPIO_STATUS_INVALID_ARGUMENT);
    assert(picokit_gpio_reset_pulse(0, 9, 0, 1) == PICOKIT_GPIO_STATUS_CHIP_MISMATCH);
    assert(picokit_gpio_reset_pulse(1, 30, 0, 1) == PICOKIT_GPIO_STATUS_INVALID_ARGUMENT);
    assert(event_count == 0);

    puts("PicoKit GPIO facade host behavior passed");
    return 0;
}
