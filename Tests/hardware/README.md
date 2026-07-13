# Physical hardware validation matrix

Run these tests against each board before documenting a peripheral as verified:
Pico, Pico W, Pico 2, and Pico 2 W. Record board revision, SDK revision,
firmware commit, wiring, supply voltage, and observed serial output.

| Peripheral | Fixture and expected behavior |
| --- | --- |
| GPIO / board LED | Toggle an external LED on GPIO15; toggle the board status LED. |
| Timer / delay | Measure a 500 ms pin waveform with a logic analyzer. |
| USB serial | Verify 1,000 numbered lines over CDC after USB reconnect, then send a byte from the host and verify the firmware echoes it exactly. |
| UART | Loop TX GPIO0 to RX GPIO1 and verify timeout plus byte integrity. |
| PWM | Measure 1 kHz and 25/50/75% duty cycles on GPIO0. |
| ADC | Apply 0 V, mid-scale, and 3.3 V to GPIO26; check monotonic samples. |
| I2C | Use a known I2C sensor at 0x50; verify read/write and unplug timeout. |
| SPI | Loop MOSI to MISO; verify a byte pattern and unplug timeout. |
| GPIO interrupt | Drive GPIO17 edges and verify foreground event counts. |
| Watchdog | Stop updates and verify reset; then verify regular updates prevent it. |

The test operator must stop and report failures; no physical peripheral is
considered supported merely because the project builds.

## Automated USB serial gate

The normal integration test always creates and builds a disposable serial-echo
project and uses a fake picotool, so it is safe without hardware:

```sh
sh Tests/integration/generated-project.sh
```

With exactly one Pico USB serial device connected, enable the physical section:

```sh
PICO_HARDWARE_TEST=1 sh Tests/integration/generated-project.sh
```

It flashes the generated UF2, waits for the CDC device to return, then verifies
an exact byte sequence including NUL and `0xFF`. No device or multiple devices
produce an explicit `SKIPPED`; a detected device that fails flash or echo fails
the test.
