# PicoKit Documentation

## Chapter 9: Flashing


Put the board in BOOTSEL mode (hold BOOTSEL while connecting it), then run:

```sh
./swiftpico flash
```

Aliases are `upload` and `f`.

SwiftPico looks for the usual RP2040 and RP2350 boot volumes. If another drive
with a similar name is mounted, or automatic detection misses your board, pass
the paths yourself:

```sh
./swiftpico flash --uf2 Firmware/build/Blink.uf2 --volume /Volumes/RPI-RP2
```

Once the basic flow works, build and flash in one command:

```sh
./swiftpico make
```

Alias:

```sh
./swiftpico m
```
