# PicoKit Documentation

## Project workflow


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

### Configuration and commands

SwiftPico finds `swiftpico.json` in the current directory or a parent. The
generated file records the board, firmware directory, PicoKit source/version,
build configuration, product, UF2 path, and optional Pico SDK, picotool,
Swift SDK, and OpenOCD settings. Run `./swiftpico info` to inspect the resolved
configuration rather than editing it unless a project needs an override.

| Command | Aliases | Purpose |
|---|---|---|
| `init` | `new` | Create a project |
| `build` | `b` | Configure and build firmware |
| `clean` | `c` | Remove firmware build artifacts |
| `flash` | `upload`, `f` | Flash the UF2 |
| `make` | `m` | Build then flash |
| `monitor` | `serial`, `mon` | Open the interactive CDC terminal |
| `debug` | — | Start OpenOCD |
| `list` | `devices` | List boot volumes and serial devices |
| `doctor` | `diagnose` | Diagnose the environment |

`build` includes every Swift source below `Sources/<App>/`; keep `main.swift`
as the entry point and split ordinary types into subdirectories as needed. The
embedded targets are `armv6m-none-none-eabi` for RP2040, `armv7em-none-none-eabi`
for RP2350 ARM, and `riscv32-none-none-eabi` for RP2350 RISC-V.

To flash, hold BOOTSEL while connecting the board and run `./swiftpico flash`.
Pass `--uf2` and `--volume` when auto-detection is wrong. For a debug probe,
run `./swiftpico debug`; put stable probe settings in `openOCDConfig` or
override one run with `--openocd` and `--target`.
