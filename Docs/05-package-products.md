# PicoKit Documentation

## Chapter 5: Package products


There are two things you can install from this package: the PicoKit library for
firmware and the SwiftPico tool for creating and managing projects.

```swift
.library(name: "PicoKit", targets: ["PicoKit"])
.executable(name: "swiftpico", targets: ["SwiftPicoCLI"])
.executable(name: "picokit", targets: ["SwiftPicoCLI"]) // compatibility alias
```

`PicoKit` is the firmware-facing library. `swiftpico` is the separate host-side
project initializer, build, flash, debug, and monitoring utility. `picokit` is
kept as a compatibility alias.
