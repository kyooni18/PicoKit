# PicoKit Documentation

## Chapter 7: Project configuration


SwiftPico looks for `swiftpico.json` in the current directory and then walks up
through parent directories. That means commands work from a source subfolder as
well as from the project root.

Most projects can leave this file alone after `init`. It is still useful to know
what is in it when changing boards, naming a firmware target, or using a custom
SDK checkout:

```json
{
  "board": "pico2_w",
  "configuration": "release",
  "firmwareDirectory": "Firmware",
  "picoKitURL": "https://github.com/kyooni18/PicoKit.git",
  "picoKitVersion": "0.1.0",
  "product": "Blink",
  "uf2": "Firmware/build/Blink.uf2",
  "openOCD": "openocd",
  "openOCDConfig": [
    "interface/cmsis-dap.cfg",
    "target/rp2350.cfg"
  ]
}
```

These are the supported fields when you do need to customize the setup:

| Field | Purpose |
|---|---|
| `board` | Canonical PicoKit board name |
| `firmwareDirectory` | Directory containing the firmware CMake project |
| `picoSDKPath` | Explicit Pico SDK path |
| `picoKitPath` | Path to the reusable PicoKit checkout |
| `picoKitURL` | SwiftPM URL used to resolve PicoKit |
| `picoKitVersion` | SwiftPM release used to resolve PicoKit |
| `picotool` | Optional `picotool` path |
| `swiftSDK` | Embedded Swift SDK identifier for SwiftPM-based builds |
| `product` | Firmware target and product name |
| `configuration` | Usually `debug` or `release` |
| `uf2` | UF2 output path |
| `openOCD` | OpenOCD executable |
| `openOCDConfig` | OpenOCD configuration files |
