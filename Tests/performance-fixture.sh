#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture="$root/Sources/Performance/main.swift"
docs="$root/Docs/15-performance.md"

test -s "$fixture"
test -s "$docs"
grep -Fq 'Serial.println("metric,iterations,elapsed_us,check")' "$fixture"
grep -Fq 'Serial.println("complete,0,0,0")' "$fixture"
grep -Fq 'Each record is `metric,iterations,elapsed_us,check`' "$fixture"

for metric in \
    cpu.add cpu.multiply cpu.shift cpu.branch cpu.xorshift cpu.fixedpoint cpu.mix cpu.crcstep \
    gpio.single_toggle gpio.mask_toggle pwm.update pwm.counter_update adc.same_channel; do
    grep -Fq "report(\"$metric\"" "$fixture"
done

grep -Fq 'Pico 2 W benchmark fixture' "$docs"
grep -Fq 'emits one CSV record per measurement' "$docs"

echo "PicoKit performance fixture contract passed"
