#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
reference="$root/Docs/11-api-reference.md"

for symbol in \
    PicoChip PicoBoard PicoKitError PicoPin Duration Frequency PinMode PinState \
    DigitalIO PicoGPIO BoardLED Clock USBSerial PicoSerial Serial Pico UARTInstance \
    PicoUART PWMChannel PicoPWM ADCChannel PicoADC I2CInstance PicoI2C SPIInstance \
    PicoSPI GPIOInterruptEdge PicoInterrupts PicoWatchdog pinMode digitalWrite \
    digitalRead analogRead analogWrite delay delayMicroseconds millis micros sleep \
    sleepMicroseconds
do
    grep -q "$symbol" "$reference" || {
        echo "Docs/11-api-reference.md is missing $symbol" >&2
        exit 1
    }
done

echo "PicoKit API reference coverage passed"
