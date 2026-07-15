#!/bin/sh
set -eu

# Exercise the supported compiler environment overrides without rebuilding a
# firmware image. The direct-CMake integration test separately covers the
# complete auto-discovery build.
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
export PATH="/opt/homebrew/bin:$PATH"
export CMAKE_OSX_ARCHITECTURES="$(uname -m)"

compiler=""
for candidate in "$HOME"/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-*.xctoolchain/usr/bin/swiftc; do
    if [ -x "$candidate" ]; then
        compiler="$candidate"
    fi
done
if [ -z "$compiler" ] && [ -n "${SWIFTLY_TOOLCHAINS_DIR:-}" ]; then
    for candidate in "$SWIFTLY_TOOLCHAINS_DIR"/swift-DEVELOPMENT-SNAPSHOT-*.xctoolchain/usr/bin/swiftc; do
        if [ -x "$candidate" ]; then
            compiler="$candidate"
        fi
    done
fi
test -x "$compiler"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

PICOKIT_SWIFT_COMPILER="$compiler" cmake -S "$root/Firmware" -B "$tmp/explicit" -G Ninja \
    -DPICOKIT_ROOT="$root" \
    -DPICOKIT_PRODUCT=CompilerExplicitProbe \
    -DPICOKIT_SOURCE="$root/Sources/Blink/main.swift" \
    -DPICO_BOARD=pico \
    -DPICOKIT_ENABLE_USB=OFF >"$tmp/explicit.log" 2>&1
grep -Fq "Using PicoKit Embedded Swift compiler: $compiler" "$tmp/explicit.log"

PICO_SWIFTC="$compiler" cmake -S "$root/Firmware" -B "$tmp/legacy" -G Ninja \
    -DPICOKIT_ROOT="$root" \
    -DPICOKIT_PRODUCT=CompilerLegacyProbe \
    -DPICOKIT_SOURCE="$root/Sources/Blink/main.swift" \
    -DPICO_BOARD=pico \
    -DPICOKIT_ENABLE_USB=OFF >"$tmp/legacy.log" 2>&1
grep -Fq "Using PicoKit Embedded Swift compiler: $compiler" "$tmp/legacy.log"

if PICOKIT_SWIFT_COMPILER="$tmp/missing-swiftc" cmake -S "$root/Firmware" -B "$tmp/invalid" -G Ninja \
    -DPICOKIT_ROOT="$root" \
    -DPICOKIT_PRODUCT=CompilerInvalidProbe \
    -DPICOKIT_SOURCE="$root/Sources/Blink/main.swift" \
    -DPICO_BOARD=pico \
    -DPICOKIT_ENABLE_USB=OFF >"$tmp/invalid.log" 2>&1; then
    echo "PicoKit accepted an invalid PICOKIT_SWIFT_COMPILER override" >&2
    exit 1
fi
grep -Fq "does not exist or is not executable" "$tmp/invalid.log"

echo "PicoKit compiler environment override validation passed"
