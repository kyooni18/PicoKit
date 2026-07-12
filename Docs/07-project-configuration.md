# PicoKit Documentation

## Chapter 7: Project configuration


PicoKit commands locate `picokit.json` in the current directory or one of its parent directories.

A configuration can contain:

```json
{
  "board": "pico2_w",
  "configuration": "release",
  "firmwareDirectory": "Firmware",
  "product": "Blink",
  "uf2": "Firmware/build/Blink.uf2",
  "openOCD": "openocd",
  "openOCDConfig": [
    "interface/cmsis-dap.cfg",
    "target/rp2350.cfg"
  ]
}
```

Additional supported fields include:

| Field | Purpose |
|---|---|
| `board` | Canonical PicoKit board name |
| `firmwareDirectory` | Directory containing the firmware CMake project |
| `picoSDKPath` | Explicit Pico SDK path |
| `picoKitPath` | Path to the reusable PicoKit checkout |
| `picotool` | Optional `picotool` path |
| `swiftSDK` | Embedded Swift SDK identifier for SwiftPM-based builds |
| `product` | Firmware target and product name |
| `configuration` | Usually `debug` or `release` |
| `uf2` | UF2 output path |
| `openOCD` | OpenOCD executable |
| `openOCDConfig` | OpenOCD configuration files |
