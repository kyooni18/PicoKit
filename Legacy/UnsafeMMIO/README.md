# Isolated direct-register prototype

These sources are retained only as historical reference. They are not a
SwiftPM target, are not included by `Firmware/CMakeLists.txt`, and are not part
of the PicoKit public API. They used hand-written RP2040/RP2350 register
offsets, unbounded polling, and unverified USB-controller code.

PicoKit firmware now uses `Sources/PicoKitCore`, `Sources/PicoKitHAL`, and the
Pico SDK bridge in `Firmware/PicoKitSDKBridge.c`. Do not re-enable these files
until an implementation is chip-specific and hardware-tested.

## Why this boundary is permanent for normal users

Direct MMIO code duplicates chip selection, pin validation, timing assumptions,
and startup ownership that the SDK bridge already centralizes. It also bypasses
the host-testable error model and the RP2040/RP2350 validation gates. If a new
capability genuinely needs raw registers, isolate it behind a reviewed C or
Swift implementation boundary, add board-family tests, and keep the public
PicoKit API independent of this historical prototype.
