#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bridge="$root/Firmware/PicoKitSDKBridge.c"
header="$root/Firmware/PicoKitSDKBridge.h"
gpio_facade="$root/Firmware/PicoKitGPIOFacade.c"

# GPIO output updates must stay on the SDK's atomic set/clear/XOR register
# paths. A read-modify-write toggle can lose another core's simultaneous bit.
grep -Fq 'gpio_put(pin, value != 0);' "$gpio_facade"
grep -Fq 'gpio_xor_mask(1u << pin);' "$gpio_facade"
grep -Fq 'gpio_set_mask(mask & PICOKIT_GPIO_MASK);' "$gpio_facade"
grep -Fq 'gpio_clr_mask(mask & PICOKIT_GPIO_MASK);' "$gpio_facade"
grep -Fq 'gpio_xor_mask(mask & PICOKIT_GPIO_MASK);' "$gpio_facade"
if awk '
    /int32_t picokit_gpio_toggle\(/ { inside = 1 }
    inside && /gpio_get\(/ { found = 1 }
    inside && /^}/ { inside = 0 }
    END { exit found ? 0 : 1 }
' "$gpio_facade"; then
    echo "single-pin toggle regressed to read-modify-write" >&2
    exit 1
fi

# GPIO IRQ delivery crosses the SDK interrupt callback and foreground Swift.
# Keep the producer, consumer, and lifecycle reset operations atomic.
grep -Fq '__atomic_fetch_or(&picokit_interrupt_events[gpio]' "$bridge"
grep -Fq '__atomic_exchange_n(&picokit_interrupt_events[pin]' "$bridge"
grep -Fq '__atomic_store_n(&picokit_interrupt_events[pin]' "$bridge"
grep -Fq 'picokit_status_led_initialization_state' "$bridge"
grep -Fq 'status_led_init()' "$bridge"
grep -Fq '__atomic_compare_exchange_n(' "$bridge"
for state in picokit_stdio_initialization_state picokit_status_led_initialization_state picokit_adc_initialization_state; do
    grep -Fq "__atomic_load_n(&$state" "$bridge"
done
grep -Fq '&picokit_stdio_initialization_state, initialized ? 2u' "$bridge"
grep -Fq '&picokit_status_led_initialization_state, initialized ? 2u' "$bridge"
grep -Fq '&picokit_adc_initialization_state, 2u, __ATOMIC_RELEASE' "$bridge"
grep -Fq 'void picokit_interrupt_disable(uint32_t pin);' "$header"

echo "PicoKit GPIO and interrupt atomicity coverage passed"
