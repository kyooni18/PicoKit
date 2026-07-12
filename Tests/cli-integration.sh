#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cd "$root"
swift run swiftpico help | grep -q "PicoKit"
swift run swiftpico template | grep -q "watchdog"
swift run swiftpico init --board pico-w --name CLIValidation --template blink --path "$tmp/CLIValidation" --skip-resolve
test -f "$tmp/CLIValidation/Package.swift"
test -f "$tmp/CLIValidation/Firmware/CMakeLists.txt"
test -f "$tmp/CLIValidation/swiftpico"
grep -q '"board" : "pico_w"' "$tmp/CLIValidation/swiftpico.json"
grep -q 'github.com/kyooni18/PicoKit.git' "$tmp/CLIValidation/Package.swift"
grep -q 'PICOKIT_ROOT}/Firmware/CMakeLists.txt' "$tmp/CLIValidation/Firmware/CMakeLists.txt"
grep -q 'import PicoKit' "$tmp/CLIValidation/Sources/CLIValidation/main.swift"
