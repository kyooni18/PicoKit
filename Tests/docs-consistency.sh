#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
hardware="$root/Docs/hardware-guide.md"
integration="$root/Docs/integration.md"
reference="$root/Docs/api-reference.md"

grep -Fq 'select()` and `deselect()`' "$hardware"
grep -Fq 'active-low chip select (high' "$hardware"
grep -Fq '8/16-bit frame width' "$hardware"
grep -Fq 'writeDMA' "$integration"
grep -Fq 'configured MISO pin' "$integration"
grep -Fq 'read(count:repeatedByte:)' "$hardware"
grep -Fq 'read(_:repeatedWord:)' "$hardware"
grep -Fq 'transferDMA' "$hardware"
grep -Fq 'PICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS' "$hardware"
grep -Fq 'indefinite wait' "$hardware"
grep -Fq 'PICOKIT_USB_POST_CONNECT_WAIT_DELAY_MS' "$hardware"
grep -Fq 'additional settle delay' "$hardware"
grep -Fq '8,388 ms on RP2040 and 16,777 ms on RP2350' "$hardware"
grep -Fq 'PICOKIT_USB_CONNECTION_WITHOUT_DTR' "$hardware"
grep -Fq 'without asserting DTR' "$reference"
grep -Fq 'Tests/integration/compiler-discovery.sh' "$root/README.md"
if grep -Fq 'has no async scheduler, DMA,' "$hardware"; then
    echo "hardware guide contains stale no-DMA limitation" >&2
    exit 1
fi
grep -Fq '0/1, 2/3, 12/13, 14/15, 16/17, 18/19, 28/29' "$hardware"
grep -Fq 'PicoI2C.write(..., stop: false)' "$hardware"
grep -Fq 'PicoI2C.read(..., stop: false)' "$hardware"
grep -Fq 'I2C reads and writes report' "$hardware"
grep -Fq 'analogWrite(0, UInt8(128), using: pwm)' "$root/README.md"
grep -Fq 'analogWrite(0, UInt8(128), using: pwm)' "$hardware"
if grep -Fq 'analogWrite(0, 128, using: pwm)' "$root/README.md" "$hardware"; then
    echo "PWM documentation contains an ambiguous overloaded analogWrite example" >&2
    exit 1
fi
if grep -Fq 'I2C repeated starts' "$hardware"; then
    echo "hardware guide contains stale repeated-start limitation" >&2
    exit 1
fi
if grep -Fq '0/1, 12/13, 16/17, 28/29`' "$hardware"; then
    echo "hardware guide contains stale RP2350 UART TX/RX mappings" >&2
    exit 1
fi

if grep -Fq 'does not own chip select' "$hardware"; then
    echo "hardware guide contains stale chip-select ownership guidance" >&2
    exit 1
fi
if grep -Fq 'General DMA is intentionally outside' "$integration"; then
    echo "integration guide contains stale DMA guidance" >&2
    exit 1
fi

echo "PicoKit documentation consistency passed"
