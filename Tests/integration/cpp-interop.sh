#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
source_file="$root/Tests/fixtures/cpp-interop/main.swift"
interop_dir="$root/Tests/fixtures/cpp-interop/Interop"
export PATH="/opt/homebrew/bin:$PATH"
export CMAKE_OSX_ARCHITECTURES="$(uname -m)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cmake -S "$root/Firmware" -B "$tmp" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DPICOKIT_ROOT="$root" \
    -DPICOKIT_PRODUCT=CppInteropProbe \
    -DPICOKIT_SOURCE="$source_file" \
    -DPICOKIT_APP_INTEROP_DIR="$interop_dir" \
    -DPICO_BOARD=pico \
    -DPICOKIT_ENABLE_USB=OFF >/dev/null
cmake --build "$tmp" --parallel >/dev/null

test -s "$tmp/CppInteropProbe.elf"
test -s "$tmp/CppInteropProbe.uf2"
nm "$tmp/CppInteropProbe.elf" |
    grep -Eq '[[:space:]]picokit_cpp_add$'

echo "PicoKit Embedded Swift C++ interop passed"
