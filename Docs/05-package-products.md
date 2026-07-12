# PicoKit Documentation

## Chapter 5: Package products


The Swift package exports:

```swift
.library(name: "PicoKit", targets: ["PicoKit"])
.executable(name: "picokit", targets: ["PicoKitCLI"])
```

`PicoKit` is the firmware-facing library. `picokit` is the host-side project, build, flash, debug, and monitoring utility.
