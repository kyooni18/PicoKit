#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bridge="$root/Firmware/PicoKitSDKBridge.c"
gpioFacade="$root/Firmware/PicoKitGPIOFacade.c"
cmakeFile="$root/Firmware/CMakeLists.txt"
swiftBuses="$root/Sources/PicoKitHAL/Buses.swift"
swiftSerial="$root/Sources/PicoKitHAL/Serial.swift"
rp2350DMA="$root/Vendor/pico-sdk/src/rp2350/hardware_regs/include/hardware/regs/dma.h"

test -s "$rp2350DMA"
grep -Fq 'set(PICOKIT_COMPILED_BOARD 255)' "$cmakeFile"
grep -Fq 'PICO_BOARD STREQUAL "pico2_w"' "$cmakeFile"
test "$(awk '/pico_sdk_init\(\)/ { print NR; exit }' "$cmakeFile")" -lt \
    "$(awk '/set\(PICOKIT_COMPILED_BOARD 255\)/ { print NR; exit }' "$cmakeFile")"
grep -Fq 'case .pico2W: 3' "$root/Sources/PicoKitHAL/GPIO.swift"
grep -Fq '#define DMA_CH0_TRANS_COUNT_COUNT_BITS   _u(0x0fffffff)' "$rp2350DMA"

# Keep PWM period arithmetic wide until the division. A UInt32 frequency must
# not wrap divider * frequency_hz before the firmware validates the period.
grep -Fq 'uint64_t denominator = (uint64_t)divider * frequency_hz;' "$bridge"
grep -Fq 'uint32_t wrap = (uint32_t)((uint64_t)clock_hz / denominator);' "$bridge"
grep -Fq 'A rejected configuration must leave the GPIO usable' "$bridge"
test "$(awk '/uint32_t wrap = \(uint32_t\)\(\(uint64_t\)clock_hz \/ denominator\)/ { print NR; exit }' "$bridge")" -lt \
    "$(awk '/gpio_set_function\(pin, GPIO_FUNC_PWM\)/ { print NR; exit }' "$bridge")"
grep -Fq 'uint32_t chunk = count > (uint32_t)INT_MAX ? (uint32_t)INT_MAX : count;' "$bridge"
grep -Fq 'count -= chunk;' "$bridge"
grep -Fq 'alignment < sizeof(void *)' "$bridge"
grep -Fq 'int posix_memalign(void **pointer, size_t alignment, size_t size);' "$bridge"
grep -Fq 'miso < -1 || (miso >= 0 && !picokit_valid_gpio' "$bridge"
grep -Fq 'if (slice >= NUM_PWM_SLICES || channel > 1 || wrap > UINT16_MAX) return;' "$bridge"
grep -Fq 'picokit_pwm_init_with_actual_frequency' "$bridge"
grep -Fq 'picokit_pwm_slice_channel_claims' "$bridge"
grep -Fq 'void picokit_pwm_release(uint32_t pin)' "$bridge"
grep -Fq 'static void picokit_spi_recover_after_timeout(spi_inst_t *spi)' "$bridge"
grep -Fq 'spi_get_hw(spi)->cr1 &= ~SPI_SSPCR1_SSE_BITS;' "$bridge"
grep -Fq 'spi_get_hw(spi)->icr = SPI_SSPICR_RORIC_BITS;' "$bridge"
grep -Fq 'actual_frequency_out' "$bridge"
grep -Fq 'picokit_i2c_init_with_actual_frequency' "$bridge"
grep -Fq 'uint32_t actual_frequency = i2c_init(i2c, frequency_hz);' "$bridge"
grep -Fq '(uint16_t)(scaled > wrap ? wrap : scaled)' "$bridge"
grep -Fq '(uint16_t)(level > wrap ? wrap : level)' "$bridge"
grep -Fq 'slice >= NUM_PWM_SLICES' "$bridge"
if ! awk '
/static int32_t picokit_pwm_init_impl/ { inside = 1 }
inside && /if \(wrap < 2 \|\| wrap > 65536\)/ { validated = 1 }
inside && /gpio_set_function\(pin, GPIO_FUNC_PWM\)/ {
    if (!validated) exit 1
    changed = 1
}
inside && /^}/ {
    if (changed) exit 0
    inside = 0
}
END { if (!changed) exit 1 }
' "$bridge"; then
    echo "PWM setup mutates the pin before frequency validation" >&2
    exit 1
fi
grep -Fq 'nostop > 1' "$bridge"
grep -Fq 'nostop != 0' "$bridge"
grep -Fq 'address < 0x08 || address > 0x77' "$bridge"
grep -Fq 'i2c_read_timeout_us(' "$bridge"
grep -Fq 'uint64_t timeout_us, uint32_t nostop)' "$bridge"
grep -Fq 'void picokit_i2c_recover(uint32_t instance)' "$bridge"
grep -Fq 'return nostop ? -1 : 0;' "$bridge"
grep -Fq '!picokit_valid_i2c_pins(instance, sda, scl)' "$bridge"
grep -Fq '!picokit_valid_spi_pins(instance, sck, mosi' "$bridge"
grep -Fq 'sck == mosi || (miso >= 0' "$bridge"
grep -Fq '!picokit_valid_uart_pins(instance, tx, rx)' "$bridge"
grep -Fq 'uint32_t transferred = 0;' "$bridge"
grep -Fq 'uart_get_hw(uart)->dr = bytes[transferred++];' "$bridge"
grep -Fq 'picokit_uart_write_dma_timeout' "$bridge"
grep -Fq 'dma_channel_cleanup((uint)channel);' "$bridge"
grep -Fq 'UART_FUNCSEL_NUM(uart, tx)' "$bridge"
grep -Fq 'UART_FUNCSEL_NUM(uart, rx)' "$bridge"
grep -Fq 'picokit_uart_init_with_actual_baud_rate' "$bridge"
grep -Fq 'uint32_t actual_baud_rate = uart_init(uart, baud_rate);' "$bridge"
grep -Fq '#if PICOKIT_ENABLE_USB' "$bridge"
grep -Fq '#include "pico/stdio_usb.h"' "$bridge"
grep -Fq 'if (!picokit_stdio_connected()) return PICOKIT_STDIO_STATUS_DISCONNECTED;' "$bridge"
grep -Fq 'const uint32_t poll_slice_us = 10000;' "$bridge"
grep -Fq 'return PICOKIT_STDIO_STATUS_NO_DATA;' "$bridge"
test "$(rg -n '^#if PICOKIT_ENABLE_USB$' "$bridge" | wc -l | tr -d ' ')" -ge 3
grep -Fq 'uint32_t picokit_compiled_chip(void)' "$bridge"
grep -Fq 'uint32_t picokit_compiled_board(void)' "$bridge"
grep -Fq 'PICOKIT_COMPILED_BOARD' "$bridge"
if grep -Fq 'PICO_RUNTIME_INIT_FUNC_RUNTIME(picokit_runtime_init_stdio' "$bridge"; then
    echo "USB stdio must not run from the pre-main runtime initializer" >&2
    exit 1
fi
grep -Fq '__attribute__((constructor(101)))' "$bridge"
grep -Fq 'picokit_initialize_usb_stdio' "$bridge"
grep -Fq 'UART chip does not match compiled Pico chip' "$root/Sources/PicoKitHAL/UART.swift"
grep -Fq 'GPIO chip does not match compiled Pico chip' "$root/Sources/PicoKitHAL/GPIO.swift"
grep -Fq 'static int32_t picokit_gpio_validate(uint32_t chip, uint32_t pin)' "$gpioFacade"
grep -Fq '#define PICOKIT_GPIO_COMPILED_CHIP 0u' "$gpioFacade"
grep -Fq '#define PICOKIT_GPIO_COMPILED_CHIP 1u' "$gpioFacade"
grep -Fq 'int32_t picokit_gpio_reset_pulse' "$gpioFacade"
grep -Fq 'PICOKIT_GPIO_STATUS_CHIP_MISMATCH = -2' "$root/Firmware/PicoKitSDKBridge.h"
grep -Fq 'let chipMismatch = PICOKIT_GPIO_STATUS_CHIP_MISMATCH' "$root/Sources/PicoKitHAL/GPIO.swift"
grep -Fq 'let chipMismatch: Int32 = -2' "$root/Sources/PicoKitHAL/GPIO.swift"
if grep -Eq 'picokit_gpio_(init|set_direction)' "$root/Firmware/PicoKitSDKBridge.h"; then
    echo "low-level GPIO primitives escaped the high-level C facade" >&2
    exit 1
fi
grep -Fq 'public convenience init() throws(PicoKitError)' "$root/Sources/PicoKitHAL/GPIO.swift"
grep -Fq 'unknown compiled Pico board' "$root/Sources/PicoKitHAL/GPIO.swift"
grep -Fq 'public static var compiled: PicoGPIO' "$root/Sources/PicoKitHAL/GPIO.swift"
if grep -Eq 'class PicoGPIO[^\{]*Sendable' "$root/Sources/PicoKitHAL/GPIO.swift"; then
    echo "PicoGPIO must not promise synchronization through Sendable" >&2
    exit 1
fi
grep -Fq 'static var compiled: Self' "$root/Sources/PicoKitHAL/GPIO.swift"
grep -Fq 'static var compiled: Self?' "$root/Sources/PicoKitHAL/GPIO.swift"
grep -Fq 'public init(chip: PicoChip = .compiled)' "$root/Sources/PicoKitHAL/GPIO.swift"
grep -Fq 'chip: PicoChip = .compiled' "$root/Sources/PicoKitHAL/UART.swift"
grep -Fq 'case .ownershipConflict(let reason): reason' "$root/Sources/PicoKitCore/PicoKitCore.swift"
grep -Fq 'is zero, overflows, or is unsupported' "$root/Sources/PicoKitCore/PicoKitCore.swift"
grep -Fq 'let led = try BoardLED()' "$root/Sources/Blink/main.swift"
grep -Fq 'self.gpio = PicoGPIO.compiled' "$root/Sources/PicoKitHAL/Serial.swift"
grep -Fq 'try! gpio.pinMode(pin, mode)' "$root/Sources/PicoKitHAL/Serial.swift"
grep -Fq 'try! gpio.digitalWrite(pin, state)' "$root/Sources/PicoKitHAL/Serial.swift"
grep -Fq 'SPI chip-select GPIO does not match compiled Pico chip' "$swiftBuses"
grep -Fq 'guard bitOrder == .mostSignificantBitFirst' "$swiftBuses"
grep -Fq 'bit_order != 0' "$bridge"
grep -Fq 'spi_set_format(spi, data_bits, cpol, cpha, SPI_MSB_FIRST)' "$bridge"
grep -Fq 'if (result != (int32_t)count) i2c->restart_on_next = false;' "$bridge"
grep -Fq 'let compiledChip = picokit_compiled_chip() == 0 ? PicoChip.rp2040 : .rp2350' "$swiftBuses"
grep -Fq 'PicoGPIO(chip: compiledChip)' "$swiftBuses"
grep -Fq '#if PICO_RP2040' "$bridge"
grep -Fq 'operation: "I2C write", transferred: Int(result), expected: Int(count)' "$swiftBuses"
if grep -Fq 'picokit_gpio_' "$swiftSerial"; then
    echo "Pico sketch facade bypasses PicoGPIO" >&2
    exit 1
fi
grep -Fq 'invalid read arguments must never cause a prefix' "$swiftBuses"
grep -Fq '_ = try picoKitTransferCount(count, operation: "I2C read")' "$swiftBuses"
grep -Fq 'spi_read_blocking(spi, repeated_tx_data' "$bridge"
grep -Fq 'int32_t picokit_spi_read_timeout' "$bridge"
grep -Fq 'int32_t picokit_spi_read16' "$bridge"
grep -Fq 'int32_t picokit_spi_read16_timeout' "$bridge"
grep -Fq 'const uint32_t fifo_depth = 8;' "$bridge"
grep -Fq '(rx_remaining < tx_remaining || rx_remaining - tx_remaining < fifo_depth)' "$bridge"
grep -Fq 'int32_t picokit_spi_transfer16' "$bridge"
grep -Fq 'spi_get_hw(spi)->dr = tx[index];' "$bridge"
grep -Fq 'int32_t picokit_spi_write16_timeout' "$bridge"
grep -Fq 'int32_t picokit_spi_transfer_dma' "$bridge"
grep -Fq 'int32_t picokit_spi_transfer16_dma' "$bridge"
grep -Fq 'picokit_spi_write_dma_timeout' "$bridge"
grep -Fq 'picokit_spi_write16_dma_timeout' "$bridge"
grep -Fq 'picokit_spi_transfer_dma_timeout' "$bridge"
grep -Fq 'picokit_spi_transfer16_dma_timeout' "$bridge"
grep -Fq 'dma_channel_cleanup((uint)tx_channel);' "$bridge"
grep -Fq 'dma_channel_cleanup((uint)rx_channel);' "$bridge"
grep -Fq 'dma_channel_unclaim((uint)channel);' "$bridge"
grep -Fq 'picokit_uart_dma_channels[instance] = -1;' "$bridge"
grep -Fq 'picokit_spi_dma_tx_channels[instance] = -1;' "$bridge"
grep -Fq 'picokit_spi_dma_rx_channels[instance] = -1;' "$bridge"
grep -Fq 'picokit_dma_owner_token' "$bridge"
grep -Fq 'picokit_uart_dma_owners' "$bridge"
grep -Fq 'picokit_spi_dma_owners' "$bridge"
grep -Fq 'owner == 0u' "$bridge"
grep -Fq 'ownershipConflict("SPI DMA is owned by another PicoSPI")' "$swiftBuses"
grep -Fq 'picokit_i2c_recover(instance.rawValue)' "$swiftBuses"
grep -Fq 'guard count > 0 else' "$swiftBuses"
# DMA completion must stay on the error-aware polling path. The SDK's
# blocking wait and direct abort helpers bypass the RP2350 cleanup ordering
# and would regress timeout/fault recovery if reintroduced here.
if grep -Fq 'dma_channel_wait_for_finish_blocking' "$bridge"; then
    echo "PicoKit DMA bridge regressed to blocking completion wait" >&2
    exit 1
fi
if grep -Fq 'dma_channel_abort(' "$bridge"; then
    echo "PicoKit DMA bridge regressed to direct channel abort" >&2
    exit 1
fi
grep -Fq '#define PICOKIT_GPIO_COUNT 30u' "$bridge"
grep -Fq 'static volatile uint32_t picokit_interrupt_events[PICOKIT_GPIO_COUNT];' "$bridge"
grep -Fq 'if (gpio < PICOKIT_GPIO_COUNT)' "$bridge"
grep -Fq 'if (pin >= PICOKIT_GPIO_COUNT || edge < 1 || edge > 3)' "$bridge"
grep -Fq 'if (pin >= PICOKIT_GPIO_COUNT) return 0;' "$bridge"
grep -Fq 'static bool picokit_valid_gpio(uint32_t pin)' "$bridge"
grep -Fq 'static bool picokit_valid_dma_count(uint32_t count)' "$bridge"
grep -Fq 'static bool picokit_valid_i2c_frequency(uint32_t frequency_hz)' "$bridge"
grep -Fq 'static bool picokit_valid_spi_frequency(uint32_t frequency_hz)' "$bridge"
grep -Fq 'static bool picokit_valid_watchdog_timeout_ms(uint32_t timeout_ms)' "$bridge"
grep -Fq 'WATCHDOG_LOAD_BITS / 2000u' "$bridge"
grep -Fq 'WATCHDOG_LOAD_BITS / 1000u' "$bridge"
grep -Fq 'pause_on_debug > 1' "$bridge"
awk '
    /int32_t picokit_watchdog_enable/ { inside = 1 }
    inside && /if \(!picokit_valid_watchdog_timeout_ms/ { guard_line = NR }
    inside && /watchdog_enable\(timeout_ms/ {
        if (!guard_line || guard_line >= NR) exit 1
        exit 0
    }
    inside && /^}/ { inside = 0 }
' "$bridge"
grep -Fq 'invalid_params/assert' "$bridge"
awk '
    /static int32_t picokit_i2c_init_impl/ { inside = 1 }
    inside && /picokit_valid_i2c_frequency\(frequency_hz\)/ { guard_line = NR }
    inside && /uint32_t actual_frequency = i2c_init\(/ {
        if (!guard_line || guard_line >= NR) exit 1
        exit 0
    }
    inside && /^}/ { inside = 0 }
' "$bridge"
awk '
    /int32_t picokit_spi_init_config/ { inside = 1 }
    inside && /picokit_valid_spi_frequency\(frequency_hz\)/ { guard_line = NR }
    inside && /uint32_t actual = spi_init\(/ {
        if (!guard_line || guard_line >= NR) exit 1
        exit 0
    }
    inside && /^}/ { inside = 0 }
' "$bridge"
grep -Fq '#if PICO_RP2040' "$bridge"
grep -Fq 'return count <= 0x0fffffffu;' "$bridge"
grep -Fq 'dma_encode_transfer_count((uint)count)' "$bridge"
grep -Fq 'static bool picokit_valid_result_count(uint32_t count)' "$bridge"
grep -Fq 'return count <= (uint32_t)INT32_MAX;' "$bridge"
test "$(rg -o 'picokit_valid_result_count\(count\)' "$bridge" | wc -l | tr -d ' ')" -eq 15
test "$(rg -o '!picokit_valid_dma_count\(count\) \|\| !picokit_valid_result_count\(count\)' "$bridge" | wc -l | tr -d ' ')" -eq 2
grep -Fq 'static bool picokit_dma_channel_has_error(uint channel)' "$bridge"
grep -Fq 'DMA_CH0_CTRL_TRIG_AHB_ERROR_BITS' "$bridge"
grep -Fq 'return -4;' "$bridge"
grep -Fq 'static bool picokit_adc_gpio_initialized[NUM_ADC_CHANNELS - 1];' "$bridge"
grep -Fq 'static critical_section_t picokit_adc_critical_section;' "$bridge"
grep -Fq 'critical_section_enter_blocking(&picokit_adc_critical_section);' "$bridge"
grep -Fq 'critical_section_exit(&picokit_adc_critical_section);' "$bridge"
grep -Fq 'if (channel >= NUM_ADC_CHANNELS) return -1;' "$bridge"
grep -Fq 'guard count != 0 else {' "$root/Sources/PicoKitHAL/Buses.swift"
grep -Fq 'guard transferCount != 0 else {' "$root/Sources/PicoKitHAL/Buses.swift"
grep -Fq 'if (count == 0) {' "$bridge"
grep -Fq 'adc_gpio_init(ADC_BASE_PIN + channel);' "$bridge"
grep -Fq 'channel == ADC_TEMPERATURE_CHANNEL_NUM' "$bridge"
grep -Fq 'static uint32_t picokit_adc_initialization_state;' "$bridge"
grep -Fq '__atomic_compare_exchange_n(' "$bridge"
grep -Fq '__atomic_store_n(&picokit_adc_initialization_state, 2u, __ATOMIC_RELEASE);' "$bridge"
grep -Fq 'int32_t status = picokit_gpio_validate(chip, pin);' "$gpioFacade"
grep -Fq 'if (output > 1 || initial_value > 1 || pull > 2 || drive > 3 || slew > 1)' "$gpioFacade"
echo "PicoKit bridge arithmetic validation passed"
