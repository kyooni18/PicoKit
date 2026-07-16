#include "PicoKitSDKBridge.h"

#include <limits.h>
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
#include "pico/critical_section.h"
#include "pico/stdio.h"
#if PICOKIT_ENABLE_USB
#include "pico/stdio_usb.h"
#endif
#include "pico/stdlib.h"
#include "pico/status_led.h"

#ifndef PICOKIT_COMPILED_BOARD
#define PICOKIT_COMPILED_BOARD 255u
#endif

// Embedded Swift expects POSIX's aligned-allocation entry point. Newlib's
// bare-metal build exposes the equivalent allocator as memalign instead.
int posix_memalign(void **pointer, size_t alignment, size_t size);
int posix_memalign(void **pointer, size_t alignment, size_t size) {
    if (alignment < sizeof(void *) || (alignment & (alignment - 1)) != 0) return 22;
    if (size == 0) { *pointer = NULL; return 0; }
    void *allocated = memalign(alignment, size);
    if (!allocated) return 12;
    *pointer = allocated;
    return 0;
}

// PicoKit deliberately exposes GPIO0...GPIO29, including on RP2350 boards
// with additional GPIO. Keep the fast mask API inside that public range.
#define PICOKIT_GPIO_COUNT 30u
#define PICOKIT_GPIO_MASK ((1u << PICOKIT_GPIO_COUNT) - 1u)

static volatile uint32_t picokit_interrupt_events[PICOKIT_GPIO_COUNT];
static uint32_t picokit_adc_initialization_state;
static bool picokit_adc_gpio_initialized[NUM_ADC_CHANNELS - 1];
static uint32_t picokit_adc_channel = UINT32_MAX;
static bool picokit_adc_temperature_enabled;
static critical_section_t picokit_adc_critical_section;
static uint32_t picokit_stdio_initialization_state;
static uint32_t picokit_status_led_initialization_state;
static int picokit_uart_dma_channels[2] = {-1, -1};
static int picokit_spi_dma_tx_channels[2] = {-1, -1};
static int picokit_spi_dma_rx_channels[2] = {-1, -1};

static bool picokit_valid_gpio(uint32_t pin) { return pin < PICOKIT_GPIO_COUNT; }

static bool picokit_pin_in_list(const uint32_t *pins, size_t count, uint32_t pin) {
    for (size_t index = 0; index < count; ++index) {
        if (pins[index] == pin) return true;
    }
    return false;
}

static bool picokit_valid_i2c_pins(uint32_t instance, uint32_t sda, uint32_t scl) {
    if (instance > 1 || sda == scl) return false;
    uint32_t base = instance == 0 ? 0u : 2u;
    return sda % 4u == base && scl % 4u == base + 1u;
}

static bool picokit_valid_spi_pins(
    uint32_t instance, uint32_t sck, uint32_t mosi, int32_t miso
) {
    static const uint32_t spi0_sck[] = {2, 6, 18, 22};
    static const uint32_t spi0_mosi[] = {3, 7, 19, 23};
    static const uint32_t spi0_miso[] = {0, 4, 16, 20};
    static const uint32_t spi1_sck[] = {10, 14, 26};
    static const uint32_t spi1_mosi[] = {11, 15, 27};
    static const uint32_t spi1_miso[] = {8, 12, 24, 28};
    if (instance > 1 || sck == mosi || (miso >= 0 &&
        (sck == (uint32_t)miso || mosi == (uint32_t)miso))) return false;
    const uint32_t *sck_pins = instance == 0 ? spi0_sck : spi1_sck;
    const uint32_t *mosi_pins = instance == 0 ? spi0_mosi : spi1_mosi;
    const uint32_t *miso_pins = instance == 0 ? spi0_miso : spi1_miso;
    size_t sck_count = instance == 0 ? sizeof(spi0_sck) / sizeof(spi0_sck[0]) :
        sizeof(spi1_sck) / sizeof(spi1_sck[0]);
    size_t mosi_count = instance == 0 ? sizeof(spi0_mosi) / sizeof(spi0_mosi[0]) :
        sizeof(spi1_mosi) / sizeof(spi1_mosi[0]);
    size_t miso_count = instance == 0 ? sizeof(spi0_miso) / sizeof(spi0_miso[0]) :
        sizeof(spi1_miso) / sizeof(spi1_miso[0]);
    return picokit_pin_in_list(sck_pins, sck_count, sck) &&
        picokit_pin_in_list(mosi_pins, mosi_count, mosi) &&
        (miso < 0 || picokit_pin_in_list(miso_pins, miso_count, (uint32_t)miso));
}

static bool picokit_valid_uart_pins(uint32_t instance, uint32_t tx, uint32_t rx) {
#if PICO_RP2040
    static const uint32_t uart0_tx[] = {0, 12, 16, 28};
    static const uint32_t uart0_rx[] = {1, 13, 17, 29};
    static const uint32_t uart1_tx[] = {4, 8, 20, 24};
    static const uint32_t uart1_rx[] = {5, 9, 21, 25};
#else
    static const uint32_t uart0_tx[] = {0, 2, 12, 14, 16, 18, 28};
    static const uint32_t uart0_rx[] = {1, 3, 13, 15, 17, 19, 29};
    static const uint32_t uart1_tx[] = {4, 6, 8, 10, 20, 22, 24, 26};
    static const uint32_t uart1_rx[] = {5, 7, 9, 11, 21, 23, 25, 27};
#endif
    if (instance > 1 || tx == rx) return false;
    const uint32_t *tx_pins = instance == 0 ? uart0_tx : uart1_tx;
    const uint32_t *rx_pins = instance == 0 ? uart0_rx : uart1_rx;
    size_t tx_count = instance == 0 ? sizeof(uart0_tx) / sizeof(uart0_tx[0]) :
        sizeof(uart1_tx) / sizeof(uart1_tx[0]);
    size_t rx_count = instance == 0 ? sizeof(uart0_rx) / sizeof(uart0_rx[0]) :
        sizeof(uart1_rx) / sizeof(uart1_rx[0]);
    return picokit_pin_in_list(tx_pins, tx_count, tx) &&
        picokit_pin_in_list(rx_pins, rx_count, rx);
}

static bool picokit_valid_dma_count(uint32_t count) {
#if PICO_RP2040
    (void)count;
    return true;
#else
    // RP2350 uses the upper four transfer-count bits for DMA mode flags.
    return count <= 0x0fffffffu;
#endif
}
static bool picokit_valid_i2c_frequency(uint32_t frequency_hz) {
    if (!frequency_hz) return false;

    // Match the SDK's i2c_set_baudrate calculations before calling i2c_init.
    // The SDK uses invalid_params/assert for these bounds, which would turn a
    // recoverable Swift setup error into a firmware reset.
    uint64_t clock_hz = clock_get_hz(clk_sys);
    uint64_t period = (clock_hz + frequency_hz / 2u) / frequency_hz;
    uint64_t low_count = period * 3u / 5u;
    uint64_t high_count = period - low_count;
    if (high_count > I2C_IC_FS_SCL_HCNT_IC_FS_SCL_HCNT_BITS ||
        low_count > I2C_IC_FS_SCL_LCNT_IC_FS_SCL_LCNT_BITS ||
        high_count < 8u || low_count < 8u) return false;

    uint64_t hold_count = frequency_hz < 1000000u
        ? (clock_hz * 3u) / 10000000u + 1u
        : (clock_hz * 3u) / 25000000u + 1u;
    return low_count >= 2u && hold_count <= low_count - 2u;
}
static bool picokit_valid_spi_frequency(uint32_t frequency_hz) {
    if (!frequency_hz) return false;
    uint64_t clock_hz = clock_get_hz(clk_peri);
    // spi_set_baudrate requires baudrate <= clk_peri and must find an even
    // prescaler no greater than 254 for the requested output frequency.
    return frequency_hz <= clock_hz &&
        (uint64_t)frequency_hz * 254u * 256u > clock_hz;
}
static bool picokit_valid_result_count(uint32_t count) {
    // Transfer results are reported through int32_t; reject counts that
    // would otherwise wrap into a negative or ambiguous result.
    return count <= (uint32_t)INT32_MAX;
}
static bool picokit_dma_channel_has_error(uint channel) {
    uint32_t status = dma_channel_hw_addr(channel)->ctrl_trig;
    return (status & (DMA_CH0_CTRL_TRIG_AHB_ERROR_BITS |
                      DMA_CH0_CTRL_TRIG_READ_ERROR_BITS |
                      DMA_CH0_CTRL_TRIG_WRITE_ERROR_BITS)) != 0;
}

static void picokit_gpio_irq(uint gpio, uint32_t events) {
    if (gpio < PICOKIT_GPIO_COUNT) {
        __atomic_fetch_or(&picokit_interrupt_events[gpio], events, __ATOMIC_RELEASE);
    }
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
                // PicoKit's firmware target is USB-CDC-only. Initializing the
                // concrete driver avoids relying on stdio_init_all's
                // link-time driver registration, which can be absent when the
                // SDK lives inside the bridge static archive.
                bool initialized = stdio_usb_init();
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

#if PICOKIT_ENABLE_USB
// C constructors run after the Pico SDK's complete preinit array, including
// the per-core IRQ and RP2350 boot-lock initializers. Starting USB here keeps
// CDC/reset available even for Swift applications that never use Serial.
__attribute__((constructor(101)))
static void picokit_initialize_usb_stdio(void) {
    picokit_stdio_init();
}
#endif

uint32_t picokit_stdio_connected(void) {
#if PICOKIT_ENABLE_USB
    picokit_stdio_init();
    return stdio_usb_connected() ? 1u : 0u;
#else
    return 0u;
#endif
}

void picokit_stdio_write(const char *text) {
    if (text) stdio_put_string(text, -1, false, true);
}
void picokit_stdio_write_line(const char *text) {
    if (text) stdio_put_string(text, -1, true, true);
}
void picokit_stdio_write_byte(uint8_t byte) {
    stdio_put_string((const char *)&byte, 1, false, false);
}
void picokit_stdio_write_bytes(const uint8_t *bytes, uint32_t count) {
    while (bytes && count) {
        uint32_t chunk = count > (uint32_t)INT_MAX ? (uint32_t)INT_MAX : count;
        stdio_put_string((const char *)bytes, (int)chunk, false, false);
        bytes += chunk;
        count -= chunk;
    }
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
static int32_t picokit_uart_init_impl(
    uint32_t instance, uint32_t baud_rate, uint32_t tx, uint32_t rx,
    uint32_t *actual_baud_rate_out
) {
    uart_inst_t *uart = picokit_uart(instance);
    if (!uart || !baud_rate || !picokit_valid_gpio(tx) || !picokit_valid_gpio(rx) ||
        !picokit_valid_uart_pins(instance, tx, rx)) return -1;
    uint32_t actual_baud_rate = uart_init(uart, baud_rate);
    gpio_set_function(tx, UART_FUNCSEL_NUM(uart, tx));
    gpio_set_function(rx, UART_FUNCSEL_NUM(uart, rx));
    if (actual_baud_rate_out) *actual_baud_rate_out = actual_baud_rate;
    return 0;
}
int32_t picokit_uart_init(uint32_t instance, uint32_t baud_rate, uint32_t tx, uint32_t rx) {
    return picokit_uart_init_impl(instance, baud_rate, tx, rx, NULL);
}
int32_t picokit_uart_init_with_actual_baud_rate(
    uint32_t instance, uint32_t baud_rate, uint32_t tx, uint32_t rx,
    uint32_t *actual_baud_rate_out
) {
    if (!actual_baud_rate_out) return -1;
    return picokit_uart_init_impl(
        instance, baud_rate, tx, rx, actual_baud_rate_out
    );
}
int32_t picokit_uart_write(uint32_t instance, const uint8_t *bytes, uint32_t count, uint64_t timeout_us) {
    uart_inst_t *uart = picokit_uart(instance);
    if (!uart || !picokit_valid_result_count(count) || (!bytes && count)) return -1;
    uint64_t deadline = picokit_deadline_after(timeout_us);
    uint32_t transferred = 0;
    while (transferred < count) {
        while (!uart_is_writable(uart)) {
            if (picokit_expired(deadline)) return transferred == 0 ? -2 : (int32_t)transferred;
        }
        uart_get_hw(uart)->dr = bytes[transferred++];
    }
    return (int32_t)transferred;
}
static int32_t picokit_dma_write(
    int *channel_slot,
    volatile void *destination,
    const void *source,
    uint32_t count,
    enum dma_channel_transfer_size size,
    uint dreq,
    bool timed,
    uint64_t timeout_us
) {
    if (!source && count) return -1;
    if (!picokit_valid_dma_count(count) || !picokit_valid_result_count(count)) return -1;
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
    dma_channel_configure(
        (uint)channel, &config, destination, source, dma_encode_transfer_count((uint)count), true
    );
    uint64_t deadline = timed ? picokit_deadline_after(timeout_us) : 0;
    for (;;) {
        if (picokit_dma_channel_has_error((uint)channel)) {
            dma_channel_cleanup((uint)channel);
            return -4;
        }
        if (!dma_channel_is_busy((uint)channel)) break;
        if (timed && picokit_expired(deadline)) {
            // dma_channel_cleanup disables the channel before aborting;
            // this ordering is required by the RP2350 abort erratum.
            // Keep the channel claimed so the next call can reconfigure it.
            dma_channel_cleanup((uint)channel);
            return -2;
        }
    }
    return (int32_t)count;
}
int32_t picokit_uart_write_dma(uint32_t instance, const uint8_t *bytes, uint32_t count) {
    uart_inst_t *uart = picokit_uart(instance);
    if (!uart) return -1;
    return picokit_dma_write(
        &picokit_uart_dma_channels[instance], &uart_get_hw(uart)->dr,
        bytes, count, DMA_SIZE_8, uart_get_dreq(uart, true), false, 0
    );
}
int32_t picokit_uart_write_dma_timeout(
    uint32_t instance, const uint8_t *bytes, uint32_t count, uint64_t timeout_us
) {
    uart_inst_t *uart = picokit_uart(instance);
    if (!uart) return -1;
    return picokit_dma_write(
        &picokit_uart_dma_channels[instance], &uart_get_hw(uart)->dr,
        bytes, count, DMA_SIZE_8, uart_get_dreq(uart, true), true, timeout_us
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
uint32_t picokit_compiled_chip(void) {
#if PICO_RP2040
    return 0;
#else
    return 1;
#endif
}
uint32_t picokit_compiled_board(void) { return PICOKIT_COMPILED_BOARD; }
int32_t picokit_status_led_init(void) {
    // The SDK creates an async context for wireless-board LEDs and asserts if
    // status_led_init() is called a second time. Share one process-lifetime
    // initialization across all BoardLED values, including concurrent setup.
    for (;;) {
        uint32_t state = __atomic_load_n(&picokit_status_led_initialization_state, __ATOMIC_ACQUIRE);
        if (state == 2) return 0;
        if (state == 0) {
            uint32_t expected = 0;
            if (__atomic_compare_exchange_n(
                    &picokit_status_led_initialization_state, &expected, 1, false,
                    __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
                bool initialized = status_led_init();
                __atomic_store_n(
                    &picokit_status_led_initialization_state, initialized ? 2u : 0u,
                    __ATOMIC_RELEASE
                );
                return initialized ? 0 : -1;
            }
        }
        tight_loop_contents();
    }
}
void picokit_status_led_write(uint32_t value) { status_led_set_state(value != 0); }
void picokit_status_led_toggle(void) { status_led_set_state(!status_led_get_state()); }

void picokit_gpio_init(uint32_t pin) { if (picokit_valid_gpio(pin)) gpio_init(pin); }
void picokit_gpio_set_direction(uint32_t pin, uint32_t output) {
    if (picokit_valid_gpio(pin)) gpio_set_dir(pin, output != 0);
}
void picokit_gpio_write(uint32_t pin, uint32_t value) {
    if (picokit_valid_gpio(pin)) gpio_put(pin, value != 0);
}
uint32_t picokit_gpio_read(uint32_t pin) {
    return picokit_valid_gpio(pin) && gpio_get(pin) ? 1u : 0u;
}
void picokit_gpio_toggle(uint32_t pin) {
    if (picokit_valid_gpio(pin)) gpio_xor_mask(1u << pin);
}
void picokit_gpio_set_mask(uint32_t mask) { gpio_set_mask(mask & PICOKIT_GPIO_MASK); }
void picokit_gpio_clear_mask(uint32_t mask) { gpio_clr_mask(mask & PICOKIT_GPIO_MASK); }
void picokit_gpio_toggle_mask(uint32_t mask) { gpio_xor_mask(mask & PICOKIT_GPIO_MASK); }
int32_t picokit_gpio_configure(uint32_t pin, uint32_t output, uint32_t initial_value,
                               uint32_t pull, uint32_t drive, uint32_t slew) {
    if (!picokit_valid_gpio(pin) || pull > 2 || drive > 3 || slew > 1) return -1;
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

static int32_t picokit_pwm_init_impl(
    uint32_t pin, uint32_t frequency_hz, uint32_t *slice_out, uint32_t *channel_out,
    uint32_t *wrap_out, uint32_t *actual_frequency_out
) {
    if (!picokit_valid_gpio(pin) || !frequency_hz || !slice_out || !channel_out || !wrap_out) return -1;
    uint slice = pwm_gpio_to_slice_num(pin);
    uint32_t clock_hz = clock_get_hz(clk_sys);
    uint64_t cycle_span = (uint64_t)frequency_hz * 65536u;
    uint32_t divider = (uint32_t)(((uint64_t)clock_hz + cycle_span - 1u) / cycle_span);
    if (divider < 1) divider = 1;
    if (divider > 255) return -1;
    uint64_t denominator = (uint64_t)divider * frequency_hz;
    uint32_t wrap = (uint32_t)((uint64_t)clock_hz / denominator);
    if (wrap < 2 || wrap > 65536) return -1;
    // Do not change the pin mux until every frequency and output argument has
    // passed validation. A rejected configuration must leave the GPIO usable
    // by the caller's previous peripheral or mode.
    gpio_set_function(pin, GPIO_FUNC_PWM);
    pwm_set_clkdiv_int_frac(slice, (uint8_t)divider, 0);
    pwm_set_wrap(slice, (uint16_t)(wrap - 1));
    pwm_set_gpio_level(pin, 0);
    pwm_set_enabled(slice, true);
    *slice_out = slice;
    *channel_out = pwm_gpio_to_channel(pin);
    *wrap_out = wrap - 1;
    if (actual_frequency_out) {
        *actual_frequency_out = (uint32_t)((uint64_t)clock_hz / ((uint64_t)divider * wrap));
    }
    return 0;
}
int32_t picokit_pwm_init(uint32_t pin, uint32_t frequency_hz, uint32_t *slice_out, uint32_t *channel_out, uint32_t *wrap_out) {
    return picokit_pwm_init_impl(pin, frequency_hz, slice_out, channel_out, wrap_out, NULL);
}
int32_t picokit_pwm_init_with_actual_frequency(
    uint32_t pin, uint32_t frequency_hz, uint32_t *slice_out, uint32_t *channel_out,
    uint32_t *wrap_out, uint32_t *actual_frequency_out
) {
    if (!actual_frequency_out) return -1;
    return picokit_pwm_init_impl(
        pin, frequency_hz, slice_out, channel_out, wrap_out, actual_frequency_out
    );
}
void picokit_pwm_set_level(uint32_t slice, uint32_t channel, uint32_t wrap, uint16_t level) {
    if (slice >= NUM_PWM_SLICES || channel > 1 || wrap > UINT16_MAX) return;
    uint32_t scaled = ((uint32_t)level * (wrap + 1u)) / UINT16_MAX;
    pwm_set_chan_level(slice, (enum pwm_chan)channel,
                       (uint16_t)(scaled > wrap ? wrap : scaled));
}
void picokit_pwm_set_counter_level(uint32_t slice, uint32_t channel, uint32_t wrap, uint16_t level) {
    if (slice >= NUM_PWM_SLICES || channel > 1 || wrap > UINT16_MAX) return;
    pwm_set_chan_level(slice, (enum pwm_chan)channel,
                       (uint16_t)(level > wrap ? wrap : level));
}

void picokit_adc_init(void) {
    // ADC setup is shared by every PicoADC value. Keep initialization
    // one-shot and race-free, matching the USB and status-LED lifecycles.
    for (;;) {
        uint32_t state = __atomic_load_n(&picokit_adc_initialization_state, __ATOMIC_ACQUIRE);
        if (state == 2) return;
        if (state == 0) {
            uint32_t expected = 0;
            if (__atomic_compare_exchange_n(
                    &picokit_adc_initialization_state, &expected, 1, false,
                    __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
                adc_init();
                critical_section_init(&picokit_adc_critical_section);
                __atomic_store_n(&picokit_adc_initialization_state, 2u, __ATOMIC_RELEASE);
                return;
            }
        }
        tight_loop_contents();
    }
}
int32_t picokit_adc_read(uint32_t channel) {
    if (channel >= NUM_ADC_CHANNELS) return -1;
    picokit_adc_init();
    critical_section_enter_blocking(&picokit_adc_critical_section);
    if (channel < ADC_TEMPERATURE_CHANNEL_NUM && !picokit_adc_gpio_initialized[channel]) {
        adc_gpio_init(ADC_BASE_PIN + channel);
        picokit_adc_gpio_initialized[channel] = true;
    }
    bool temperature_enabled = channel == ADC_TEMPERATURE_CHANNEL_NUM;
    if (temperature_enabled != picokit_adc_temperature_enabled) {
        adc_set_temp_sensor_enabled(temperature_enabled);
        picokit_adc_temperature_enabled = temperature_enabled;
    }
    if (channel != picokit_adc_channel) {
        adc_select_input(channel);
        picokit_adc_channel = channel;
    }
    int32_t result = (int32_t)adc_read();
    critical_section_exit(&picokit_adc_critical_section);
    return result;
}

static i2c_inst_t *picokit_i2c(uint32_t instance) { return instance == 0 ? i2c0 : instance == 1 ? i2c1 : NULL; }
static int32_t picokit_i2c_init_impl(
    uint32_t instance, uint32_t frequency_hz, uint32_t sda, uint32_t scl,
    uint32_t *actual_frequency_out
) {
    i2c_inst_t *i2c = picokit_i2c(instance);
    if (!i2c || !picokit_valid_i2c_frequency(frequency_hz) ||
        !picokit_valid_gpio(sda) || !picokit_valid_gpio(scl) ||
        !picokit_valid_i2c_pins(instance, sda, scl)) return -1;
    uint32_t actual_frequency = i2c_init(i2c, frequency_hz);
    gpio_set_function(sda, GPIO_FUNC_I2C);
    gpio_set_function(scl, GPIO_FUNC_I2C);
    gpio_pull_up(sda);
    gpio_pull_up(scl);
    if (actual_frequency_out) *actual_frequency_out = actual_frequency;
    return 0;
}
int32_t picokit_i2c_init(uint32_t instance, uint32_t frequency_hz, uint32_t sda, uint32_t scl) {
    return picokit_i2c_init_impl(instance, frequency_hz, sda, scl, NULL);
}
int32_t picokit_i2c_init_with_actual_frequency(
    uint32_t instance, uint32_t frequency_hz, uint32_t sda, uint32_t scl,
    uint32_t *actual_frequency_out
) {
    if (!actual_frequency_out) return -1;
    return picokit_i2c_init_impl(
        instance, frequency_hz, sda, scl, actual_frequency_out
    );
}
int32_t picokit_i2c_write(uint32_t instance, uint32_t address, const uint8_t *bytes, uint32_t count,
                          uint64_t timeout_us, uint32_t nostop) {
    i2c_inst_t *i2c = picokit_i2c(instance);
    if (!i2c || !picokit_valid_result_count(count) || address < 0x08 || address > 0x77 || (!bytes && count) ||
        timeout_us > UINT32_MAX || nostop > 1) return -1;
    // The Pico SDK asserts for a zero-length transaction. Keep the C ABI
    // safe for direct callers as well as the Swift wrapper.
    if (count == 0) return 0;
    return i2c_write_timeout_us(i2c, (uint8_t)address, bytes, count, nostop != 0, (uint32_t)timeout_us);
}
int32_t picokit_i2c_read(uint32_t instance, uint32_t address, uint8_t *bytes, uint32_t count,
                         uint64_t timeout_us, uint32_t nostop) {
    i2c_inst_t *i2c = picokit_i2c(instance);
    if (!i2c || !picokit_valid_result_count(count) || address < 0x08 || address > 0x77 || (!bytes && count) ||
        timeout_us > UINT32_MAX || nostop > 1) return -1;
    // See picokit_i2c_write: do not enter the SDK assertion path for empty
    // reads, even when the bridge is called without Swift's validation.
    if (count == 0) return 0;
    return i2c_read_timeout_us(i2c, (uint8_t)address, bytes, count, nostop != 0, (uint32_t)timeout_us);
}

static spi_inst_t *picokit_spi(uint32_t instance) { return instance == 0 ? spi0 : instance == 1 ? spi1 : NULL; }
int32_t picokit_spi_init(uint32_t instance, uint32_t frequency_hz, uint32_t sck, uint32_t mosi, uint32_t miso) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi || !picokit_valid_spi_frequency(frequency_hz) ||
        !picokit_valid_gpio(sck) || !picokit_valid_gpio(mosi) ||
        !picokit_valid_gpio(miso) || !picokit_valid_spi_pins(instance, sck, mosi, (int32_t)miso)) return -1;
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
    if (!spi || !picokit_valid_spi_frequency(frequency_hz) ||
        !picokit_valid_gpio(sck) || !picokit_valid_gpio(mosi) ||
        miso < -1 || (miso >= 0 && !picokit_valid_gpio((uint32_t)miso)) || mode > 3 || bit_order > 1 ||
        (data_bits != 8 && data_bits != 16) || !picokit_valid_spi_pins(instance, sck, mosi, miso)) return -1;
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
    if (!spi || !picokit_valid_result_count(count) || (!bytes && count)) return -1;
    return spi_write_blocking(spi, bytes, count);
}
int32_t picokit_spi_read(uint32_t instance, uint8_t repeated_tx_data, uint8_t *bytes, uint32_t count) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi || !picokit_valid_result_count(count) || (!bytes && count)) return -1;
    return spi_read_blocking(spi, repeated_tx_data, bytes, count);
}
int32_t picokit_spi_read_timeout(uint32_t instance, uint8_t repeated_tx_data, uint8_t *bytes,
                                 uint32_t count, uint64_t timeout_us) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi || !picokit_valid_result_count(count) || (!bytes && count)) return -1;
    uint64_t deadline = picokit_deadline_after(timeout_us);
    for (uint32_t index = 0; index < count; index++) {
        while (!spi_is_writable(spi)) if (picokit_expired(deadline)) return -2;
        spi_get_hw(spi)->dr = repeated_tx_data;
        while (!spi_is_readable(spi)) if (picokit_expired(deadline)) return -2;
        bytes[index] = (uint8_t)spi_get_hw(spi)->dr;
    }
    return (int32_t)count;
}
int32_t picokit_spi_read16(uint32_t instance, uint16_t repeated_tx_word, uint16_t *words, uint32_t count) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi || !picokit_valid_result_count(count) || (!words && count)) return -1;

    // Match the SDK's FIFO-depth-limited full-duplex loop while transmitting
    // the same word for every received 16-bit frame.
    const uint32_t fifo_depth = 8;
    uint32_t rx_remaining = count;
    uint32_t tx_remaining = count;
    while (rx_remaining || tx_remaining) {
        // Compare the distance between the receive and transmit queues instead
        // of adding fifo_depth to tx_remaining; the latter can wrap for a
        // large direct C call even though Swift-side counts are bounded.
        if (tx_remaining && spi_is_writable(spi) &&
            (rx_remaining < tx_remaining || rx_remaining - tx_remaining < fifo_depth)) {
            spi_get_hw(spi)->dr = repeated_tx_word;
            --tx_remaining;
        }
        if (rx_remaining && spi_is_readable(spi)) {
            *words++ = (uint16_t)spi_get_hw(spi)->dr;
            --rx_remaining;
        }
    }
    return (int32_t)count;
}
int32_t picokit_spi_read16_timeout(uint32_t instance, uint16_t repeated_tx_word, uint16_t *words,
                                   uint32_t count, uint64_t timeout_us) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi || !picokit_valid_result_count(count) || (!words && count)) return -1;
    uint64_t deadline = picokit_deadline_after(timeout_us);
    for (uint32_t index = 0; index < count; index++) {
        while (!spi_is_writable(spi)) if (picokit_expired(deadline)) return -2;
        spi_get_hw(spi)->dr = repeated_tx_word;
        while (!spi_is_readable(spi)) if (picokit_expired(deadline)) return -2;
        words[index] = (uint16_t)spi_get_hw(spi)->dr;
    }
    return (int32_t)count;
}
int32_t picokit_spi_write_timeout(uint32_t instance, const uint8_t *bytes, uint32_t count, uint64_t timeout_us) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi || !picokit_valid_result_count(count) || (!bytes && count)) return -1;
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
int32_t picokit_spi_transfer16(uint32_t instance, const uint16_t *tx, uint16_t *rx,
                               uint32_t count, uint64_t timeout_us) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi || !picokit_valid_result_count(count) || (!tx && count) || (!rx && count)) return -1;
    uint64_t deadline = picokit_deadline_after(timeout_us);
    for (uint32_t index = 0; index < count; index++) {
        while (!spi_is_writable(spi)) if (picokit_expired(deadline)) return -2;
        spi_get_hw(spi)->dr = tx[index];
        while (!spi_is_readable(spi)) if (picokit_expired(deadline)) return -2;
        rx[index] = (uint16_t)spi_get_hw(spi)->dr;
    }
    return (int32_t)count;
}
int32_t picokit_spi_write16(uint32_t instance, const uint16_t *words, uint32_t count) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi || !picokit_valid_result_count(count) || (!words && count)) return -1;
    return spi_write16_blocking(spi, words, count);
}
int32_t picokit_spi_write16_timeout(uint32_t instance, const uint16_t *words, uint32_t count,
                                    uint64_t timeout_us) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi || !picokit_valid_result_count(count) || (!words && count)) return -1;
    uint64_t deadline = picokit_deadline_after(timeout_us);
    uint32_t transferred = 0;
    while (transferred < count) {
        while (!spi_is_writable(spi)) {
            if (picokit_expired(deadline)) return (int32_t)transferred;
        }
        spi_get_hw(spi)->dr = words[transferred++];
        // Drain RX to keep the full-duplex SPI peripheral moving during TX-only use.
        while (!spi_is_readable(spi)) {
            if (picokit_expired(deadline)) return (int32_t)(transferred - 1);
        }
        (void)spi_get_hw(spi)->dr;
    }
    return (int32_t)transferred;
}
static int32_t picokit_spi_dma_write(
    uint32_t instance,
    spi_inst_t *spi,
    const void *bytes,
    volatile void *received,
    bool receive_write_increment,
    uint32_t count,
    enum dma_channel_transfer_size size,
    bool timed,
    uint64_t timeout_us
) {
    if ((!bytes || !received) && count) return -1;
    if (!picokit_valid_dma_count(count) || !picokit_valid_result_count(count)) return -1;
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

    // SPI is full duplex even for write-only Swift APIs. Consume every
    // received word through a paired DMA channel so the RX FIFO never stalls
    // TX. A write-only call supplies a one-word discard sink; transfer calls
    // provide the caller's incrementing receive buffer.
    dma_channel_config rx_config = dma_channel_get_default_config((uint)rx_channel);
    channel_config_set_transfer_data_size(&rx_config, size);
    channel_config_set_read_increment(&rx_config, false);
    channel_config_set_write_increment(&rx_config, receive_write_increment);
    channel_config_set_dreq(&rx_config, spi_get_dreq(spi, false));
    dma_channel_configure(
        (uint)rx_channel, &rx_config, received, &spi_get_hw(spi)->dr,
        dma_encode_transfer_count((uint)count), false
    );

    dma_channel_config tx_config = dma_channel_get_default_config((uint)tx_channel);
    channel_config_set_transfer_data_size(&tx_config, size);
    channel_config_set_read_increment(&tx_config, true);
    channel_config_set_write_increment(&tx_config, false);
    channel_config_set_dreq(&tx_config, spi_get_dreq(spi, true));
    dma_channel_configure(
        (uint)tx_channel, &tx_config, &spi_get_hw(spi)->dr, bytes,
        dma_encode_transfer_count((uint)count), true
    );

    uint64_t deadline = timed ? picokit_deadline_after(timeout_us) : 0;
    for (;;) {
        if (picokit_dma_channel_has_error((uint)tx_channel) ||
            picokit_dma_channel_has_error((uint)rx_channel)) {
            dma_channel_cleanup((uint)tx_channel);
            dma_channel_cleanup((uint)rx_channel);
            return -4;
        }
        if (!dma_channel_is_busy((uint)tx_channel) &&
            !dma_channel_is_busy((uint)rx_channel)) break;
        if (timed && picokit_expired(deadline)) {
            // Cleanup disables both channels before aborting them. This is
            // required on RP2350 to prevent a chained/self-triggered DMA
            // channel from restarting after timeout recovery.
            dma_channel_cleanup((uint)tx_channel);
            dma_channel_cleanup((uint)rx_channel);
            return -2;
        }
    }
    return (int32_t)count;
}
int32_t picokit_spi_write_dma(uint32_t instance, const uint8_t *bytes, uint32_t count) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi) return -1;
    uint8_t discard;
    return picokit_spi_dma_write(instance, spi, bytes, &discard, false, count, DMA_SIZE_8, false, 0);
}
int32_t picokit_spi_write_dma_timeout(
    uint32_t instance, const uint8_t *bytes, uint32_t count, uint64_t timeout_us
) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi) return -1;
    uint8_t discard;
    return picokit_spi_dma_write(
        instance, spi, bytes, &discard, false, count, DMA_SIZE_8, true, timeout_us
    );
}
int32_t picokit_spi_write16_dma(uint32_t instance, const uint16_t *words, uint32_t count) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi) return -1;
    uint16_t discard;
    return picokit_spi_dma_write(instance, spi, words, &discard, false, count, DMA_SIZE_16, false, 0);
}
int32_t picokit_spi_write16_dma_timeout(
    uint32_t instance, const uint16_t *words, uint32_t count, uint64_t timeout_us
) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi) return -1;
    uint16_t discard;
    return picokit_spi_dma_write(
        instance, spi, words, &discard, false, count, DMA_SIZE_16, true, timeout_us
    );
}
int32_t picokit_spi_transfer_dma(uint32_t instance, const uint8_t *tx, uint8_t *rx, uint32_t count) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi) return -1;
    return picokit_spi_dma_write(instance, spi, tx, rx, true, count, DMA_SIZE_8, false, 0);
}
int32_t picokit_spi_transfer_dma_timeout(
    uint32_t instance, const uint8_t *tx, uint8_t *rx, uint32_t count, uint64_t timeout_us
) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi) return -1;
    return picokit_spi_dma_write(
        instance, spi, tx, rx, true, count, DMA_SIZE_8, true, timeout_us
    );
}
int32_t picokit_spi_transfer16_dma(uint32_t instance, const uint16_t *tx, uint16_t *rx, uint32_t count) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi) return -1;
    return picokit_spi_dma_write(instance, spi, tx, rx, true, count, DMA_SIZE_16, false, 0);
}
int32_t picokit_spi_transfer16_dma_timeout(
    uint32_t instance, const uint16_t *tx, uint16_t *rx, uint32_t count, uint64_t timeout_us
) {
    spi_inst_t *spi = picokit_spi(instance);
    if (!spi) return -1;
    return picokit_spi_dma_write(
        instance, spi, tx, rx, true, count, DMA_SIZE_16, true, timeout_us
    );
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
    if (!spi || !picokit_valid_result_count(count) || (!tx && count) || (!rx && count)) return -1;
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
    if (pin >= PICOKIT_GPIO_COUNT || edge < 1 || edge > 3) return -1;
    __atomic_store_n(&picokit_interrupt_events[pin], 0u, __ATOMIC_RELAXED);
    uint32_t events = edge == 1 ? GPIO_IRQ_EDGE_RISE : edge == 2 ? GPIO_IRQ_EDGE_FALL : GPIO_IRQ_EDGE_RISE | GPIO_IRQ_EDGE_FALL;
    gpio_set_irq_enabled_with_callback(pin, events, true, &picokit_gpio_irq);
    return 0;
}

void picokit_interrupt_disable(uint32_t pin) {
    if (pin >= PICOKIT_GPIO_COUNT) return;
    gpio_set_irq_enabled(pin, GPIO_IRQ_EDGE_RISE | GPIO_IRQ_EDGE_FALL, false);
    __atomic_store_n(&picokit_interrupt_events[pin], 0u, __ATOMIC_RELAXED);
}

uint32_t picokit_interrupt_take(uint32_t pin) {
    if (pin >= PICOKIT_GPIO_COUNT) return 0;
    return __atomic_exchange_n(&picokit_interrupt_events[pin], 0u, __ATOMIC_ACQ_REL);
}

static bool picokit_valid_watchdog_timeout_ms(uint32_t timeout_ms) {
#if PICO_RP2040
    // The SDK's watchdog counter runs at half-rate on RP2040 because of
    // erratum RP2040-E1; watchdog_enable asserts above this board limit.
    return timeout_ms <= WATCHDOG_LOAD_BITS / 2000u;
#else
    return timeout_ms <= WATCHDOG_LOAD_BITS / 1000u;
#endif
}
int32_t picokit_watchdog_enable(uint32_t timeout_ms, uint32_t pause_on_debug) {
    if (!picokit_valid_watchdog_timeout_ms(timeout_ms) || pause_on_debug > 1) return -1;
    watchdog_enable(timeout_ms, pause_on_debug != 0);
    return 0;
}
void picokit_watchdog_update(void) { watchdog_update(); }
