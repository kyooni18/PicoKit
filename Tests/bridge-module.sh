#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cmake="$root/Firmware/CMakeLists.txt"
module_map="$root/Firmware/PicoKitSDKBridge.modulemap"

test -s "$module_map"
grep -Fq 'module PicoKitSDKBridge' "$module_map"
grep -Fq 'header "PicoKitSDKBridge.h"' "$module_map"
grep -Fq 'import PicoKitSDKBridge' "$root/Sources/PicoKitHAL/Serial.swift"
grep -Fq 'import PicoKitSDKBridge' "$root/Sources/PicoKitHAL/Buses.swift"
grep -Fq 'fmodule-map-file=${PICOKIT_BRIDGE_MODULE_MAP}' "$cmake"
if grep -Fq -- '-import-bridging-header ${PICOKIT_BRIDGE_DIR}/BridgingHeader.h' "$cmake"; then
    echo "PicoKit still uses the deprecated implicit bridge header" >&2
    exit 1
fi

echo "PicoKit explicit bridge module validation passed"
