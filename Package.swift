// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "PicoKit",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "PicoKit", targets: ["PicoKit"])
  ],
  targets: [
    // Layer 1: portable value types, validation, units, and errors.
    .target(name: "PicoKitCore"),
    // Layer 2: hardware API. Its SDK implementation is selected only by
    // the firmware CMake build; this target remains host-testable.
    .target(
      name: "PicoKitHAL",
      dependencies: ["PicoKitCore"],
      // PicoKitHostTests intentionally remains an executable so it can
      // run on the same toolchain as firmware builds. Its validation
      // covers internal conversion guards that have no hardware-backed
      // host equivalent; keep those @testable imports working in the
      // optimized configuration as well.
      swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .release))]
    ),
    // Public umbrella. Firmware imports this product, never a C shim.
    .target(
      name: "PicoKit", dependencies: ["PicoKitCore", "PicoKitHAL"], path: "Sources/PicoKitFacade"),
    // A Foundation-free host validation executable. Some embedded Swift
    // toolchains omit XCTest/Swift Testing, so this remains runnable in
    // the same toolchain used to generate firmware.
    .executableTarget(
      name: "PicoKitHostTests",
      dependencies: ["PicoKit", "PicoKitHAL"],
      path: "Tests/HostTests"
    ),
  ]
)
