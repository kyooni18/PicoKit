#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# Keep the Pico SDK's nested pioasm build native on Apple Silicon. Without
# this, an x86_64 CMake/Ninja can select the wrong architecture of the host
# compiler or cross-toolchain plugin before the bridge is compiled.
export PATH="/opt/homebrew/bin:$PATH"
command -v cmake >/dev/null
command -v ninja >/dev/null
command -v arm-none-eabi-gcc >/dev/null

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
configure_log="$tmp/configure.log"
build_log="$tmp/build.log"

if ! cmake -S "$root/Firmware" -B "$tmp/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DPICO_BOARD="${PICO_TEST_BOARD:-pico}" \
    -DPICOKIT_PRODUCT=PicoKitWarningProbe \
    -DPICOKIT_SOURCE="$root/Sources/Blink/main.swift" \
    -DPICOKIT_ENABLE_USB=ON \
    -DPICOKIT_ROOT="$root" \
    -DPICOKIT_BRIDGE_WARNINGS=ON >"$configure_log" 2>&1; then
    cat "$configure_log" >&2
    exit 1
fi
on_command=$(ninja -C "$tmp/build" -t commands PicoKitSDKBridge \
    | awk '/PicoKitSDKBridge\.c$/ { print; exit }')
test -n "$on_command"
printf '%s\n' "$on_command" > "$tmp/on-command"
grep -F -- '-fanalyzer' "$tmp/on-command" >/dev/null
grep -F -- '-Werror' "$tmp/on-command" >/dev/null
gpio_on_command=$(ninja -C "$tmp/build" -t commands PicoKitSDKBridge \
    | awk '/PicoKitGPIOFacade\.c$/ { print; exit }')
test -n "$gpio_on_command"
printf '%s\n' "$gpio_on_command" | grep -F -- '-Werror' >/dev/null
if ! cmake --build "$tmp/build" --target PicoKitSDKBridge >"$build_log" 2>&1; then
    cat "$build_log" >&2
    exit 1
fi
if ! cmake -S "$root/Firmware" -B "$tmp/build" -G Ninja \
    -DPICOKIT_BRIDGE_WARNINGS=OFF >"$configure_log" 2>&1; then
    cat "$configure_log" >&2
    exit 1
fi
off_command=$(ninja -C "$tmp/build" -t commands PicoKitSDKBridge \
    | awk '/PicoKitSDKBridge\.c$/ { print; exit }')
test -n "$off_command"
printf '%s\n' "$off_command" > "$tmp/off-command"
if grep -Eq -- '-W(error|all|extra|conversion|shadow)' "$tmp/off-command"; then
    echo "bridge warning flags remained after disabling PICOKIT_BRIDGE_WARNINGS" >&2
    exit 1
fi

echo "PicoKit bridge warnings validation passed"
