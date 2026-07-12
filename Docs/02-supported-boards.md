# PicoKit Documentation

## Chapter 2: Supported boards


Pick the board name that matches the board on your desk; SwiftPico passes the
matching CMake name through to the Pico SDK.

| PicoKit board | Configuration name | Chip |
|---|---|---|
| Raspberry Pi Pico | `pico` | RP2040 |
| Raspberry Pi Pico W | `pico_w` | RP2040 |
| Raspberry Pi Pico 2 | `pico2` | RP2350 |
| Raspberry Pi Pico 2 W | `pico2_w` | RP2350 |

The configuration parser also accepts the friendlier `pico-w` and `pico2-w`
spellings.

`PicoBoard.onboardLEDPin` returns GPIO 25 only for the non-wireless Pico and
Pico 2. For a portable board LED, prefer `BoardLED`: it uses the Pico SDK status
LED abstraction and can work with SDK-supported wireless-board LEDs too.
