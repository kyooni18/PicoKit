# Isolated direct-register prototype

These sources are retained only as historical reference. They are not a
SwiftPM target, are not included by `Firmware/CMakeLists.txt`, and are not part
of the PicoKit public API. They used hand-written RP2040/RP2350 register
offsets, unbounded polling, and unverified USB-controller code.

PicoKit firmware now uses `Sources/PicoKitCore`, `Sources/PicoKitHAL`, and the
Pico SDK bridge in `Firmware/PicoKitSDKBridge.c`. Do not re-enable these files
until an implementation is chip-specific and hardware-tested.
