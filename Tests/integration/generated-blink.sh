#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
swiftpico=${SWIFTPICO_ROOT:-"$root/../SwiftPico"}
swiftpico=$(CDPATH= cd -- "$swiftpico" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export PATH="/opt/homebrew/bin:$PATH"

for board in pico pico_w pico2 pico2_w; do
    project="$tmp/Blink-$board"
    swift run --build-system native --package-path "$swiftpico" swiftpico init \
        --board "$board" --name Blink --template blink --path "$project" \
        --pico-kit-path "$root"

    source="$project/Sources/Blink/main.swift"
    test -s "$source"
    rg -Fq 'import PicoKit' "$source"
    if test "$board" = pico_w || test "$board" = pico2_w; then
        rg -Fq 'BoardLED(board:' "$source"
        if test "$board" = pico_w; then
            rg -Fq '.picoW' "$source"
        else
            rg -Fq '.pico2W' "$source"
        fi
        if rg -Fq 'pinMode(25' "$source"; then
            echo "Generated W Blink template used GPIO25: $board" >&2
            exit 1
        fi
    else
        rg -Fq 'pinMode(25, .output)' "$source"
        rg -Fq 'digitalWrite(25, .high)' "$source"
        if rg -Fq 'BoardLED(board:' "$source"; then
            echo "Generated non-W Blink template used BoardLED: $board" >&2
            exit 1
        fi
    fi
done

echo "Generated Blink template integration passed"
