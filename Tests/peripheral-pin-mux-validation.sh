#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
rp2040="$root/Vendor/pico-sdk/src/rp2040/hardware_regs/include/hardware/regs/io_bank0.h"
rp2350="$root/Vendor/pico-sdk/src/rp2350/hardware_regs/include/hardware/regs/io_bank0.h"
bridge="$root/Firmware/PicoKitSDKBridge.c"
swiftBuses="$root/Sources/PicoKitHAL/Buses.swift"
swiftUART="$root/Sources/PicoKitHAL/UART.swift"

test -f "$rp2040"
test -f "$rp2350"
test -f "$bridge"
test -f "$swiftBuses"
test -f "$swiftUART"

check() {
    header=$1
    pin=$2
    function=$3
    pattern="#define IO_BANK0_GPIO${pin}_CTRL_FUNCSEL_VALUE_${function}"
    if ! rg -Fq "$pattern" "$header"; then
        echo "missing $function on GPIO$pin in $header" >&2
        exit 1
    fi
}

check_set() {
    header=$1
    function=$2
    pins=$3
    for pin in $pins; do
        check "$header" "$pin" "$function"
    done
}

check_peripheral_maps() {
    header=$1
    uart0_tx=$2
    uart0_rx=$3
    uart1_tx=$4
    uart1_rx=$5

    check_set "$header" UART0_TX "$uart0_tx"
    check_set "$header" UART0_RX "$uart0_rx"
    check_set "$header" UART1_TX "$uart1_tx"
    check_set "$header" UART1_RX "$uart1_rx"

    check_set "$header" I2C0_SDA "0 4 8 12 16 20 24 28"
    check_set "$header" I2C0_SCL "1 5 9 13 17 21 25 29"
    check_set "$header" I2C1_SDA "2 6 10 14 18 22 26"
    check_set "$header" I2C1_SCL "3 7 11 15 19 23 27"

    check_set "$header" SPI0_SCLK "2 6 18 22"
    check_set "$header" SPI0_TX "3 7 19 23"
    check_set "$header" SPI0_RX "0 4 16 20"
    check_set "$header" SPI1_SCLK "10 14 26"
    check_set "$header" SPI1_TX "11 15 27"
    check_set "$header" SPI1_RX "8 12 24 28"
}

check_peripheral_maps "$rp2040" \
    "0 12 16 28" "1 13 17 29" \
    "4 8 20 24" "5 9 21 25"
check_peripheral_maps "$rp2350" \
    "0 2 12 14 16 18 28" "1 3 13 15 17 19 29" \
    "4 6 8 10 20 22 24 26" "5 7 9 11 21 23 25 27"

# Keep the hand-written Swift and C maps synchronized with the SDK-backed
# expectations above. These assertions make a source-map drift fail even if
# the SDK headers themselves are unchanged.
rg -Fq 'txPins = [0, 12, 16, 28]' "$swiftUART"
rg -Fq 'rxPins = [1, 13, 17, 29]' "$swiftUART"
rg -Fq 'txPins = [4, 8, 20, 24]' "$swiftUART"
rg -Fq 'rxPins = [5, 9, 21, 25]' "$swiftUART"
rg -Fq 'txPins = [0, 2, 12, 14, 16, 18, 28]' "$swiftUART"
rg -Fq 'rxPins = [1, 3, 13, 15, 17, 19, 29]' "$swiftUART"
rg -Fq 'txPins = [4, 6, 8, 10, 20, 22, 24, 26]' "$swiftUART"
rg -Fq 'rxPins = [5, 7, 9, 11, 21, 23, 25, 27]' "$swiftUART"
rg -Fq 'static const uint32_t uart0_tx[] = {0, 12, 16, 28};' "$bridge"
rg -Fq 'static const uint32_t uart0_rx[] = {1, 13, 17, 29};' "$bridge"
rg -Fq 'static const uint32_t uart1_tx[] = {4, 8, 20, 24};' "$bridge"
rg -Fq 'static const uint32_t uart1_rx[] = {5, 9, 21, 25};' "$bridge"
rg -Fq 'static const uint32_t uart0_tx[] = {0, 2, 12, 14, 16, 18, 28};' "$bridge"
rg -Fq 'static const uint32_t uart0_rx[] = {1, 3, 13, 15, 17, 19, 29};' "$bridge"
rg -Fq 'static const uint32_t uart1_tx[] = {4, 6, 8, 10, 20, 22, 24, 26};' "$bridge"
rg -Fq 'static const uint32_t uart1_rx[] = {5, 7, 9, 11, 21, 23, 25, 27};' "$bridge"
rg -Fq 'validSCK = self == .spi0 ? [2, 6, 18, 22] : [10, 14, 26]' "$swiftBuses"
rg -Fq 'validMOSI = self == .spi0 ? [3, 7, 19, 23] : [11, 15, 27]' "$swiftBuses"
rg -Fq 'validMISO = self == .spi0 ? [0, 4, 16, 20] : [8, 12, 24, 28]' "$swiftBuses"
rg -Fq 'static const uint32_t spi0_sck[] = {2, 6, 18, 22};' "$bridge"
rg -Fq 'static const uint32_t spi0_mosi[] = {3, 7, 19, 23};' "$bridge"
rg -Fq 'static const uint32_t spi0_miso[] = {0, 4, 16, 20};' "$bridge"
rg -Fq 'static const uint32_t spi1_sck[] = {10, 14, 26};' "$bridge"
rg -Fq 'static const uint32_t spi1_mosi[] = {11, 15, 27};' "$bridge"
rg -Fq 'static const uint32_t spi1_miso[] = {8, 12, 24, 28};' "$bridge"

echo "PicoKit peripheral pin mux validation passed"
