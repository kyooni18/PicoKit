#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
swiftpico=${SWIFTPICO_ROOT:-"$root/../SwiftPico"}
swiftpico=$(CDPATH= cd -- "$swiftpico" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export PATH="/opt/homebrew/bin:$PATH"
swift build --package-path "$swiftpico" --product swiftpico
cli="$swiftpico/.build/debug/swiftpico"
project="$tmp/RealLCD"

"$cli" init --board pico --name RealLCD --template blink \
    --path "$project" --skip-resolve --pico-kit-path "$root"
"$cli" build --configuration release --context "$project/swiftpico.json"
test -s "$project/Firmware/build/RealLCD.uf2"
echo "PicoKit mixed-case product-name integration passed"
