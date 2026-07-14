#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
swiftpico=${SWIFTPICO_ROOT:-"$root/../SwiftPico"}
swiftpico=$(CDPATH= cd -- "$swiftpico" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

project="$tmp/SerialEcho"
swift run --build-system native --package-path "$swiftpico" swiftpico init \
    --board pico --name SerialEcho --template serial --path "$project" \
    --pico-kit-path "$root"

source="$project/Sources/SerialEcho/main.swift"
grep -q 'Serial.read()' "$source"
grep -Fq 'Serial.write([byte])' "$source"
grep -Fq '.package(path: "'"$root"'")' "$project/Package.swift"
grep -Fq '"picoKitPath"' "$project/swiftpico.json"
grep -Fq 'PicoKit' "$project/swiftpico.json"

swift run --build-system native --package-path "$swiftpico" swiftpico build \
    --configuration release --context "$project/swiftpico.json"
uf2="$project/Firmware/build/SerialEcho.uf2"
test -s "$uf2"

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
if test "$#" -ne 1; then
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
test "$#" -eq 1 || { echo "Hardware echo failed: serial device did not return" >&2; exit 1; }

swift "$root/Tests/hardware/SerialEchoTest.swift" "$1"
echo "Hardware flash and echo passed on $1"
echo "Temporary PicoKit project integration passed"
