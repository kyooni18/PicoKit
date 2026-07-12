#include "PicoKitSDKBridge.h"

#include "hardware/adc.h"
#include "hardware/clocks.h"
#include "hardware/gpio.h"
#include "hardware/i2c.h"
#include "hardware/pwm.h"
#include "hardware/spi.h"
#include "hardware/uart.h"
#include "hardware/watchdog.h"
#include "pico/stdlib.h"
#include "pico/status_led.h"

static volatile uint32_t picokit_interrupt_events[30];

static void picokit_gpio_irq(uint gpio, uint32_t events) {
    if (gpio < 30) picokit_interrupt_events[gpio] |= events;
}

void picokit_stdio_init(void) { stdio_init_all(); }
void picokit_stdio_write(const char *text) { stdio_puts(text); }
static bool picokit_expired(uint64_t deadline) { return time_us_64() >= deadline; }
static uart_inst_t *picokit_uart(uint32_t instance) { return instance == 0 ? uart0 : instance == 1 ? uart1 : NULL; }
int32_t picokit_uart_init(uint32_t instance, uint32_t baud_rate, uint32_t tx, uint32_t rx) {
    uart_inst_t *uart = picokit_uart(instance);
    if (!uart || !baud_rate) return -1;
    uart_init(uart, baud_rate);
    gpio_set_function(tx, GPIO_FUNC_UART);
    gpio_set_function(rx, GPIO_FUNC_UART);
    return 0;
}
int32_t picokit_uart_write(uint32_t instance, const uint8_t *bytes, uint32_t count, uint64_t timeout_us) {
    uart_inst_t *uart = picokit_uart(instance);
    if (!uart || (!bytes && count)) return -1;
    uint64_t deadline = time_us_64() + timeout_us;
    for (uint32_t index = 0; index < count; index++) {
        while (!uart_is_writable(uart)) if (picokit_expired(deadline)) return -2;
        uart_get_hw(uart)->dr = bytes[index];
    }
    return (int32_t)count;
}
int32_t picokit_uart_read(uint32_t instance, uint8_t *byte, uint64_t timeout_us) {
    uart_inst_t *uart = picokit_uart(instance);
    if (!uart || !byte) return -1;
    uint64_t deadline = time_us_64() + timeout_us;
    while (!uart_is_readable(uart)) if (picokit_expired(deadline)) return -2;
    *byte = (uint8_t)uart_get_hw(uart)->dr;
    return 0;
}
int32_t picokit_status_led_init(void) { return status_led_init() ? 0 : -1; }
void picokit_status_led_write(uint32_t value) { status_led_set_state(value != 0); }
void picokit_status_led_toggle(void) { status_led_set_state(!status_led_get_state()); }

void picokit_gpio_init(uint32_t pin) { gpio_init(pin); }
void picokit_gpio_set_direction(uint32_t pin, uint32_t output) { gpio_set_dir(pin, output != 0); }
void picokit_gpio_write(uint32_t pin, uint32_t value) { gpio_put(pin, value != 0); }
uint32_t picokit_gpio_read(uint32_t pin) { return gpio_get(pin) ? 1u : 0u; }
void picokit_gpio_toggle(uint32_t pin) { gpio_xor_mask(1u << pin); }

uint64_t picokit_time_us(void) { return time_us_64(); }
void picokit_sleep_us(uint64_t microseconds) { sleep_us(microseconds); }

int32_t picokit_pwm_init(uint32_t pin, uint32_t frequency_hz) {
    if (!frequency_hz) return -1;
    gpio_set_function(pin, GPIO_FUNC_PWM);
    uint slice = pwm_gpio_to_slice_num(pin);
    uint32_t clock_hz = clock_get_hz(clk_sys);
    uint64_t cycle_span = (uint64_t)frequency_hz * 65536u;
    uint32_t divider = (uint32_t)(((uint64_t)clock_hz + cycle_span - 1u) / cycle_span);
    if (divider < 1) divider = 1;
    if (divider > 255) return -1;
    uint32_t wrap = clock_hz / (divider * frequency_hz);
    if (wrap < 2 || wrap > 65536) return -1;
    pwm_set_clkdiv_int_frac(slice, (uint8_t)divider, 0);
    pwm_set_wrap(slice, (uint16_t)(wrap - 1));
    pwm_set_gpio_level(pin, 0);
    pwm_set_enabled(slice, true);
    return 0;
}
void picokit_pwm_set_level(uint32_t pin, uint16_t level) {
    uint slice = pwm_gpio_to_slice_num(pin);
    uint32_t wrap = pwm_get_wrap(slice);
    uint32_t scaled = ((uint32_t)level * (wrap + 1u)) / UINT16_MAX;
    pwm_set_gpio_level(pin, scaled > wrap ? wrap : scaled);
}

void picokit_adc_init(void) { adc_init(); }
int32_t picokit_adc_read(uint32_t channel) {
    if (channel > 4) return -1;
    if (channel < 4) adc_gpio_init(26 + channel);
    adc_set_temp_sensor_enabled(channel == 4);
    adc_select_input(channel);
    return adc_read();
}

static i2c_inst_t *picokit_i2c(uint32_t instance) { return instance == 0 ? i2c0 : instance == 1 ? i2c1 : NULL; }
int32_t picokit_i2c_init(uint32_t instance, uint32_t frequency_hz, uint32_t sda, uint32_t scl) {
    i2c_inst_t *i2c = picokit_i2c(instance);
    if (!i2c || !frequency_hz) return -1;
    i2c_init(i2c, frequency_hz);
    gpio_set_function(sda, GPIO_FUNC_I2C);
    gpio_set_function(scl, GPIO_FUNC_I2C);
    gpio_pull_up(sda);
    gpio_pull_up(scl);
    return 0;
}
int32_t picokit_i2c_write(uint32_t instance, uint32_t address, const uint8_t *bytes, uint32_t count, uint64_t timeout_us) {
    i2c_inst_t *i2c = picokit_i2c(instance);
    if (!i2c || address > 0x7f || (!bytes && count) || timeout_us > UINT32_MAX) return -1;
    return i2c_write_timeout_us(i2c, (uint8_t)address, bytes, count, false, (uint32_t)timeout_us);
}
int32_t picokit_i2c_read(uint32_t instance, uint32_t address, uint8_t *bytes, uint32_t count, uint64_t timeout_us) {
    i2c_inst_t *i2c = picokit_i2c(instance);
    if (!i2c || address > 0x7f || (!bytes && count) || timeout_us > UINT32_MAX) return -1;
    return i2c_read_timeout_us(i2c, (uint8_t)address, bytes, count, false, (uint32_t)timeout_us);
}

static spi_inst_t *picokit_spi(uint32_t instance) { return instance == 0 ? spi0 : instance == 1 ? spi1 : NULL; }
int32_t picokit_spi_init(uint32_t instance, uint32_t frequency_hz, uint32_t sck, uint32_t mosi, uint32_t miso) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi || !frequency_hz) return -1;
    spi_init(spi, frequency_hz);
    gpio_set_function(sck, GPIO_FUNC_SPI);
    gpio_set_function(mosi, GPIO_FUNC_SPI);
    gpio_set_function(miso, GPIO_FUNC_SPI);
    return 0;
}
int32_t picokit_spi_transfer(uint32_t instance, const uint8_t *tx, uint8_t *rx, uint32_t count, uint64_t timeout_us) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi || (!tx && count) || (!rx && count)) return -1;
    uint64_t deadline = time_us_64() + timeout_us;
    for (uint32_t index = 0; index < count; index++) {
        while (!spi_is_writable(spi)) if (picokit_expired(deadline)) return -2;
        spi_get_hw(spi)->dr = tx[index];
        while (!spi_is_readable(spi)) if (picokit_expired(deadline)) return -2;
        rx[index] = (uint8_t)spi_get_hw(spi)->dr;
    }
    return (int32_t)count;
}

int32_t picokit_interrupt_enable(uint32_t pin, uint32_t edge) {
    if (pin >= 30 || edge < 1 || edge > 3) return -1;
    uint32_t events = edge == 1 ? GPIO_IRQ_EDGE_RISE : edge == 2 ? GPIO_IRQ_EDGE_FALL : GPIO_IRQ_EDGE_RISE | GPIO_IRQ_EDGE_FALL;
    gpio_set_irq_enabled_with_callback(pin, events, true, &picokit_gpio_irq);
    return 0;
}
uint32_t picokit_interrupt_take(uint32_t pin) {
    if (pin >= 30) return 0;
    uint32_t events = picokit_interrupt_events[pin];
    picokit_interrupt_events[pin] = 0;
    return events;
}

void picokit_watchdog_enable(uint32_t timeout_ms, uint32_t pause_on_debug) { watchdog_enable(timeout_ms, pause_on_debug != 0); }
void picokit_watchdog_update(void) { watchdog_update(); }
