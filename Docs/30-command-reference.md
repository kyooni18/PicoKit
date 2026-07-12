# PicoKit Documentation

## Chapter 30: Command reference


When you need a reminder rather than a full guide, this is the short version of
the SwiftPico command set:

| Command | Aliases | Purpose |
|---|---|---|
| `init` | `new` | Create a standalone project |
| `build` | `b` | Build firmware |
| `clean` | `c` | Remove build artifacts |
| `flash` | `upload`, `f` | Copy a UF2 to a BOOTSEL volume |
| `make` | `m` | Build and flash |
| `debug` | — | Start OpenOCD |
| `monitor` | `serial`, `mon` | Monitor a serial device |
| `list` | `devices` | List boot volumes and serial devices |
| `info` | — | Show resolved project configuration |
| `template` | — | List templates |
| `doctor` | `diagnose` | Check the development environment |

Run `swiftpico help` for option details and examples for the command you are
about to use.
