# PicoKit Documentation

## Chapter 6: Creating a project


Create a project with:

```sh
swift run swiftpico init --board pico2_w --name Blink --template blink
```

`swiftpico init` creates a standalone Swift package that depends on
`https://github.com/kyooni18/PicoKit.git`, writes the board-specific
`swiftpico.json` configuration, and resolves the Pico SDK submodule required by
the firmware build. Use `--skip-resolve` when creating an offline scaffold.

`new` is an alias for `init`.

Available templates are:

- `blink`
- `serial`
- `adc`
- `pwm`
- `i2c`
- `spi`
- `interrupt`
- `watchdog`

Useful initialization options include:

```text
--board BOARD
--name NAME
--template TEMPLATE
--path PATH
--force
--pico-kit-url URL
--pico-kit-branch BRANCH
--skip-resolve
```

Generated projects include a local `./swiftpico` launcher. After creation, commands can be run from the generated project:

```sh
./swiftpico build
./swiftpico flash
./swiftpico monitor --reconnect
```
