# PicoKit Documentation

## Chapter 6: Creating a project


When you want a fresh firmware project rather than another in-tree example,
start here:

```sh
swiftpico init --board pico2_w --name Blink --template blink
```

Install SwiftPico first, then run `swiftpico init`. It creates a normal standalone Swift package that depends on
`https://github.com/kyooni18/PicoKit.git`, writes the board-specific
`swiftpico.json` configuration, and resolves the Pico SDK submodule required by
the firmware build. Use `--skip-resolve` when creating an offline scaffold.

`new` is an alias for `init`, so use whichever reads better in your shell
history.

The templates are intentionally small starting points:

- `blink`
- `serial`
- `adc`
- `pwm`
- `i2c`
- `spi`
- `interrupt`
- `watchdog`

The options you will use most often are:

```text
--board BOARD
--name NAME
--template TEMPLATE
--path PATH
--force
--pico-kit-url URL
--pico-kit-version VERSION
--skip-resolve
```

Generated projects include a local `./swiftpico` launcher. Once you are in the
project directory, the usual loop looks like this:

```sh
./swiftpico build
./swiftpico flash
./swiftpico monitor --reconnect
```
