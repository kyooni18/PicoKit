# PicoKit Documentation

## External libraries

Add a library to the normal SwiftPM development build, then describe its
firmware integration in a project-local `Firmware/Dependencies.cmake` file.
PicoKit includes that file automatically after defining the firmware target and
the `picokit_add_swift_library` helper. Set
`PICOKIT_DEPENDENCIES_FILE` before including PicoKit's firmware CMake entrypoint
only if you keep the file somewhere else.

### C and C++ libraries

Fetch a repository and link the CMake target that it exports:

```sh
include(FetchContent)
FetchContent_Declare(tiny_driver
    GIT_REPOSITORY "https://github.com/example/tiny-driver.git"
    GIT_TAG "v1.2.0")
FetchContent_MakeAvailable(tiny_driver)
target_link_libraries(${PICOKIT_PRODUCT} PRIVATE tiny_driver)
```

On the next firmware build, CMake fetches the source for the embedded target
and links `tiny_driver` into the firmware. The library must support the Pico
cross compiler; a host-only CMake package cannot be used as firmware.

### Swift libraries

First add the package and its product to `Package.swift` as usual:

```swift
dependencies: [
    .package(url: "https://github.com/example/EmbeddedMath.git", from: "1.0.0")
],
targets: [
    .executableTarget(
        name: "Blink",
        dependencies: [
            .product(name: "PicoKit", package: "PicoKit"),
            .product(name: "EmbeddedMath", package: "EmbeddedMath")
        ]
    )
]
```

Run `swift package resolve`, then add its checkout target to
`Firmware/Dependencies.cmake`. The firmware build compiles that target for the
selected Pico architecture, creates an importable Swift module, and links it
into the final executable:

```swift
import PicoKit
import EmbeddedMath
```

Only Foundation-free, Embedded Swift-compatible package targets can be used in
firmware. SwiftPM may still build a package on macOS even when the package uses
host-only APIs, so `swiftpico build` is the final compatibility check.

`Firmware/Dependencies.cmake` is ordinary CMake and is included after PicoKit
has defined the application target. For the checked-out Swift target, add:

```cmake
picokit_add_swift_library(EmbeddedMath
    SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../Dependencies/EmbeddedMath/Sources/EmbeddedMath")
target_link_libraries(${PICOKIT_PRODUCT} PRIVATE EmbeddedMath)
```

For C/C++ dependencies, use `FetchContent` or `add_subdirectory`, then link
the dependency's exported CMake target to `${PICOKIT_PRODUCT}`. Keep platform
setup inside the dependency file rather than modifying PicoKit's SDK bridge.
