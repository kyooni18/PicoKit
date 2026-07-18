#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
hardware="$root/Docs/hardware-guide.md"
serial="$root/Docs/serial-and-uart.md"
buses="$root/Docs/buses-and-analog.md"
runtime="$root/Docs/runtime-and-testing.md"
integration="$root/Docs/external-libraries.md"
reference="$root/Docs/api-reference.md"
examples="$root/Docs/examples.md"
dma="$root/Docs/dma-and-buffer-lifecycle.md"
gpio="$root/Docs/gpio-and-reset-sequencing.md"
interrupts="$root/Docs/interrupts-and-watchdog.md"
analog="$root/Docs/analog-and-pwm.md"
build="$root/Docs/firmware-build-and-bridge.md"
transactions="$root/Docs/i2c-and-spi-transactions.md"
validation="$root/Docs/hardware-validation.md"
typed="$root/Docs/typed-api-and-errors.md"

grep -Fq 'spi.select()' "$buses"
grep -Fq 'spi.deselect()' "$buses"
grep -Fq 'active-low CS that is high while' "$buses"
grep -Fq '16-bit mode' "$buses"
grep -Fq 'writeDMA' "$buses"
grep -Fq 'MISO' "$buses"
grep -Fq 'read(count:repeatedByte:)' "$buses"
grep -Fq 'read(_:repeatedWord:)' "$buses"
grep -Fq 'transferDMA' "$buses"
grep -Fq 'releaseDMAChannels()' "$dma"
grep -Fq 'writeDMA(packet, timeout:' "$dma"
grep -Fq 'the bridge cleans up the channel(s)' "$dma"
grep -Fq 'The call leaves the pin as an output at the inactive level' "$gpio"
grep -Fq 'writes the output latch before enabling output' "$gpio"
grep -Fq 'Bits above GPIO29 are ignored' "$gpio"
grep -Fq 'atomically returns the current word and clears it' "$interrupts"
grep -Fq 'There is no public disable method' "$interrupts"
grep -Fq '8,388 ms' "$interrupts"
grep -Fq 'actualFrequency` is the frequency produced' "$analog"
grep -Fq 'multiplying by 257' "$analog"
grep -Fq 'logical `off()` drives' "$analog"
grep -Fq 'host build is not a firmware build' "$build"
grep -Fq 'PICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS' "$build"
grep -Fq 'PicoKitSDKBridge.c' "$build"
grep -Fq 'writeRead` validates the complete' "$transactions"
grep -Fq 'select()` drives it low' "$transactions"
grep -Fq 'read(count:repeatedByte:)' "$transactions"
grep -Fq 'PICO_HARDWARE_TEST=1' "$validation"
grep -Fq 'fake picotool' "$validation"
grep -Fq 'A skipped physical section is an honest result' "$validation"
grep -Fq 'The valid range is GPIO0 through GPIO29' "$typed"
grep -Fq 'multiplication overflow' "$typed"
grep -Fq 'PicoKitError` is `Equatable`' "$typed"
grep -Fq 'PICOKIT_USB_CONNECT_WAIT_TIMEOUT_MS' "$serial"
grep -Fq 'waits indefinitely' "$serial"
grep -Fq 'PICOKIT_USB_POST_CONNECT_WAIT_DELAY_MS' "$serial"
grep -Fq 'Extra settling time' "$serial"
grep -Fq '8,388 ms on RP2040 and 16,777 ms on RP2350' "$runtime"
grep -Fq 'PICOKIT_USB_CONNECTION_WITHOUT_DTR' "$serial"
grep -Fq 'while !Serial.connected { sleep(10) }' "$serial"
grep -Fq 'one-shot startup' "$serial"
grep -Fq 'USB serial host is not connected' "$serial"
grep -Fq 'Timed reads poll' "$serial"
grep -Fq 'USB serial host is not connected' "$reference"
grep -Fq 'USB serial host is not connected' "$hardware"
grep -Fq 'without asserting DTR' "$reference"
grep -Fq 'the default is `OFF`' "$reference"
grep -Fq 'struct Blink' "$examples"
grep -Fq 'struct SerialEcho' "$examples"
grep -Fq 'resetting `announced`' "$examples"
grep -Fq 'struct I2CRegisterRead' "$examples"
grep -Fq 'struct SPIIdentifier' "$examples"
grep -Fq 'struct InterruptButton' "$examples"
grep -Fq 'struct WatchedLoop' "$examples"
grep -Fq 'final class FakeGPIO' "$examples"
grep -Fq 'Tests/integration/compiler-discovery.sh' "$root/README.md"
if grep -Fq 'has no async scheduler, DMA,' "$runtime"; then
    echo "hardware guide contains stale no-DMA limitation" >&2
    exit 1
fi
grep -Fq '0/1, 2/3, 12/13, 14/15, 16/17, 18/19, 28/29' "$serial"
grep -Fq 'stop: false' "$buses"
grep -Fq 'partialTransfer' "$buses"
grep -Fq 'analogWrite(0, UInt8(128), using: pwm)' "$root/README.md"
grep -Fq 'analogWrite(0, UInt8(128), using: pwm)' "$buses"
if grep -Fq 'analogWrite(0, 128, using: pwm)' "$root/README.md" "$buses"; then
    echo "PWM documentation contains an ambiguous overloaded analogWrite example" >&2
    exit 1
fi
if grep -Fq 'I2C repeated starts' "$buses"; then
    echo "hardware guide contains stale repeated-start limitation" >&2
    exit 1
fi
if grep -Fq '0/1, 12/13, 16/17, 28/29`' "$serial"; then
    echo "hardware guide contains stale RP2350 UART TX/RX mappings" >&2
    exit 1
fi

if grep -Fq 'does not own chip select' "$buses"; then
    echo "hardware guide contains stale chip-select ownership guidance" >&2
    exit 1
fi
if grep -Fq 'General DMA is intentionally outside' "$integration"; then
    echo "integration guide contains stale DMA guidance" >&2
    exit 1
fi

echo "PicoKit documentation consistency passed"
