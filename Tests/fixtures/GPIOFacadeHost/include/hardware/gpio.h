#pragma once

#include <stdbool.h>
#include <stdint.h>

enum gpio_drive_strength {
    GPIO_DRIVE_STRENGTH_2MA = 0,
    GPIO_DRIVE_STRENGTH_4MA = 1,
    GPIO_DRIVE_STRENGTH_8MA = 2,
    GPIO_DRIVE_STRENGTH_12MA = 3,
};

enum gpio_slew_rate {
    GPIO_SLEW_RATE_SLOW = 0,
    GPIO_SLEW_RATE_FAST = 1,
};

void gpio_init(uint32_t pin);
void gpio_set_dir(uint32_t pin, bool output);
void gpio_put(uint32_t pin, bool value);
bool gpio_get(uint32_t pin);
void gpio_xor_mask(uint32_t mask);
void gpio_set_mask(uint32_t mask);
void gpio_clr_mask(uint32_t mask);
void gpio_set_pulls(uint32_t pin, bool up, bool down);
void gpio_set_drive_strength(uint32_t pin, enum gpio_drive_strength drive);
void gpio_set_slew_rate(uint32_t pin, enum gpio_slew_rate slew);
