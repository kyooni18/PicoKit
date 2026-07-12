# PicoKit Documentation

## Chapter 5: Package products


The Swift package exports:

```swift
.library(name: "PicoKit", targets: ["PicoKit"])
.executable(name: "swiftpico", targets: ["SwiftPicoCLI"])
.executable(name: "picokit", targets: ["SwiftPicoCLI"]) // compatibility alias
```

`PicoKit` is the firmware-facing library. `swiftpico` is the separate host-side
project initializer, build, flash, debug, and monitoring utility. `picokit` is
kept as a compatibility alias.
