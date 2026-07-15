#!/bin/sh
set -eu

# Keep the documented direct CMake entry point independently covered. In
# particular, do not pass CMAKE_Swift_COMPILER here: Firmware/CMakeLists.txt
# must discover the Embedded Swift compiler itself.
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
# Match the existing firmware integrations on Apple Silicon, where the
# cross-compiler and picotool are installed under Homebrew's arm64 prefix.
export PATH="/opt/homebrew/bin:$PATH"
export CMAKE_OSX_ARCHITECTURES="$(uname -m)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cmake -S "$root/Firmware" -B "$tmp" -G Ninja \
    -DPICOKIT_ROOT="$root" \
    -DPICOKIT_PRODUCT=DirectCMake \
    -DPICOKIT_SOURCE="$root/Sources/Blink/main.swift" \
    -DPICO_BOARD=pico \
    -DPICOKIT_ENABLE_USB=OFF
cmake --build "$tmp"
test -s "$tmp/DirectCMake.elf"

echo "PicoKit direct CMake compiler-discovery build passed"
