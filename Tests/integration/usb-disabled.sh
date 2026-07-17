#!/bin/sh
set -eu

# Requires CMake, Ninja, an Embedded Swift toolchain, and arm-none-eabi-gcc.
# Verify the supported no-USB configuration on every supported board alias.
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
swiftpico=${SWIFTPICO_ROOT:-"$root/../SwiftPico"}
swiftpico=$(CDPATH= cd -- "$swiftpico" && pwd)
export PATH="/opt/homebrew/bin:$PATH"
export CMAKE_OSX_ARCHITECTURES="$(uname -m)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

swift build --package-path "$swiftpico" --product swiftpico >/dev/null
cli="$swiftpico/.build/debug/swiftpico"

for board in pico pico_w pico2 pico2_w; do
    project="$tmp/$board"
    "$cli" init --board "$board" --name NoUSB --template blink --path "$project" --pico-kit-path "$root" >/dev/null
    perl -0pi -e 's/"initialize_usb_interface_at_start"\s*:\s*true/"initialize_usb_interface_at_start" : false/' "$project/swiftpico.json"
    case "$board" in
        pico) expected_compiled_board=0 ;;
        pico_w) expected_compiled_board=1 ;;
        pico2) expected_compiled_board=2 ;;
        pico2_w) expected_compiled_board=3 ;;
    esac
    build_log="$tmp/$board-build.log"
    (
        cd "$project"
        "$cli" build --configuration release --context "$project/swiftpico.json" >"$build_log" 2>&1
    )
    grep -Fq "PicoKit compiled board: $board ($expected_compiled_board)" "$build_log"
    grep -Fq 'PicoKit USB CDC: disabled' "$build_log"
    test -f "$project/Firmware/build/NoUSB.uf2"
done

echo "PicoKit USB-disabled firmware integration passed"
