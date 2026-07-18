#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export PATH="/opt/homebrew/bin:$PATH"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for board in pico pico2; do
    build="$tmp/$board"
    cmake -S "$root/Firmware" -B "$build" -G Ninja \
        -DPICOKIT_ROOT="$root" \
        -DPICOKIT_PRODUCT="DMAOwnership_$board" \
        -DPICOKIT_SOURCE="$root/Tests/fixtures/dma-ownership/main.swift" \
        -DPICO_BOARD="$board" \
        -DPICOKIT_ENABLE_USB=OFF >/dev/null
    cmake --build "$build" >/dev/null
    test -s "$build/DMAOwnership_$board.elf"
done

echo "PicoKit DMA ownership firmware builds passed for RP2040 and RP2350"
