#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
swiftpico=${SWIFTPICO_ROOT:-"$root/../SwiftPico"}
swiftpico=$(CDPATH= cd -- "$swiftpico" && pwd)
# Keep CMake and Ninja native on Apple Silicon. Pico SDK's nested pioasm
# build inherits these tools, and an x86_64 CMake can otherwise select the
# wrong slice of the universal cross-compiler's LTO plugin.
export PATH="/opt/homebrew/bin:$PATH"
board=${PICO_TEST_BOARD:-pico}
case "$board" in
    pico|pico_w) expected_chip=RP2040 ;;
    pico2|pico2_w) expected_chip=RP2350 ;;
    *) echo "Unsupported PICO_TEST_BOARD: $board" >&2; exit 1 ;;
esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

project="$tmp/SerialEcho-$board"
swift run --build-system native --package-path "$swiftpico" swiftpico init \
    --board "$board" --name SerialEcho --template serial --path "$project" \
    --pico-kit-path "$root"

source="$project/Sources/SerialEcho/main.swift"
grep -q 'Serial.read()' "$source"
grep -Fq 'Serial.write([byte])' "$source"
grep -Fq '.package(path: "'"$root"'")' "$project/Package.swift"
grep -Fq '"picoKitPath"' "$project/swiftpico.json"
grep -Fq 'PicoKit' "$project/swiftpico.json"

# CMake's PICOKIT_SOURCE remains the entry-point hint, while every Swift file
# below its directory is compiled. Replace the generated entry point with a
# tracked two-file fixture so this contract is exercised by every board gate.
cp "$root/Tests/fixtures/split-source/main.swift" "$source"
cp "$root/Tests/fixtures/split-source/Support.swift" "$project/Sources/SerialEcho/Support.swift"

in_bootloader=0
if test "${PICO_HARDWARE_TEST:-0}" = 1; then
    if info=$(picotool info 2>/dev/null); then
        in_bootloader=1
        info_file="$tmp/picotool-info"
        printf '%s\n' "$info" > "$info_file"
        if ! grep -Eq "target chip:[[:space:]]+$expected_chip" "$info_file"; then
            echo "Hardware board mismatch: expected $expected_chip for $board" >&2
            exit 1
        fi
    fi
fi

swift run --build-system native --package-path "$swiftpico" swiftpico build \
    --configuration release --context "$project/swiftpico.json"
uf2="$project/Firmware/build/SerialEcho.uf2"
elf="$project/Firmware/build/SerialEcho.elf"
test -s "$uf2"
test -s "$elf"
if command -v arm-none-eabi-nm >/dev/null 2>&1; then
    symbols="$tmp/SerialEcho.symbols"
    arm-none-eabi-nm -an "$elf" > "$symbols"
    grep -Eq '[[:space:]]picokit_runtime_init_stdio$' "$symbols"
    grep -Eq '[[:space:]]stdio_usb_init$' "$symbols"
    # TinyUSB's current tud_init() is an always-inline wrapper around the
    # exported root-hub initializer; assert the symbol that actually links.
    grep -Eq '[[:space:]]tud_rhport_init$' "$symbols"
    grep -Eq '[[:space:]]__pre_init_runtime_init_early_resets$' "$symbols"
    grep -Eq '[[:space:]]__pre_init_runtime_init_clocks$' "$symbols"
    grep -Eq '[[:space:]]__pre_init_runtime_init_post_clock_resets$' "$symbols"
    grep -Eq '[[:space:]]__pre_init_runtime_init_spin_locks_reset$' "$symbols"
    grep -Eq '[[:space:]]__pre_init_runtime_init_mutex$' "$symbols"
    grep -Eq '[[:space:]]__pre_init_runtime_init_install_ram_vector_table$' "$symbols"
    grep -Eq '[[:space:]]__pre_init_runtime_init_default_alarm_pool$' "$symbols"
fi

export SWIFTPICO_TEST_LOG="$tmp/picotool-args"
swift run --build-system native --package-path "$swiftpico" swiftpico flash \
    --context "$project/swiftpico.json" --picotool "$swiftpico/Tests/fake-picotool.sh"
test "$(sed -n '1p' "$SWIFTPICO_TEST_LOG")" = load
test "$(sed -n '2p' "$SWIFTPICO_TEST_LOG")" = -f
test "$(sed -n '3p' "$SWIFTPICO_TEST_LOG")" = "$uf2"

if test "${PICO_HARDWARE_TEST:-0}" != 1; then
    echo "Hardware flash and echo: SKIPPED (set PICO_HARDWARE_TEST=1)"
    echo "Temporary PicoKit project integration passed"
    exit 0
fi

set -- /dev/cu.usbmodem* /dev/ttyACM* /dev/ttyUSB*
devices=""
for device in "$@"; do
    test -e "$device" && devices="$devices $device"
done
set -- $devices
had_serial=0
test "$#" -eq 1 && had_serial=1
if test "$#" -ne 1 && test "$in_bootloader" -ne 1; then
    echo "Hardware flash and echo: SKIPPED (expected one serial device, found $#)"
    echo "Temporary PicoKit project integration passed"
    exit 0
fi

swift run --build-system native --package-path "$swiftpico" swiftpico flash --context "$project/swiftpico.json"
i=0
while test "$i" -lt 40; do
    set -- /dev/cu.usbmodem* /dev/ttyACM* /dev/ttyUSB*
    devices=""
    for device in "$@"; do
        test -e "$device" && devices="$devices $device"
    done
    set -- $devices
    test "$#" -eq 1 && break
    sleep 0.25
    i=$((i + 1))
done
if test "$#" -ne 1; then
    if test "$had_serial" -eq 1; then
        echo "Hardware echo failed: serial device did not return" >&2
        exit 1
    fi
    if test "${PICO_HARDWARE_REQUIRE_CDC:-0}" = 1; then
        echo "Hardware CDC failed: device did not enumerate after flash" >&2
        exit 1
    fi
    if picotool info >/dev/null 2>&1; then
        echo "Hardware flash passed; echo SKIPPED (board remains USB-controlled in BOOTSEL)"
        echo "Temporary PicoKit project integration passed"
        exit 0
    fi
    echo "Hardware flash failed: board is neither CDC serial nor USB-controlled BOOTSEL" >&2
    exit 1
fi

swift "$root/Tests/hardware/SerialEchoTest.swift" "$1"
echo "Hardware flash and echo passed on $1"
echo "Temporary PicoKit project integration passed"
