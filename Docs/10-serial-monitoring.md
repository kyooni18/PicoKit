# PicoKit Documentation

## Chapter 10: Serial monitoring


List detected boot volumes and serial devices:

```sh
./picokit list
```

Open a serial monitor:

```sh
./picokit monitor
```

Aliases are `serial` and `mon`.

Options:

```text
--device /dev/cu.usbmodem...
--baud 115200
--reconnect
```

When multiple serial devices are detected, specify the device explicitly. `--reconnect` causes the monitor to reconnect after a firmware reset or USB disconnection.
