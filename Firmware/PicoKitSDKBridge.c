#include "PicoKitSDKBridge.h"

#include <malloc.h>

#include "hardware/adc.h"
#include "hardware/clocks.h"
#include "hardware/dma.h"
#include "hardware/gpio.h"
#include "hardware/i2c.h"
#include "hardware/pwm.h"
#include "hardware/spi.h"
#include "hardware/uart.h"
#include "hardware/watchdog.h"
#include "pico/error.h"
#include "pico/runtime.h"
#include "pico/stdio.h"
#include "pico/stdlib.h"
#include "pico/status_led.h"

// Embedded Swift expects POSIX's aligned-allocation entry point. Newlib's
// bare-metal build exposes the equivalent allocator as memalign instead.
int posix_memalign(void **pointer, size_t alignment, size_t size) {
    if (!pointer || alignment == 0 || (alignment & (alignment - 1)) != 0) return 22;
    if (size == 0) { *pointer = NULL; return 0; }
    void *allocated = memalign(alignment, size);
    if (!allocated) return 12;
    *pointer = allocated;
    return 0;
}

static volatile uint32_t picokit_interrupt_events[30];
static bool picokit_adc_initialized;
static bool picokit_adc_gpio_initialized[4];
static uint32_t picokit_adc_channel = UINT32_MAX;
static bool picokit_adc_temperature_enabled;
static uint32_t picokit_stdio_initialization_state;
static int picokit_uart_dma_channels[2] = {-1, -1};
static int picokit_spi_dma_tx_channels[2] = {-1, -1};
static int picokit_spi_dma_rx_channels[2] = {-1, -1};

// PicoKit deliberately exposes GPIO0...GPIO29, including on RP2350 boards
// with additional GPIO. Keep the fast mask API inside that public range.
#define PICOKIT_GPIO_MASK 0x3fffffffu

static void picokit_gpio_irq(uint gpio, uint32_t events) {
    if (gpio < 30) picokit_interrupt_events[gpio] |= events;
}

static bool picokit_expired(uint64_t deadline) { return time_us_64() >= deadline; }
static uint64_t picokit_deadline_after(uint64_t timeout_us) {
    uint64_t now = time_us_64();
    return UINT64_MAX - now < timeout_us ? UINT64_MAX : now + timeout_us;
}
void picokit_stdio_init(void) {
    // stdio_usb_init claims an IRQ and installs handlers, so it must run only
    // once even when an application constructs several USBSerial values. The
    // atomic state also prevents two cores from racing through initialization.
    for (;;) {
        uint32_t state = __atomic_load_n(&picokit_stdio_initialization_state, __ATOMIC_ACQUIRE);
        if (state == 2) return;
        if (state == 0) {
            uint32_t expected = 0;
            if (__atomic_compare_exchange_n(
                    &picokit_stdio_initialization_state, &expected, 1, false,
                    __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
                bool initialized = stdio_init_all();
                __atomic_store_n(
                    &picokit_stdio_initialization_state, initialized ? 2u : 0u,
                    __ATOMIC_RELEASE
                );
                return;
            }
        }
        tight_loop_contents();
    }
}

// USB stdio must be initialized before the Swift application enters main.
// `pico_enable_stdio_usb` only links the backend; without this hook sketches
// that do not otherwise use Serial never enumerate after `picotool load -f`
// reboots them into the newly flashed application.
#if PICOKIT_ENABLE_USB
static void picokit_runtime_init_stdio(void) {
    picokit_stdio_init();
}
PICO_RUNTIME_INIT_FUNC_RUNTIME(picokit_runtime_init_stdio, "11090");
#endif

void picokit_stdio_write(const char *text) {
    if (text) stdio_put_string(text, -1, false, true);
}
void picokit_stdio_write_line(const char *text) {
    if (text) stdio_put_string(text, -1, true, true);
}
void picokit_stdio_write_bytes(const uint8_t *bytes, uint32_t count) {
    if (bytes && count) stdio_put_string((const char *)bytes, (int)count, false, false);
}
int32_t picokit_stdio_read(uint8_t *byte, uint64_t timeout_us) {
    if (!byte) return -1;

    // The SDK accepts a UInt32 timeout while PicoKit's Duration is UInt64.
    // Read in bounded slices so long Swift timeouts retain their full meaning.
    uint64_t now = time_us_64();
    uint64_t deadline = picokit_deadline_after(timeout_us);
    do {
        now = time_us_64();
        uint64_t remaining = deadline > now ? deadline - now : 0;
        uint32_t slice = remaining > UINT32_MAX ? UINT32_MAX : (uint32_t)remaining;
        int result = stdio_getchar_timeout_us(slice);
        if (result >= 0) {
            *byte = (uint8_t)result;
            return 0;
        }
        if (result != PICO_ERROR_TIMEOUT && result != PICO_ERROR_NO_DATA) return result;
        if (timeout_us == 0 || picokit_expired(deadline)) return -2;
    } while (true);
}
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
    uint64_t deadline = picokit_deadline_after(timeout_us);
    for (uint32_t index = 0; index < count; index++) {
        while (!uart_is_writable(uart)) if (picokit_expired(deadline)) return -2;
        uart_get_hw(uart)->dr = bytes[index];
    }
    return (int32_t)count;
}
static int32_t picokit_dma_write(
    int *channel_slot,
    volatile void *destination,
    const void *source,
    uint32_t count,
    enum dma_channel_transfer_size size,
    uint dreq
) {
    if (!source && count) return -1;
    if (count == 0) return 0;

    int channel = *channel_slot;
    if (channel < 0) {
        channel = dma_claim_unused_channel(false);
        if (channel < 0) return -3;
        *channel_slot = channel;
    }

    dma_channel_config config = dma_channel_get_default_config((uint)channel);
    channel_config_set_transfer_data_size(&config, size);
    channel_config_set_read_increment(&config, true);
    channel_config_set_write_increment(&config, false);
    channel_config_set_dreq(&config, dreq);
    dma_channel_configure((uint)channel, &config, destination, source, count, true);
    dma_channel_wait_for_finish_blocking((uint)channel);
    return (int32_t)count;
}
int32_t picokit_uart_write_dma(uint32_t instance, const uint8_t *bytes, uint32_t count) {
    uart_inst_t *uart = picokit_uart(instance);
    if (!uart) return -1;
    return picokit_dma_write(
        &picokit_uart_dma_channels[instance], &uart_get_hw(uart)->dr,
        bytes, count, DMA_SIZE_8, uart_get_dreq(uart, true)
    );
}
void picokit_uart_dma_release(uint32_t instance) {
    if (instance > 1) return;
    int channel = picokit_uart_dma_channels[instance];
    if (channel < 0) return;
    dma_channel_cleanup((uint)channel);
    dma_channel_unclaim((uint)channel);
    picokit_uart_dma_channels[instance] = -1;
}
int32_t picokit_uart_read(uint32_t instance, uint8_t *byte, uint64_t timeout_us) {
    uart_inst_t *uart = picokit_uart(instance);
    if (!uart || !byte) return -1;
    uint64_t deadline = picokit_deadline_after(timeout_us);
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
void picokit_gpio_set_mask(uint32_t mask) { gpio_set_mask(mask & PICOKIT_GPIO_MASK); }
void picokit_gpio_clear_mask(uint32_t mask) { gpio_clr_mask(mask & PICOKIT_GPIO_MASK); }
void picokit_gpio_toggle_mask(uint32_t mask) { gpio_xor_mask(mask & PICOKIT_GPIO_MASK); }
int32_t picokit_gpio_configure(uint32_t pin, uint32_t output, uint32_t initial_value,
                               uint32_t pull, uint32_t drive, uint32_t slew) {
    if (pin >= NUM_BANK0_GPIOS || pull > 2 || drive > 3 || slew > 1) return -1;
    gpio_init(pin);
    // Program the output latch before enabling output to prevent a transient
    // opposite level on reset, chip-select, and backlight pins.
    gpio_put(pin, initial_value != 0);
    gpio_set_pulls(pin, pull == 1, pull == 2);
    gpio_set_drive_strength(pin, (enum gpio_drive_strength)drive);
    gpio_set_slew_rate(pin, (enum gpio_slew_rate)slew);
    gpio_set_dir(pin, output != 0);
    return 0;
}

uint64_t picokit_time_us(void) { return time_us_64(); }
void picokit_sleep_us(uint64_t microseconds) { sleep_us(microseconds); }

int32_t picokit_pwm_init(uint32_t pin, uint32_t frequency_hz, uint32_t *slice_out, uint32_t *channel_out, uint32_t *wrap_out) {
    if (!frequency_hz || !slice_out || !channel_out || !wrap_out) return -1;
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
    *slice_out = slice;
    *channel_out = pwm_gpio_to_channel(pin);
    *wrap_out = wrap - 1;
    return 0;
}
void picokit_pwm_set_level(uint32_t slice, uint32_t channel, uint32_t wrap, uint16_t level) {
    uint32_t scaled = ((uint32_t)level * (wrap + 1u)) / UINT16_MAX;
    pwm_set_chan_level(slice, (enum pwm_chan)channel, scaled > wrap ? wrap : scaled);
}
void picokit_pwm_set_counter_level(uint32_t slice, uint32_t channel, uint32_t wrap, uint16_t level) {
    pwm_set_chan_level(slice, (enum pwm_chan)channel, level > wrap ? wrap : level);
}

void picokit_adc_init(void) {
    if (!picokit_adc_initialized) {
        adc_init();
        picokit_adc_initialized = true;
    }
}
int32_t picokit_adc_read(uint32_t channel) {
    if (channel > 4) return -1;
    picokit_adc_init();
    if (channel < 4 && !picokit_adc_gpio_initialized[channel]) {
        adc_gpio_init(26 + channel);
        picokit_adc_gpio_initialized[channel] = true;
    }
    bool temperature_enabled = channel == 4;
    if (temperature_enabled != picokit_adc_temperature_enabled) {
        adc_set_temp_sensor_enabled(temperature_enabled);
        picokit_adc_temperature_enabled = temperature_enabled;
    }
    if (channel != picokit_adc_channel) {
        adc_select_input(channel);
        picokit_adc_channel = channel;
    }
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
int32_t picokit_spi_init_config(uint32_t instance, uint32_t frequency_hz, uint32_t sck,
                                uint32_t mosi, int32_t miso, uint32_t mode,
                                uint32_t bit_order, uint32_t data_bits,
                                uint32_t *actual_frequency_hz) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi || !frequency_hz || mode > 3 || bit_order > 1 || (data_bits != 8 && data_bits != 16)) return -1;
    uint32_t actual = spi_init(spi, frequency_hz);
    spi_cpol_t cpol = mode >= 2 ? SPI_CPOL_1 : SPI_CPOL_0;
    spi_cpha_t cpha = (mode & 1u) ? SPI_CPHA_1 : SPI_CPHA_0;
    spi_set_format(spi, data_bits, cpol, cpha, bit_order == 0 ? SPI_MSB_FIRST : SPI_LSB_FIRST);
    gpio_set_function(sck, GPIO_FUNC_SPI);
    gpio_set_function(mosi, GPIO_FUNC_SPI);
    if (miso >= 0) gpio_set_function((uint32_t)miso, GPIO_FUNC_SPI);
    if (actual_frequency_hz) *actual_frequency_hz = actual;
    return 0;
}
int32_t picokit_spi_write(uint32_t instance, const uint8_t *bytes, uint32_t count) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi || (!bytes && count)) return -1;
    return spi_write_blocking(spi, bytes, count);
}
int32_t picokit_spi_write_timeout(uint32_t instance, const uint8_t *bytes, uint32_t count, uint64_t timeout_us) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi || (!bytes && count)) return -1;
    uint64_t deadline = picokit_deadline_after(timeout_us);
    uint32_t transferred = 0;
    while (transferred < count) {
        while (!spi_is_writable(spi)) {
            if (picokit_expired(deadline)) return (int32_t)transferred;
        }
        spi_get_hw(spi)->dr = bytes[transferred++];
        // Drain RX to avoid stalling a full-duplex peripheral during TX-only use.
        while (!spi_is_readable(spi)) {
            if (picokit_expired(deadline)) return (int32_t)(transferred - 1);
        }
        (void)spi_get_hw(spi)->dr;
    }
    return (int32_t)transferred;
}
int32_t picokit_spi_write16(uint32_t instance, const uint16_t *words, uint32_t count) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi || (!words && count)) return -1;
    return spi_write16_blocking(spi, words, count);
}
static int32_t picokit_spi_dma_write(
    uint32_t instance,
    spi_inst_t *spi,
    const void *bytes,
    uint32_t count,
    enum dma_channel_transfer_size size
) {
    if (!bytes && count) return -1;
    if (count == 0) return 0;

    int tx_channel = picokit_spi_dma_tx_channels[instance];
    bool claimed_tx = false;
    if (tx_channel < 0) {
        tx_channel = dma_claim_unused_channel(false);
        if (tx_channel < 0) return -3;
        picokit_spi_dma_tx_channels[instance] = tx_channel;
        claimed_tx = true;
    }
    int rx_channel = picokit_spi_dma_rx_channels[instance];
    if (rx_channel < 0) rx_channel = dma_claim_unused_channel(false);
    if (rx_channel < 0) {
        if (claimed_tx) {
            dma_channel_unclaim((uint)tx_channel);
            picokit_spi_dma_tx_channels[instance] = -1;
        }
        return -3;
    }
    picokit_spi_dma_rx_channels[instance] = rx_channel;

    // SPI is full duplex even for write-only Swift APIs. Drain every received
    // word through a paired DMA channel so the RX FIFO never stalls TX.
    volatile uint16_t discard;
    dma_channel_config rx_config = dma_channel_get_default_config((uint)rx_channel);
    channel_config_set_transfer_data_size(&rx_config, size);
    channel_config_set_read_increment(&rx_config, false);
    channel_config_set_write_increment(&rx_config, false);
    channel_config_set_dreq(&rx_config, spi_get_dreq(spi, false));
    dma_channel_configure(
        (uint)rx_channel, &rx_config, &discard, &spi_get_hw(spi)->dr, count, false
    );

    dma_channel_config tx_config = dma_channel_get_default_config((uint)tx_channel);
    channel_config_set_transfer_data_size(&tx_config, size);
    channel_config_set_read_increment(&tx_config, true);
    channel_config_set_write_increment(&tx_config, false);
    channel_config_set_dreq(&tx_config, spi_get_dreq(spi, true));
    dma_channel_configure(
        (uint)tx_channel, &tx_config, &spi_get_hw(spi)->dr, bytes, count, true
    );

    dma_channel_wait_for_finish_blocking((uint)tx_channel);
    dma_channel_wait_for_finish_blocking((uint)rx_channel);
    return (int32_t)count;
}
int32_t picokit_spi_write_dma(uint32_t instance, const uint8_t *bytes, uint32_t count) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi) return -1;
    return picokit_spi_dma_write(instance, spi, bytes, count, DMA_SIZE_8);
}
int32_t picokit_spi_write16_dma(uint32_t instance, const uint16_t *words, uint32_t count) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi) return -1;
    return picokit_spi_dma_write(instance, spi, words, count, DMA_SIZE_16);
}
void picokit_spi_dma_release(uint32_t instance) {
    if (instance > 1) return;
    int tx_channel = picokit_spi_dma_tx_channels[instance];
    int rx_channel = picokit_spi_dma_rx_channels[instance];
    if (tx_channel >= 0) {
        dma_channel_cleanup((uint)tx_channel);
        dma_channel_unclaim((uint)tx_channel);
        picokit_spi_dma_tx_channels[instance] = -1;
    }
    if (rx_channel >= 0) {
        dma_channel_cleanup((uint)rx_channel);
        dma_channel_unclaim((uint)rx_channel);
        picokit_spi_dma_rx_channels[instance] = -1;
    }
}
int32_t picokit_spi_transfer(uint32_t instance, const uint8_t *tx, uint8_t *rx, uint32_t count, uint64_t timeout_us) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi || (!tx && count) || (!rx && count)) return -1;
    uint64_t deadline = picokit_deadline_after(timeout_us);
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
