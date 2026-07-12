# PicoKit Documentation

## Chapter 2: Supported boards


| PicoKit board | Configuration name | Chip |
|---|---|---|
| Raspberry Pi Pico | `pico` | RP2040 |
| Raspberry Pi Pico W | `pico_w` | RP2040 |
| Raspberry Pi Pico 2 | `pico2` | RP2350 |
| Raspberry Pi Pico 2 W | `pico2_w` | RP2350 |

The configuration parser also accepts `pico-w` and `pico2-w`.

`PicoBoard.onboardLEDPin` returns GPIO 25 only for the non-wireless Pico and Pico 2. Board LED operations use the Pico SDK status LED abstraction, which also permits SDK-supported wireless-board LED implementations.
