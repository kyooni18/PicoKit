#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
spi="$root/Docs/07-i2c.md"
interop="$root/Docs/14-v0.2-interoperability.md"
serial="$root/Docs/05-usb-serial.md"
runtime="$root/Docs/10-runtime-model.md"

grep -Fq 'select()` and `deselect()`' "$spi"
grep -Fq 'bit order, and 8/16-bit frame width' "$spi"
grep -Fq '`writeDMA` is available' "$interop"
grep -Fq 'configured MISO pin' "$interop"
grep -Fq 'read(count:repeatedByte:)' "$interop"
grep -Fq 'read(_:repeatedWord:)' "$interop"
grep -Fq 'transferDMA' "$interop"
if grep -Fq 'has no async scheduler, DMA,' "$runtime"; then
    echo "Docs/10-runtime-model.md contains stale no-DMA limitation" >&2
    exit 1
fi
grep -Fq '0/1, 2/3, 12/13, 14/15, 16/17, 18/19, 28/29' "$serial"
grep -Fq 'PicoI2C.write(..., stop: false)' "$runtime"
grep -Fq 'PicoI2C.read(..., stop: false)' "$runtime"
grep -Fq 'I2C reads and writes report' "$runtime"
grep -Fq 'analogWrite(0, UInt8(128), using: pwm)' "$root/README.md"
grep -Fq 'analogWrite(0, UInt8(128), using: pwm)' "$root/Docs/06-pwm.md"
if grep -Fq 'analogWrite(0, 128, using: pwm)' "$root/README.md" "$root/Docs/06-pwm.md"; then
    echo "PWM documentation contains an ambiguous overloaded analogWrite example" >&2
    exit 1
fi
if grep -Fq 'I2C repeated starts' "$runtime"; then
    echo "Docs/10-runtime-model.md contains stale repeated-start limitation" >&2
    exit 1
fi
if grep -Fq '0/1, 12/13, 16/17, 28/29`' "$serial"; then
    echo "Docs/05-usb-serial.md contains stale RP2350 UART TX/RX mappings" >&2
    exit 1
fi

if grep -Fq 'does not own chip select' "$spi"; then
    echo "Docs/07-i2c.md contains stale chip-select ownership guidance" >&2
    exit 1
fi
if grep -Fq 'General DMA is intentionally outside' "$interop"; then
    echo "Docs/14-v0.2-interoperability.md contains stale DMA guidance" >&2
    exit 1
fi

echo "PicoKit documentation consistency passed"
