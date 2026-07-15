#!/bin/sh
set -eu

# Build the in-tree firmware directly for the RP2350 RISC-V platform.
# PICO_TOOLCHAIN_PATH must point at Raspberry Pi's Pico-compatible RISC-V
# toolchain; unlike a generic riscv64-elf compiler, it includes the RV32
# newlib/libgloss layout expected by the Pico SDK.
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain=${PICO_TOOLCHAIN_PATH:-}
if test -z "$toolchain"; then
    echo "PICO_TOOLCHAIN_PATH is required for the RP2350 RISC-V firmware gate" >&2
    exit 2
fi
test -d "$toolchain"
cmake_bin=$(command -v cmake)
ninja_bin=$(command -v ninja)

# On Apple Silicon, an x86_64 CMake/Ninja can select the x86_64 slice of a
# universal RISC-V GCC driver while the SDK toolchain's LTO plugin is arm64.
# Prefer the native Homebrew tools when they are installed; this keeps the
# existing invocation portable while avoiding an architecture-mixed probe.
if test "$(uname -s)" = Darwin && test "$(uname -m)" = arm64; then
    if test -x /opt/homebrew/bin/cmake && test -x /opt/homebrew/bin/ninja; then
        cmake_bin=/opt/homebrew/bin/cmake
        ninja_bin=/opt/homebrew/bin/ninja
    fi
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
build="$tmp/build"

set -- "$cmake_bin" -S "$root/Firmware" -B "$build" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$ninja_bin" \
    -DCMAKE_BUILD_TYPE=Release \
    -DPICO_BOARD=pico2 \
    -DPICO_PLATFORM=rp2350-riscv \
    -DPICOKIT_PRODUCT=PicoKitRISCV \
    -DPICOKIT_SOURCE="$root/Sources/Blink/main.swift" \
    -DPICOKIT_ENABLE_USB=ON \
    -DPICOKIT_BRIDGE_WARNINGS=ON \
    -DPICOKIT_ROOT="$root"
if test -n "${PICOKIT_SWIFT_COMPILER:-}"; then
    set -- "$@" -DCMAKE_Swift_COMPILER="$PICOKIT_SWIFT_COMPILER"
fi
PICO_TOOLCHAIN_PATH="$toolchain" "$@" >/dev/null
PICO_TOOLCHAIN_PATH="$toolchain" "$cmake_bin" --build "$build"

elf="$build/PicoKitRISCV.elf"
uf2="$build/PicoKitRISCV.uf2"
test -s "$elf"
test -s "$uf2"
nm="$toolchain/bin/riscv32-unknown-elf-nm"
test -x "$nm"
symbols_file="$build/PicoKitRISCV.symbols"
"$nm" -an "$elf" > "$symbols_file"
grep -Eq '[[:space:]]picokit_stdio_init$' "$symbols_file"
grep -Eq '[[:space:]]picokit_initialize_usb_stdio$' "$symbols_file"
grep -Eq '[[:space:]]stdio_usb_init$' "$symbols_file"
grep -Eq '[[:space:]]tusb_rhport_init$' "$symbols_file"
grep -Eq '[[:space:]]__pre_init_runtime_init_early_resets$' "$symbols_file"
grep -Eq '[[:space:]]__pre_init_runtime_init_clocks$' "$symbols_file"
grep -Eq '[[:space:]]__pre_init_runtime_init_post_clock_resets$' "$symbols_file"
grep -Eq '[[:space:]]__pre_init_runtime_init_boot_locks_reset$' "$symbols_file"
grep -Eq '[[:space:]]__pre_init_runtime_init_bootrom_locking_enable$' "$symbols_file"
grep -Eq '[[:space:]]__pre_init_runtime_init_spin_locks_reset$' "$symbols_file"
grep -Eq '[[:space:]]__pre_init_runtime_init_mutex$' "$symbols_file"
grep -Eq '[[:space:]]__pre_init_runtime_init_default_alarm_pool$' "$symbols_file"

echo "PicoKit RP2350 RISC-V firmware validation passed"
