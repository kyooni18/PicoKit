#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$root/Tests/integration/generated-project.sh"
workflow="$root/.github/workflows/ci.yml"
usb_script="$root/Tests/integration/usb-disabled.sh"
riscv_script="$root/Tests/integration/riscv-firmware.sh"
cmake_options_script="$root/Tests/integration/cmake-options.sh"

grep -Fq 'board=${PICO_TEST_BOARD:-pico}' "$script"
grep -Fq 'export PATH="/opt/homebrew/bin:$PATH"' "$script"
grep -Fq 'expected_chip=RP2040' "$script"
grep -Fq 'expected_chip=RP2350' "$script"
grep -Fq 'target chip:[[:space:]]+$expected_chip' "$script"
grep -Fq 'in_bootloader=1' "$script"
grep -Fq 'had_serial=0' "$script"
grep -Fq 'Hardware echo failed: serial device did not return' "$script"
grep -Fq 'Hardware flash passed; echo SKIPPED' "$script"
grep -Fq 'PICO_HARDWARE_REQUIRE_CDC' "$script"
grep -Fq 'Hardware CDC failed: device did not enumerate after flash' "$script"
grep -Fq 'PICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS' "$root/Firmware/CMakeLists.txt"
grep -Fq 'PICOKIT_USB_STDOUT_TIMEOUT_US must fit UInt32' "$root/Firmware/CMakeLists.txt"
grep -Fq 'PICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS must fit UInt32' "$root/Firmware/CMakeLists.txt"
grep -Fq 'PICOKIT_USB_POST_CONNECT_WAIT_DELAY_MS' "$root/Firmware/CMakeLists.txt"
grep -Fq 'PICOKIT_USB_POST_CONNECT_WAIT_DELAY_MS must fit UInt32' "$root/Firmware/CMakeLists.txt"
grep -Fq 'PICOKIT_USB_CONNECTION_WITHOUT_DTR' "$root/Firmware/CMakeLists.txt"
grep -Fq 'picokit_initialize_usb_stdio' "$script"
test -x "$root/Tests/integration/direct-cmake.sh"
test -x "$root/Tests/integration/compiler-discovery.sh"
test -x "$cmake_options_script"
grep -Fq 'run: sh Tests/integration/direct-cmake.sh' "$workflow"
grep -Fq 'run: sh Tests/integration/compiler-discovery.sh' "$workflow"
grep -Fq 'run: sh Tests/integration/cmake-options.sh' "$workflow"
if grep -Fq 'echo "$info" | grep' "$script"; then
    echo "generated-project hardware identity check uses an unsafe pipeline" >&2
    exit 1
fi
grep -Fq 'stdio_usb_init' "$script"
grep -Fq '__pre_init_runtime_init_early_resets' "$script"
grep -Fq '__pre_init_runtime_init_clocks' "$script"
grep -Fq '__pre_init_runtime_init_post_clock_resets' "$script"
grep -Fq '__pre_init_runtime_init_boot_locks_reset' "$script"
grep -Fq '__pre_init_runtime_init_bootrom_locking_enable' "$script"
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
