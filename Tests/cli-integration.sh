#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cd "$root"
swift run picokit help | grep -q "PicoKit"
swift run picokit template | grep -q "watchdog"
swift run picokit init --board pico-w --name CLIValidation --template blink --path "$tmp/CLIValidation"
test -f "$tmp/CLIValidation/Firmware/PicoKitSDKBridge.c"
grep -q '"board" : "pico_w"' "$tmp/CLIValidation/picokit.json"
grep -q 'import PicoKit' "$tmp/CLIValidation/Sources/CLIValidation/main.swift"
