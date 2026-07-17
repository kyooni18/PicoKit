#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture="$root/Sources/Performance/main.swift"
docs="$root/Docs/performance.md"

test -s "$fixture"
test -s "$docs"
grep -Fq 'emit("metric,iterations,elapsed_us,check")' "$fixture"
grep -Fq 'emit("complete,0,0,0")' "$fixture"
grep -Fq 'emit("# format=picokit-performance-v1")' "$fixture"
grep -Fq 'emit("# ready=send-one-byte")' "$fixture"
grep -Fq 'while !Serial.connected { sleep(10) }' "$fixture"
grep -Fq 'while Serial.connected {' "$fixture"
grep -Fq 'if Serial.read() != nil {' "$fixture"
grep -Fq 'private static func runOnce()' "$fixture"
grep -Fq 'private static func emit(_ line: String)' "$fixture"
grep -Fq '"gpio.counterbalanced," + String(singleElapsed)' "$fixture"
grep -Fq 'emit("# chip=" + PicoChip.compiled.rawValue)' "$fixture"
grep -Fq 'emit("# board=" + (PicoBoard.compiled?.rawValue ?? "custom"))' "$fixture"
grep -Fq 'emit("# iterations=" + String(iterations))' "$fixture"
grep -Fq 'Each record is `metric,iterations,elapsed_us,check`' "$fixture"
grep -Fq 'let gpio = PicoGPIO.compiled' "$fixture"

for metric in \
    cpu.add cpu.multiply cpu.shift cpu.branch cpu.xorshift cpu.fixedpoint cpu.mix cpu.crcstep \
    gpio.single_toggle gpio.mask_toggle gpio.mask_toggle.second_pass \
    gpio.single_toggle.second_pass pwm.update pwm.counter_update adc.same_channel; do
    grep -Fq "report(\"$metric\"" "$fixture"
done

grep -Fq 'Benchmark fixture' "$docs"
grep -Fq 'emits records in this form' "$docs"
grep -Fq -- '-DPICOKIT_USB_STDOUT_TIMEOUT_US=1000000' "$docs"

echo "PicoKit performance fixture contract passed"
