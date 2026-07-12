# PicoKit Documentation

## Chapter 6: Creating a project


Create a project with:

```sh
swift run picokit init --board pico2_w --name Blink --template blink
```

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
```

Generated projects include a local `./picokit` launcher. After creation, commands can be run from the generated project:

```sh
./picokit build
./picokit flash
./picokit monitor --reconnect
```
