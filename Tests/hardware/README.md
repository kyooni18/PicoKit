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
sh Tests/integration/generated-blink.sh
sh Tests/integration/generated-templates.sh
```

With exactly one Pico USB serial device connected, enable the physical section:

```sh
PICO_HARDWARE_TEST=1 sh Tests/integration/generated-project.sh
```

It flashes the generated UF2, waits for the CDC device to return, then verifies
an exact byte sequence including NUL and `0xFF`. A board already in BOOTSEL
mode is flashed even when no serial node exists; if CDC does not enumerate
after that successful flash, only the echo portion is explicitly skipped. With
no detected board, or multiple serial devices and no BOOTSEL device, the whole
physical section is skipped; a detected serial device that fails flash or echo
fails the test.

Set `PICO_HARDWARE_REQUIRE_CDC=1` when CDC enumeration is mandatory; this turns
the no-CDC-after-flash diagnostic into a failure. The image is also checked for
the PicoKit startup hook and TinyUSB/stdio symbols before any physical flash.

## Recording a result

For each physical run record the board name, chip family, PicoKit/SDK revision,
USB device path, whether the board began in BOOTSEL or application mode, flash
result, CDC re-enumeration result, exact bytes sent and received, and any
external wiring. A passing script without that context is difficult to compare
with another board or release. Never enable the hardware section in unattended
CI unless the connected board and destructive flash scope are explicitly owned
by that job.
