#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
swiftpico=${SWIFTPICO_ROOT:-"$root/../SwiftPico"}
swiftpico=$(CDPATH= cd -- "$swiftpico" && pwd)

# Keep nested pioasm and host-tool builds native on Apple Silicon.
export PATH="/opt/homebrew/bin:$PATH"
export CMAKE_OSX_ARCHITECTURES="$(uname -m)"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

run_cli() {
    swift run --build-system native --package-path "$swiftpico" swiftpico "$@"
}

# Build one real firmware project to produce the Embedded Swift PicoKit module.
# The generated sources below are then checked against that exact module and
# bridge surface without rebuilding the SDK for every template.
anchor="$tmp/anchor"
run_cli init --board pico --name TemplateTypecheck --template blink \
    --path "$anchor" --skip-resolve --pico-kit-path "$root" >/dev/null
run_cli build --configuration release --context "$anchor/swiftpico.json" >/dev/null

module_dir="$anchor/Firmware/build"
test -s "$module_dir/PicoKit.swiftmodule"

for template in blink serial adc pwm i2c spi interrupt watchdog; do
    project="$tmp/$template"
    run_cli init --board pico --name "$template" --template "$template" \
        --path "$project" --skip-resolve --pico-kit-path "$root" >/dev/null
    source="$project/Sources/$template/main.swift"
    test -s "$source"
    swiftc -typecheck \
        -target armv6m-none-none-eabi \
        -enable-experimental-feature Embedded \
        -parse-as-library \
        -I "$module_dir" \
        -Xcc -fmodule-map-file="$root/Firmware/PicoKitSDKBridge.modulemap" \
        -Xcc -I="$root/Firmware" \
        "$source"
done

echo "Generated PicoKit templates typecheck passed"
