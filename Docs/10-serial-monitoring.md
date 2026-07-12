# PicoKit Documentation

## Chapter 10: Serial monitoring


If you are not sure which USB device belongs to the Pico, ask SwiftPico to list
what it can see:

```sh
./swiftpico list
```

Then open a serial monitor:

```sh
./swiftpico monitor
```

Aliases are `serial` and `mon`.

Options:

```text
--device /dev/cu.usbmodem...
--baud 115200
--reconnect
```

When multiple serial devices are present, choose one explicitly. `--reconnect`
is handy during development: the monitor waits for the same device to return
after a firmware reset or brief USB disconnect.
