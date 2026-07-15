#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
# Keep nested SDK projects on the native toolchain on Apple Silicon.
export PATH="/opt/homebrew/bin:$PATH"
export CMAKE_OSX_ARCHITECTURES="$(uname -m)"

cmake -S "$root/Firmware" -B "$build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DPICO_BOARD=pico2_w \
    -DPICOKIT_PRODUCT=Performance \
    -DPICOKIT_SOURCE="$root/Sources/Performance/main.swift" \
    -DPICOKIT_ROOT="$root" \
    -DPICOKIT_ENABLE_USB=ON \
    -DCMAKE_OSX_ARCHITECTURES="$(uname -m)"
cmake --build "$build" --parallel

test -s "$build/Performance.elf"
test -s "$build/Performance.uf2"

echo "PicoKit performance firmware build passed"
