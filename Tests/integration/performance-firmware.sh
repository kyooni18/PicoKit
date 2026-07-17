#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
build_root=$(mktemp -d)
trap 'rm -rf "$build_root"' EXIT
# Keep nested SDK projects on the native toolchain on Apple Silicon.
export PATH="/opt/homebrew/bin:$PATH"
export CMAKE_OSX_ARCHITECTURES="$(uname -m)"

for board in pico pico2_w; do
    build="$build_root/$board"
    cmake -S "$root/Firmware" -B "$build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DPICO_BOARD="$board" \
        -DPICOKIT_PRODUCT=Performance \
        -DPICOKIT_SOURCE="$root/Sources/Performance/main.swift" \
        -DPICOKIT_ROOT="$root" \
        -DPICOKIT_ENABLE_USB=ON \
        -DPICOKIT_USB_STDOUT_TIMEOUT_US=1000000 \
        -DCMAKE_OSX_ARCHITECTURES="$(uname -m)"
    cmake --build "$build" --parallel

    test -s "$build/Performance.elf"
    test -s "$build/Performance.uf2"
    if command -v arm-none-eabi-nm >/dev/null 2>&1; then
        arm-none-eabi-nm "$build/Performance.elf" | grep -Eq '[[:space:]]picokit_gpio_toggle$'
        arm-none-eabi-nm "$build/Performance.elf" | grep -Eq '[[:space:]]picokit_gpio_toggle_mask$'
    fi
done

echo "PicoKit performance firmware build passed on RP2040 and RP2350"
