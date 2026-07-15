#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

# Match the established firmware build procedure on Apple Silicon so nested
# pioasm uses native host tools rather than an x86_64 CMake/Ninja pair.
export PATH="/opt/homebrew/bin:$PATH"
export CMAKE_OSX_ARCHITECTURES="$(uname -m)"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
configure_log="$tmp/configure.log"
build_log="$tmp/build.log"
build="$tmp/build"

if ! cmake -S "$root/Firmware" -B "$build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DPICOKIT_PRODUCT=DefaultBoardProbe \
    -DPICOKIT_SOURCE="$root/Sources/Blink/main.swift" \
    -DPICOKIT_ENABLE_USB=ON \
    -DPICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS=1234 \
    -DPICOKIT_ROOT="$root" >"$configure_log" 2>&1; then
    cat "$configure_log" >&2
    exit 1
fi
grep -Fq "Defaulting target board (PICO_BOARD) to 'pico'" "$configure_log"
grep -Fq "PicoKit compiled board: pico (0)" "$configure_log"
grep -Fq 'PicoKit USB CDC connect wait: 1234 ms' "$configure_log"
grep -Fq "Using PicoKit Embedded Swift compiler:" "$configure_log"

if ! cmake --build "$build" --parallel >"$build_log" 2>&1; then
    cat "$build_log" >&2
    exit 1
fi

test -s "$build/DefaultBoardProbe.elf"
test -s "$build/DefaultBoardProbe.uf2"
echo "Default direct firmware build passed"
