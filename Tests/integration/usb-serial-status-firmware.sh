#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
source_file="$root/Tests/fixtures/usb-serial-status/main.swift"
export PATH="/opt/homebrew/bin:$PATH"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for board in pico pico2; do
    build="$tmp/$board"
    cmake -S "$root/Firmware" -B "$build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DPICOKIT_ROOT="$root" \
        -DPICOKIT_PRODUCT=USBSerialStatusProbe \
        -DPICOKIT_SOURCE="$source_file" \
        -DPICO_BOARD="$board" \
        -DPICOKIT_ENABLE_USB=ON >/dev/null
    cmake --build "$build" --parallel >/dev/null
    test -s "$build/USBSerialStatusProbe.elf"
    test -s "$build/USBSerialStatusProbe.uf2"
    nm "$build/USBSerialStatusProbe.elf" |
        grep -Eq '[[:space:]]usb_reset_interface_control_xfer_cb$'
done

echo "PicoKit USB serial status firmware passed on RP2040 and RP2350"
