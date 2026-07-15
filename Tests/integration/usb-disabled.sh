#!/bin/sh
set -eu

# Requires CMake, Ninja, an Embedded Swift toolchain, and arm-none-eabi-gcc.
# Verify the supported no-USB configuration on every supported board alias.
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
swiftpico=${SWIFTPICO_ROOT:-"$root/../SwiftPico"}
swiftpico=$(CDPATH= cd -- "$swiftpico" && pwd)
export PATH="/opt/homebrew/bin:$PATH"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

swift build --package-path "$swiftpico" --product swiftpico >/dev/null
cli="$swiftpico/.build/debug/swiftpico"

for board in pico pico_w pico2 pico2_w; do
    project="$tmp/$board"
    "$cli" init --board "$board" --name NoUSB --template blink --path "$project" --pico-kit-path "$root" >/dev/null
    perl -0pi -e 's/"initialize_usb_interface_at_start"\s*:\s*true/"initialize_usb_interface_at_start" : false/' "$project/swiftpico.json"
    (
        cd "$project"
        "$cli" build --configuration release --context "$project/swiftpico.json" >/dev/null
    )
    test -f "$project/Firmware/build/NoUSB.uf2"
done

echo "PicoKit USB-disabled firmware integration passed"
