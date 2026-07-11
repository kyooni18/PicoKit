#pragma once

#include <stdint.h>

void picokit_stdio_init(void);
int picokit_status_led_init(void);
void picokit_status_led_write(uint32_t value);
void picokit_gpio_init(uint32_t pin);
void picokit_gpio_set_output(uint32_t pin);
void picokit_gpio_write(uint32_t pin, uint32_t value);
void picokit_sleep_ms(uint32_t milliseconds);
