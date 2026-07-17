#!/bin/sh
set -eu

if test "$#" -ne 1; then
    echo "usage: $0 <firmware.elf>" >&2
    exit 2
fi

elf=$1
test -s "$elf"
command -v arm-none-eabi-nm >/dev/null
# Allow modest compiler/SDK variation while catching lost constant folding,
# duplicated wrappers, or accidental runtime machinery in this hot path.
max_symbol_bytes=${PICOKIT_GPIO_MAX_SYMBOL_BYTES:-192}
max_total_bytes=${PICOKIT_GPIO_MAX_TOTAL_BYTES:-640}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
symbols="$tmp/symbols"
arm-none-eabi-nm -S "$elf" > "$symbols"

total=0
printf 'symbol,bytes\n'
for symbol in \
    picokit_gpio_set_mode picokit_gpio_configure picokit_gpio_write \
    picokit_gpio_read picokit_gpio_toggle picokit_gpio_set_mask \
    picokit_gpio_clear_mask picokit_gpio_toggle_mask picokit_gpio_reset_pulse
do
    hex_size=$(awk -v expected="$symbol" '$4 == expected { print $2; exit }' "$symbols")
    if test -z "$hex_size"; then
        echo "GPIO facade symbol is absent from $elf: $symbol" >&2
        exit 1
    fi
    size=$(printf '%d' "0x$hex_size")
    if test "$size" -gt "$max_symbol_bytes"; then
        echo "$symbol grew to $size bytes (limit: $max_symbol_bytes)" >&2
        exit 1
    fi
    total=$((total + size))
    printf '%s,%s\n' "$symbol" "$size"
done

if test "$total" -gt "$max_total_bytes"; then
    echo "GPIO facade grew to $total linked bytes (limit: $max_total_bytes)" >&2
    exit 1
fi
printf 'total,%s\n' "$total"
