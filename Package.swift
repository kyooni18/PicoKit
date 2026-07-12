// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PicoKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PicoKit", targets: ["PicoKit"]),
        .executable(name: "picokit", targets: ["PicoKitCLI"]),
    ],
    targets: [
        // Layer 1: portable value types, validation, units, and errors.
        .target(name: "PicoKitCore"),
        // Layer 2: hardware API. Its SDK implementation is selected only by
        // the firmware CMake build; this target remains host-testable.
        .target(name: "PicoKitHAL", dependencies: ["PicoKitCore"]),
        // Public umbrella. Firmware imports this product, never a C shim.
        .target(name: "PicoKit", dependencies: ["PicoKitCore", "PicoKitHAL"], path: "Sources/PicoKitFacade"),
        // Layer 4 (the Pico SDK C bridge) deliberately lives under Firmware:
        // SwiftPM must not attempt to import Pico SDK headers on the host.
        .executableTarget(name: "PicoKitCLI", dependencies: ["PicoKitCore"]),
        // A Foundation-free host validation executable. Some embedded Swift
        // toolchains omit XCTest/Swift Testing, so this remains runnable in
        // the same toolchain used to generate firmware.
        .executableTarget(name: "PicoKitHostTests", dependencies: ["PicoKitCore"], path: "Tests/HostTests"),
    ]
)
