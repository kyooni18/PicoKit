# PicoKit Documentation

## Chapter 11: Debugging


If you have a supported debug probe, start OpenOCD using the project settings:

```sh
./swiftpico debug
```

For a one-off probe or target change, override those settings on the command
line:

```sh
./swiftpico debug --openocd openocd --target target/rp2350.cfg
```

Keep the probe-specific OpenOCD files in `openOCDConfig` inside
`swiftpico.json`. That way the command stays short and the project records the
setup that actually works.
