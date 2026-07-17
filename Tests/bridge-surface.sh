#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
header="$root/Firmware/PicoKitSDKBridge.h"
bridge="$root/Firmware/PicoKitSDKBridge.c"
gpio_facade="$root/Firmware/PicoKitGPIOFacade.c"

test -s "$header"
test -s "$bridge"
test -s "$gpio_facade"

for symbol in $(rg -o 'picokit_[A-Za-z0-9_]+' "$header" | sort -u); do
    if ! rg -q "^(static )?(int32_t|uint32_t|uint64_t|void) ${symbol}[[:space:]]*\\(" \
        "$bridge" "$gpio_facade"; then
        echo "bridge declaration has no definition: $symbol" >&2
        exit 1
    fi
done

# Keep the reverse direction covered too: a non-static bridge definition that
# is not declared in the imported header cannot be reached safely from Swift
# and is usually an accidental ABI drift.
definitions=$(rg --no-filename -o \
    '^(int32_t|uint32_t|uint64_t|void) picokit_[A-Za-z0-9_]+[[:space:]]*\(' \
    "$bridge" "$gpio_facade" \
    | sed -E 's/^(int32_t|uint32_t|uint64_t|void) (picokit_[A-Za-z0-9_]+).*/\2/' \
    | sort -u) || {
    echo "could not extract bridge definitions" >&2
    exit 1
}
test -n "$definitions"

while read -r symbol; do
    test -n "$symbol" || continue
    if ! rg -q "${symbol}[[:space:]]*\\(" "$header"; then
        echo "bridge definition is missing from the public header: $symbol" >&2
        exit 1
    fi
done <<EOF
$definitions
EOF

echo "PicoKit bridge declaration surface validation passed"
