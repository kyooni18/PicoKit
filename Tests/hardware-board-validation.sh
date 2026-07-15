#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$root/Tests/integration/generated-project.sh"
workflow="$root/.github/workflows/ci.yml"
usb_script="$root/Tests/integration/usb-disabled.sh"
riscv_script="$root/Tests/integration/riscv-firmware.sh"

grep -Fq 'board=${PICO_TEST_BOARD:-pico}' "$script"
grep -Fq 'export PATH="/opt/homebrew/bin:$PATH"' "$script"
grep -Fq 'expected_chip=RP2040' "$script"
grep -Fq 'expected_chip=RP2350' "$script"
grep -Fq 'target chip:[[:space:]]+$expected_chip' "$script"
grep -Fq 'in_bootloader=1' "$script"
grep -Fq 'Hardware flash passed; echo SKIPPED' "$script"
grep -Fq 'PICO_HARDWARE_REQUIRE_CDC' "$script"
grep -Fq 'picokit_runtime_init_stdio' "$script"
if grep -Fq 'echo "$info" | grep' "$script"; then
    echo "generated-project hardware identity check uses an unsafe pipeline" >&2
    exit 1
fi
grep -Fq 'stdio_usb_init' "$script"
grep -Fq '__pre_init_runtime_init_early_resets' "$script"
grep -Fq '__pre_init_runtime_init_clocks' "$script"
grep -Fq '__pre_init_runtime_init_post_clock_resets' "$script"
grep -Fq '__pre_init_runtime_init_mutex' "$script"
grep -Fq '__pre_init_runtime_init_install_ram_vector_table' "$script"
grep -Fq '__pre_init_runtime_init_default_alarm_pool' "$script"
if grep -Fq 'echo "$symbols" | grep' "$riscv_script"; then
    echo "RISC-V symbol checks use an unsafe pipeline" >&2
    exit 1
fi

for board in pico pico_w pico2 pico2_w; do
    grep -Fq "PICO_TEST_BOARD=$board sh Tests/integration/generated-project.sh" "$workflow"
done
grep -Fq 'for board in pico pico_w pico2 pico2_w; do' "$usb_script"
grep -Fq -- '-DPICOKIT_BRIDGE_WARNINGS=ON' "$riscv_script"

echo "PicoKit hardware board-selection validation passed"
