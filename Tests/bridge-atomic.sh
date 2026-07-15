#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bridge="$root/Firmware/PicoKitSDKBridge.c"
header="$root/Firmware/PicoKitSDKBridge.h"

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

echo "PicoKit interrupt atomicity coverage passed"
