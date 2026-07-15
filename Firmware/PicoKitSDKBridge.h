#pragma once

#include <stdint.h>

// This is PicoKit's only Pico SDK-facing header. Swift imports it only while
// compiling the PicoKit library, never application sources directly.
void picokit_stdio_init(void);
void picokit_stdio_write(const char *text);
void picokit_stdio_write_line(const char *text);
void picokit_stdio_write_bytes(const uint8_t *bytes, uint32_t count);
int32_t picokit_stdio_read(uint8_t *byte, uint64_t timeout_us);
int32_t picokit_uart_init(uint32_t instance, uint32_t baud_rate, uint32_t tx, uint32_t rx);
int32_t picokit_uart_init_with_actual_baud_rate(uint32_t instance, uint32_t baud_rate,
                                                uint32_t tx, uint32_t rx,
                                                uint32_t *actual_baud_rate);
int32_t picokit_uart_write(uint32_t instance, const uint8_t *bytes, uint32_t count, uint64_t timeout_us);
int32_t picokit_uart_read(uint32_t instance, uint8_t *byte, uint64_t timeout_us);
void picokit_uart_dma_release(uint32_t instance);
uint32_t picokit_compiled_chip(void);
uint32_t picokit_compiled_board(void);
int32_t picokit_status_led_init(void);
void picokit_status_led_write(uint32_t value);
void picokit_status_led_toggle(void);

void picokit_gpio_init(uint32_t pin);
void picokit_gpio_set_direction(uint32_t pin, uint32_t output);
void picokit_gpio_write(uint32_t pin, uint32_t value);
uint32_t picokit_gpio_read(uint32_t pin);
void picokit_gpio_toggle(uint32_t pin);
void picokit_gpio_set_mask(uint32_t mask);
void picokit_gpio_clear_mask(uint32_t mask);
void picokit_gpio_toggle_mask(uint32_t mask);
int32_t picokit_gpio_configure(uint32_t pin, uint32_t output, uint32_t initial_value,
                               uint32_t pull, uint32_t drive, uint32_t slew);

uint64_t picokit_time_us(void);
void picokit_sleep_us(uint64_t microseconds);

int32_t picokit_pwm_init(uint32_t pin, uint32_t frequency_hz, uint32_t *slice, uint32_t *channel, uint32_t *wrap);
int32_t picokit_pwm_init_with_actual_frequency(uint32_t pin, uint32_t frequency_hz,
                                                uint32_t *slice, uint32_t *channel,
                                                uint32_t *wrap, uint32_t *actual_frequency_hz);
void picokit_pwm_set_level(uint32_t slice, uint32_t channel, uint32_t wrap, uint16_t level);
void picokit_pwm_set_counter_level(uint32_t slice, uint32_t channel, uint32_t wrap, uint16_t level);

void picokit_adc_init(void);
int32_t picokit_adc_read(uint32_t channel);

int32_t picokit_i2c_init(uint32_t instance, uint32_t frequency_hz, uint32_t sda, uint32_t scl);
int32_t picokit_i2c_init_with_actual_frequency(uint32_t instance, uint32_t frequency_hz,
                                               uint32_t sda, uint32_t scl,
                                               uint32_t *actual_frequency_hz);
int32_t picokit_i2c_write(uint32_t instance, uint32_t address, const uint8_t *bytes, uint32_t count,
                          uint64_t timeout_us, uint32_t nostop);
int32_t picokit_i2c_read(uint32_t instance, uint32_t address, uint8_t *bytes, uint32_t count,
                         uint64_t timeout_us, uint32_t nostop);

int32_t picokit_spi_init(uint32_t instance, uint32_t frequency_hz, uint32_t sck, uint32_t mosi, uint32_t miso);
int32_t picokit_spi_transfer(uint32_t instance, const uint8_t *tx, uint8_t *rx, uint32_t count, uint64_t timeout_us);
int32_t picokit_spi_init_config(uint32_t instance, uint32_t frequency_hz, uint32_t sck,
                                uint32_t mosi, int32_t miso, uint32_t mode,
                                uint32_t bit_order, uint32_t data_bits,
                                uint32_t *actual_frequency_hz);
int32_t picokit_spi_write(uint32_t instance, const uint8_t *bytes, uint32_t count);
int32_t picokit_spi_read(uint32_t instance, uint8_t repeated_tx_data, uint8_t *bytes, uint32_t count);
int32_t picokit_spi_read_timeout(uint32_t instance, uint8_t repeated_tx_data, uint8_t *bytes,
                                 uint32_t count, uint64_t timeout_us);
int32_t picokit_spi_read16(uint32_t instance, uint16_t repeated_tx_word, uint16_t *words, uint32_t count);
int32_t picokit_spi_read16_timeout(uint32_t instance, uint16_t repeated_tx_word, uint16_t *words,
                                   uint32_t count, uint64_t timeout_us);
int32_t picokit_spi_write_timeout(uint32_t instance, const uint8_t *bytes, uint32_t count, uint64_t timeout_us);
int32_t picokit_spi_transfer16(uint32_t instance, const uint16_t *tx, uint16_t *rx,
                               uint32_t count, uint64_t timeout_us);
int32_t picokit_spi_write16(uint32_t instance, const uint16_t *words, uint32_t count);
int32_t picokit_spi_write16_timeout(uint32_t instance, const uint16_t *words, uint32_t count,
                                    uint64_t timeout_us);
int32_t picokit_spi_write_dma(uint32_t instance, const uint8_t *bytes, uint32_t count);
int32_t picokit_spi_write_dma_timeout(uint32_t instance, const uint8_t *bytes, uint32_t count,
                                      uint64_t timeout_us);
int32_t picokit_spi_write16_dma(uint32_t instance, const uint16_t *words, uint32_t count);
int32_t picokit_spi_write16_dma_timeout(uint32_t instance, const uint16_t *words, uint32_t count,
                                       uint64_t timeout_us);
int32_t picokit_spi_transfer_dma(uint32_t instance, const uint8_t *tx, uint8_t *rx, uint32_t count);
int32_t picokit_spi_transfer_dma_timeout(uint32_t instance, const uint8_t *tx, uint8_t *rx,
                                         uint32_t count, uint64_t timeout_us);
int32_t picokit_spi_transfer16_dma(uint32_t instance, const uint16_t *tx, uint16_t *rx, uint32_t count);
int32_t picokit_spi_transfer16_dma_timeout(uint32_t instance, const uint16_t *tx, uint16_t *rx,
                                          uint32_t count, uint64_t timeout_us);
void picokit_spi_dma_release(uint32_t instance);

int32_t picokit_uart_write_dma(uint32_t instance, const uint8_t *bytes, uint32_t count);
int32_t picokit_uart_write_dma_timeout(uint32_t instance, const uint8_t *bytes, uint32_t count,
                                       uint64_t timeout_us);

int32_t picokit_interrupt_enable(uint32_t pin, uint32_t edge);
void picokit_interrupt_disable(uint32_t pin);
uint32_t picokit_interrupt_take(uint32_t pin);

void picokit_watchdog_enable(uint32_t timeout_ms, uint32_t pause_on_debug);
void picokit_watchdog_update(void);
