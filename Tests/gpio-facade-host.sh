#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture="$root/Tests/Fixtures/GPIOFacadeHost"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cc -std=c11 -Wall -Wextra -Wconversion -Wshadow -Wstrict-prototypes \
    -Wmissing-prototypes -Werror \
    -DPICOKIT_GPIO_COMPILED_CHIP=1 \
    -I"$fixture/include" -I"$root/Firmware" \
    "$root/Firmware/PicoKitGPIOFacade.c" "$fixture/main.c" \
    -o "$tmp/gpio-facade-host"

"$tmp/gpio-facade-host"
