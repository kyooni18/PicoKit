#!/bin/sh
set -eu

# Validate CMake's public USB options without compiling a firmware image. The
# checks run before pico_sdk_init(), so malformed values fail quickly and do
# not require a board or a completed cross-build.
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
export PATH="/opt/homebrew/bin:$PATH"
export CMAKE_OSX_ARCHITECTURES="$(uname -m)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

expect_failure() {
    name=$1
    expected=$2
    shift 2
    build="$tmp/$name"
    log="$tmp/$name.log"
    if cmake -S "$root/Firmware" -B "$build" -G Ninja \
        -DPICOKIT_ROOT="$root" \
        -DPICOKIT_PRODUCT="CMakeOptionProbe" \
        -DPICOKIT_SOURCE="$root/Sources/Blink/main.swift" \
        -DPICO_BOARD=pico \
        -DPICOKIT_ENABLE_USB=OFF \
        "$@" >"$log" 2>&1; then
        cat "$log" >&2
        echo "CMake accepted invalid $name value" >&2
        exit 1
    fi
    grep -Fq "$expected" "$log"
}

expect_failure stdout-nonnumeric \
    "PICOKIT_USB_STDOUT_TIMEOUT_US must be a non-negative integer" \
    -DPICOKIT_USB_STDOUT_TIMEOUT_US=10ms
expect_failure stdout-overflow \
    "PICOKIT_USB_STDOUT_TIMEOUT_US must fit UInt32" \
    -DPICOKIT_USB_STDOUT_TIMEOUT_US=4294967296
expect_failure connect-nonnumeric \
    "PICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS must be -1 or a non-negative integer" \
    -DPICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS=-2
expect_failure connect-overflow \
    "PICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS must fit UInt32" \
    -DPICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS=4294967296
expect_failure post-connect-nonnumeric \
    "PICOKIT_USB_POST_CONNECT_WAIT_DELAY_MS must be a non-negative integer" \
    -DPICOKIT_USB_POST_CONNECT_WAIT_DELAY_MS=50ms
expect_failure post-connect-overflow \
    "PICOKIT_USB_POST_CONNECT_WAIT_DELAY_MS must fit UInt32" \
    -DPICOKIT_USB_POST_CONNECT_WAIT_DELAY_MS=4294967296

# The Pico SDK uses a negative value for an indefinite CDC wait. Keep the
# documented -1 spelling accepted and verify it reaches the configured build.
indefinite_build="$tmp/connect-indefinite"
indefinite_log="$tmp/connect-indefinite.log"
cmake -S "$root/Firmware" -B "$indefinite_build" -G Ninja \
    -DPICOKIT_ROOT="$root" \
    -DPICOKIT_PRODUCT="CMakeOptionProbe" \
    -DPICOKIT_SOURCE="$root/Sources/Blink/main.swift" \
    -DPICO_BOARD=pico \
    -DPICOKIT_ENABLE_USB=ON \
    -DPICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS=-1 \
    -DPICOKIT_USB_POST_CONNECT_WAIT_DELAY_MS=75 \
    -DPICOKIT_USB_CONNECTION_WITHOUT_DTR=ON >"$indefinite_log" 2>&1
grep -Fq 'PicoKit USB CDC connect wait: -1 ms' "$indefinite_log"
grep -Fq 'PicoKit USB CDC post-connect delay: 75 ms' "$indefinite_log"
grep -Fq 'PicoKit USB CDC connection check: DTR-independent' "$indefinite_log"

echo "PicoKit CMake USB option validation passed"
