#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
reference="$root/Docs/11-api-reference.md"

command -v jq >/dev/null 2>&1 || {
    echo "jq is required for symbol-graph API coverage" >&2
    exit 1
}

symbols=$(mktemp -d)
trap 'rm -rf "$symbols"' EXIT
swift package --package-path "$root" dump-symbol-graph --output-dir "$symbols" >/dev/null

# The umbrella graph normally re-exports Core and HAL, but inspect the source
# module graphs independently as well so conditional firmware exports cannot
# silently escape documentation coverage.
types="$symbols/public-types.txt"
members="$symbols/public-members.txt"
: > "$types"
: > "$members"
for graph in PicoKit.symbols.json PicoKitCore.symbols.json PicoKitHAL.symbols.json; do
    jq -r '
        .symbols[]
        | select(.accessLevel == "public")
        | select(.kind.identifier == "swift.class" or
                 .kind.identifier == "swift.enum" or
                 .kind.identifier == "swift.protocol" or
                 .kind.identifier == "swift.struct")
        | .pathComponents[0]
    ' "$symbols/$graph" >> "$types"
    jq -r '
        .symbols[]
        | select(.accessLevel == "public")
        | select(.kind.identifier != "swift.func.op")
        | select(.names.title != "hashValue" and
                 .names.title != "hash(into:)" and
                 .names.title != "init(rawValue:)")
        | .pathComponents[-1]
        | sub("\\(.*$"; "")
    ' "$symbols/$graph" >> "$members"
done
sort -u -o "$types" "$types"
sort -u -o "$members" "$members"

# Keep the reference honest when a new public type is added. The explicit list
# below still checks overload-sensitive member names and documented conveniences.
while IFS= read -r symbol; do
    grep -Fq "$symbol" "$reference" || {
        echo "Docs/11-api-reference.md is missing public type $symbol" >&2
        exit 1
    }
done < "$types"

# Check public members as well as types. Synthesized hashing, raw-value
# initializers, and operators are compiler-provided implementation details;
# the API reference documents the authored surface. GPIO constants are
# intentionally documented as the compact `.gpio0 ... .gpio29` range.
while IFS= read -r symbol; do
    case "$symbol" in
        gpio[0-9]|gpio1[0-9]|gpio2[0-9]) continue ;;
    esac
    test -z "$symbol" || grep -Fq "$symbol" "$reference" || {
        echo "Docs/11-api-reference.md is missing public member $symbol" >&2
        exit 1
    }
done < "$members"

for symbol in \
    PicoChip PicoBoard PicoKitError PicoPin Duration Frequency PinMode PinState \
    DigitalIO PicoGPIO BoardLED Clock USBSerial PicoSerial Serial Pico UARTInstance \
    PicoUART PWMChannel PicoPWM PicoBacklight ADCChannel PicoADC I2CInstance PicoI2C SPIInstance \
    SPIMode SPIBitOrder SPIDataBits PicoSPI PinPull PinDriveStrength PinSlewRate \
    GPIOInterruptEdge PicoInterrupts PicoWatchdog disable pinMode digitalWrite digitalToggle \
    digitalRead analogRead analogWrite delay delayMicroseconds millis micros sleep \
    sleepMicroseconds releaseDMAChannel releaseDMAChannels
do
    grep -q "$symbol" "$reference" || {
        echo "Docs/11-api-reference.md is missing $symbol" >&2
        exit 1
    }
done

echo "PicoKit API reference coverage passed"
