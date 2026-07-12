# PicoKit Documentation

## Chapter 9: Flashing


Place the board into BOOTSEL mode, then run:

```sh
./swiftpico flash
```

Aliases are `upload` and `f`.

PicoKit searches for common mounted boot-volume names, including RP2040 and RP2350 volumes. Explicit paths can be supplied:

```sh
./swiftpico flash --uf2 Firmware/build/Blink.uf2 --volume /Volumes/RPI-RP2
```

Build and flash in one command:

```sh
./swiftpico make
```

Alias:

```sh
./swiftpico m
```
