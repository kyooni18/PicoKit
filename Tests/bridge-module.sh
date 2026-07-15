#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cmake="$root/Firmware/CMakeLists.txt"
module_map="$root/Firmware/PicoKitSDKBridge.modulemap"

test -s "$module_map"
grep -Fq 'module PicoKitSDKBridge' "$module_map"
grep -Fq 'header "PicoKitSDKBridge.h"' "$module_map"
grep -Fq 'import PicoKitSDKBridge' "$root/Sources/PicoKitHAL/Serial.swift"
grep -Fq 'picokit_stdio_connected' "$root/Firmware/PicoKitSDKBridge.h"
grep -Fq '#ifdef __cplusplus' "$root/Firmware/PicoKitSDKBridge.h"
grep -Fq 'extern "C" {' "$root/Firmware/PicoKitSDKBridge.h"
grep -Fq 'import PicoKitSDKBridge' "$root/Sources/PicoKitHAL/Buses.swift"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf '#include "PicoKitSDKBridge.h"\nvoid call(void) { picokit_stdio_init(); }\n' |
    c++ -x c++ -c -I"$root/Firmware" -o "$tmp/caller.o" -
nm "$tmp/caller.o" | grep -Eq '[[:space:]]U _?picokit_stdio_init$'
grep -Fq 'fmodule-map-file=${PICOKIT_BRIDGE_MODULE_MAP}' "$cmake"
if grep -Fq -- '-import-bridging-header ${PICOKIT_BRIDGE_DIR}/BridgingHeader.h' "$cmake"; then
    echo "PicoKit still uses the deprecated implicit bridge header" >&2
    exit 1
fi

echo "PicoKit explicit bridge module validation passed"
