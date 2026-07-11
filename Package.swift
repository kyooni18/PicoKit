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
        .target(name: "PicoKit"),
        .executableTarget(name: "PicoKitCLI"),
    ]
)
