# PicoKit Documentation

## Chapter 11: Debugging


Start OpenOCD using the project configuration:

```sh
./swiftpico debug
```

Override the executable or target configuration with:

```sh
./swiftpico debug --openocd openocd --target target/rp2350.cfg
```

The exact debug-probe configuration should be placed in `openOCDConfig` inside `swiftpico.json`.
