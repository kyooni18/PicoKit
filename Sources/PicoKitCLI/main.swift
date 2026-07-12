import Foundation

@main
struct PicoKitCommand {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("picokit: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else { throw CLIError.usage }
        let args = Array(arguments.dropFirst())
        switch command {
        case "help", "--help", "-h": print(usage)
        case "init", "new": try initialise(args)
        case "build", "b": try build(args)
        case "flash", "upload", "f": try flash(args)
        case "make", "m": try build(args); try flash(args)
        case "clean", "c": try clean(args)
        case "debug": try debug(args)
        case "monitor", "serial", "mon": try monitor(args)
        case "list", "devices": list()
        case "info": try showInfo(args)
        case "template": showTemplates(args)
        default: throw CLIError.message("unknown command '\(command)'\n\n\(usage)")
        }
    }

    // MARK: - init / new

    private static func initialise(_ arguments: [String]) throws {
        let board = option("--board", in: arguments) ?? "pico"
        guard ["pico", "pico-w", "pico2", "pico2_w"].contains(board) else {
            throw CLIError.message("unsupported board '\(board)'. Choose: pico, pico-w, pico2, pico2_w")
        }
        let name = option("--name", in: arguments) ?? "PicoApp"
        let template = option("--template", in: arguments) ?? "blink"
        guard ["blink", "serial"].contains(template) else {
            throw CLIError.message("template '\(template)' is not available for standalone firmware yet. Choose: blink, serial")
        }
        let force = arguments.contains("--force")
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let picoRoot = findPicoKitRoot(from: currentDirectory)
        let projectRoot: URL
        if let path = option("--path", in: arguments) {
            projectRoot = URL(fileURLWithPath: path, relativeTo: currentDirectory).standardizedFileURL
        } else if let picoRoot {
            projectRoot = picoRoot.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
        } else {
            projectRoot = currentDirectory
        }
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let configURL = projectRoot.appendingPathComponent("picokit.json")
        guard force || !FileManager.default.fileExists(atPath: configURL.path) else {
            throw CLIError.message("picokit.json already exists. Use --force to overwrite.")
        }

        let chip = board.hasPrefix("pico2") ? "rp2350" : "rp2040"
        let config = PicoKitConfig(
            board: board,
            firmwareDirectory: "Firmware",
            picoSDKPath: picoRoot?.appendingPathComponent("Vendor/pico-sdk").standardizedFileURL.path,
            picotool: picoRoot?.appendingPathComponent("Tools/picotool-build/picotool").standardizedFileURL.path,
            swiftSDK: nil,
            product: name,
            configuration: "release",
            uf2: "Firmware/build/picokit-blink.uf2",
            openOCD: "openocd",
            openOCDConfig: board.hasPrefix("pico2")
                ? ["interface/cmsis-dap.cfg", "target/rp2350.cfg"]
                : ["interface/cmsis-dap.cfg", "target/rp2040.cfg"]
        )
        try JSONEncoder.pretty.encode(config).write(to: configURL)

        let sourceDir = projectRoot.appendingPathComponent("Sources").appendingPathComponent(name)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir.appendingPathComponent("main.swift")

        guard !FileManager.default.fileExists(atPath: sourceFile.path) || force else {
            print("Source file already exists at \(sourceFile.path)")
            return
        }

        let sourceCode = templateSource(template: template, board: board, name: name, chip: chip)
        try sourceCode.write(to: sourceFile, atomically: true, encoding: .utf8)

        let firmwareDir = projectRoot.appendingPathComponent("Firmware", isDirectory: true)
        try FileManager.default.createDirectory(at: firmwareDir, withIntermediateDirectories: true)
        if let picoRoot {
            let sourceFirmware = picoRoot.appendingPathComponent("Firmware")
            for file in ["CMakeLists.txt", "BridgingHeader.h", "PicoKitShim.c"] {
                let source = sourceFirmware.appendingPathComponent(file)
                var contents = try String(contentsOf: source, encoding: .utf8)
                contents = contents.replacingOccurrences(of: "../Sources/Blink/main.swift", with: "../Sources/\(name)/main.swift")
                try contents.write(to: firmwareDir.appendingPathComponent(file), atomically: true, encoding: .utf8)
            }
        }

        if let picoRoot {
            let runner = projectRoot.appendingPathComponent("picokit")
            try projectRunner(picoKitRoot: picoRoot).write(to: runner, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runner.path)
        }

        print("""
        Project '\(name)' created for board '\(board)'.
        Project directory: \(projectRoot.path)

        Files created:
          - picokit.json
          - \(sourceFile.path)
          - Firmware/CMakeLists.txt
          - Firmware/BridgingHeader.h
          - Firmware/PicoKitShim.c
          - picokit

        Next steps:
          1. cd \(projectRoot.path)
          2. Run: ./picokit build
          3. Run: ./picokit flash
        """)
    }

    // MARK: - build

    private static func build(_ arguments: [String]) throws {
        let project = try context(arguments)
        let config = project.config
        if let firmwareDirectory = config.firmwareDirectory {
            let firmwareURL = project.url(for: firmwareDirectory)
            let buildDirectory = firmwareURL.appendingPathComponent("build", isDirectory: true)
            var configure = [
                "cmake", "-S", firmwareURL.path, "-B", buildDirectory.path,
                "-G", "Ninja", "-DPICO_BOARD=\(config.board)",
            ]
            if let picoSDKPath = config.picoSDKPath {
                let sdkURL = project.url(for: picoSDKPath)
                configure.append("-DPICO_SDK_PATH=\(sdkURL.path)")
            }
            if config.board.hasPrefix("pico2") {
                configure.append("-DPICO_PLATFORM=rp2350-arm-s")
            }
            if let swiftCompiler = swiftCompilerPath() {
                // Swiftly's ~/.swiftly/bin/swiftc is a dispatch proxy. CMake
                // invokes the compiler directly, so use the real toolchain
                // binary to avoid Swiftly recursively dispatching itself.
                configure.append("-DCMAKE_Swift_COMPILER=\(swiftCompiler)")
            }
            if arguments.contains("--verbose") {
                configure.append("-DCMAKE_VERBOSE_MAKEFILE=ON")
            }
            print("Configuring firmware: \(configure.joined(separator: " "))")
            try runProcess(configure)
            let build = ["cmake", "--build", buildDirectory.path]
            print("Building firmware: \(build.joined(separator: " "))")
            try runProcess(build)
            print("Firmware build succeeded.")
            return
        }
        guard let sdk = option("--swift-sdk", in: arguments) ?? config.swiftSDK else {
            throw CLIError.message("no Swift Embedded SDK is configured. Install one, then set 'swiftSDK' in picokit.json or pass --swift-sdk <id>. Refusing to build a host executable that cannot be flashed to \(config.board).")
        }
        var command = ["swift", "build", "-c", option("--configuration", in: arguments) ?? config.configuration]
        command += ["--swift-sdk", sdk]
        if let product = option("--product", in: arguments) ?? config.product { command += ["--product", product] }
        if arguments.contains("--verbose") { command += ["--verbose"] }
        print("Building: \(command.joined(separator: " "))")
        try runProcess(command, currentDirectory: project.root)
        print("Build succeeded.")
    }

    // MARK: - clean

    private static func clean(_ arguments: [String]) throws {
        let project = try context(arguments)
        let config = project.config
        print("Cleaning build artifacts...")
        if let firmwareDirectory = config.firmwareDirectory {
            let buildDirectory = project.url(for: firmwareDirectory)
                .appendingPathComponent("build", isDirectory: true)
            if FileManager.default.fileExists(atPath: buildDirectory.path) {
                try FileManager.default.removeItem(at: buildDirectory)
            }
        } else {
            try runProcess(["swift", "package", "clean"], currentDirectory: project.root)
        }
        print("Clean complete.")
    }

    // MARK: - flash / upload

    private static func flash(_ arguments: [String]) throws {
        let project = try context(arguments)
        let config = project.config
        let uf2 = option("--uf2", in: arguments) ?? config.uf2
        guard let uf2 else { throw CLIError.message("set 'uf2' in picokit.json or pass --uf2 path/to/app.uf2") }
        let source = project.url(for: uf2)
        guard FileManager.default.fileExists(atPath: source.path) else { throw CLIError.message("UF2 file not found: \(source.path)") }

        let requestedVolume = option("--volume", in: arguments).map { project.url(for: $0) }
        let destinationRoot = requestedVolume ?? findBootVolume() ?? requestBootVolume(using: config, projectRoot: project.root)
        guard let destinationRoot else {
            throw CLIError.message("Pico boot volume not found. Expected /Volumes/RP2350, /Volumes/RPI-RP2350, or /Volumes/RPI-RP2. Hold BOOTSEL while connecting the board, or pass --volume with its exact mounted path.")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destinationRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIError.message("Pico boot volume is not mounted at \(destinationRoot.path)")
        }

        let destination = destinationRoot.appendingPathComponent(source.lastPathComponent)
        #if os(macOS)
        try copyUF2ToBootVolume(source, destinationRoot: destinationRoot)
        #else
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        #endif
        print("Flashed \(source.lastPathComponent) to \(destinationRoot.path)")
        print("Pico will auto-restart after the file transfer completes.")
    }

    // MARK: - debug

    private static func debug(_ arguments: [String]) throws {
        let project = try context(arguments)
        let config = project.config
        let openOCD = option("--openocd", in: arguments) ?? config.openOCD
        let files = config.openOCDConfig
        guard !files.isEmpty else { throw CLIError.message("set 'openOCDConfig' in picokit.json (for example interface/cmsis-dap.cfg,target/rp2040.cfg)") }
        var command = [openOCD] + files.flatMap { ["-f", $0] }
        if let target = option("--target", in: arguments) {
            command += ["-c", "target remote \(target)"]
        }
        print("Starting OpenOCD: \(command.joined(separator: " "))")
        try runProcess(command, currentDirectory: project.root)
    }

    // MARK: - monitor

    private static func monitor(_ arguments: [String]) throws {
        let device: String
        if let explicitDevice = option("--device", in: arguments) {
            device = explicitDevice
        } else {
            let devices = serialDevices()
            guard devices.count == 1, let detected = devices.first else {
                let hint = devices.isEmpty
                    ? "No serial device found. Connect the Pico, then run 'picokit list'."
                    : "Multiple serial devices found. Pass --device <path>.\n\(devices.map { "  \($0)" }.joined(separator: "\n"))"
                throw CLIError.message(hint)
            }
            device = detected
            print("Using serial device \(device)")
        }
        let baud = option("--baud", in: arguments) ?? "115200"
        #if os(macOS)
        try runProcess(["stty", "-f", device, baud, "raw", "-echo"])
        #else
        try runProcess(["stty", "-F", device, baud, "raw", "-echo"])
        #endif
        print("Monitoring \(device) at \(baud) baud. Press Ctrl-C to stop.")
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: device))
        // `availableData` blocks until bytes arrive and is available on the
        // macOS 10.13 deployment target used by this package.
        while true {
            let data = handle.availableData
            guard !data.isEmpty else { return }
            FileHandle.standardOutput.write(data)
        }
    }

    // MARK: - list

    private static func list() {
        let manager = FileManager.default
        let volumes = manager.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: []) ?? []
        let bootVolumes = volumes.filter {
            isPicoBootVolume($0)
        }
        print("=== Pico Boot Volumes ===")
        print(bootVolumes.isEmpty ? "  none (hold BOOTSEL to enter boot mode)" : bootVolumes.map { "  \($0.path)" }.joined(separator: "\n"))

        print("\n=== Serial Devices ===")
        let devices = serialDevices()
        print(devices.isEmpty ? "  none" : devices.map { "  \($0)" }.joined(separator: "\n"))
    }

    // MARK: - info

    private static func showInfo(_ arguments: [String]) throws {
        let project = try context(arguments)
        let config = project.config
        print("=== PicoKit Project Info ===")
        print("  Root:        \(project.root.path)")
        print("  Board:       \(config.board)")
        print("  Product:     \(config.product ?? "default")")
        print("  Config:      \(config.configuration)")
        print("  Firmware:    \(config.firmwareDirectory ?? "SwiftPM")")
        print("  Swift SDK:   \(config.swiftSDK ?? "not set")")
        print("  UF2 path:    \(config.uf2 ?? "not set")")
        print("  OpenOCD:     \(config.openOCD)")
        print("  OpenOCD cfg: \(config.openOCDConfig.joined(separator: ", "))")

        if let uf2 = config.uf2, FileManager.default.fileExists(atPath: project.url(for: uf2).path) {
            let attrs = try FileManager.default.attributesOfItem(atPath: project.url(for: uf2).path)
            if let size = attrs[.size] as? Int {
                print("  UF2 size:    \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))")
            }
        }
    }

    // MARK: - templates

    private static func showTemplates(_ arguments: [String]) {
        print("Available templates:")
        print("  blink         — Toggle onboard LED")
        print("  serial        — USB CDC serial output")
    }

    // MARK: - Template Sources

    private static func templateSource(template: String, board: String, name: String, chip: String) -> String {
        let ledPin = (board == "pico" || board == "pico2") ? "25" : "0"
        switch template {
        case "blink":
            return embeddedBlinkTemplate()
        case "serial":
            return embeddedSerialTemplate(name: name)
        case "adc":
            return adcTemplate(chip: chip)
        case "pwm":
            return pwmTemplate(chip: chip)
        case "i2c":
            return i2cTemplate(chip: chip)
        case "spi":
            return spiTemplate(chip: chip)
        case "button":
            return buttonTemplate(chip: chip)
        case "all":
            return allTemplate(board: board, ledPin: ledPin, chip: chip)
        default:
            return blinkTemplate(board: board, ledPin: ledPin, chip: chip)
        }
    }

    private static func blinkTemplate(board: String, ledPin: String, chip: String) -> String {
        return """
        import PicoKit

        let gpio = PicoGPIO(chip: .\(chip))
        let led = \(ledPin)
        gpio.pinMode(led, .output)

        print("Blink demo on \(board)")

        while true {
            gpio.toggle(led)
            delay(500)
        }
        """
    }

    private static func embeddedBlinkTemplate() -> String {
        return """
        @main
        struct Blink {
            static func main() {
                picokit_stdio_init()
                guard picokit_status_led_init() == 0 else {
                    while true {}
                }
                while true {
                    picokit_status_led_write(1)
                    picokit_sleep_ms(500)
                    picokit_status_led_write(0)
                    picokit_sleep_ms(500)
                }
            }
        }
        """
    }

    private static func embeddedSerialTemplate(name: String) -> String {
        return """
        @main
        struct SerialDemo {
            static func main() {
                picokit_stdio_init()
                picokit_sleep_ms(1_500)

                var counter = 0
                while true {
                    print("\(name) #\\(counter)")
                    counter += 1
                    picokit_sleep_ms(1_000)
                }
            }
        }
        """
    }

    private static func serialTemplate(name: String, chip: String) -> String {
        return """
        import PicoKit

        let gpio = PicoGPIO(chip: .\(chip))
        let serial = PicoUART(.uart0, baudRate: 115_200)
        serial.configurePins(tx: 0, rx: 1, using: gpio)

        serial.print("Hello from \(name)")
        serial.print("PicoKit Serial Demo")

        var counter = 0
        while true {
            serial.print("Tick #\\(counter)")
            counter += 1
            delay(1000)
        }
        """
    }

    private static func adcTemplate(chip: String) -> String {
        return """
        import PicoKit

        let gpio = PicoGPIO(chip: .\(chip))
        let adc = PicoADC()
        adc.begin(channel: .gpio26)

        while true {
            let raw = adc.analogRead(26)
            let voltage = adc.readVoltage()
            let temp = adc.readTemperature()
            print("ADC26: \\(raw) mV: \\(String(format: "%.1f", voltage)) Temp: \\(String(format: "%.1f", temp))C")
            delay(1000)
        }
        """
    }

    private static func pwmTemplate(chip: String) -> String {
        return """
        import PicoKit

        let gpio = PicoGPIO(chip: .\(chip))
        let pwmSlice = PicoPWM(PicoPWM.defaultSlices[0])
        pwmSlice.configurePins(using: gpio)
        pwmSlice.setWrap(255)
        pwmSlice.enable()

        while true {
            for brightness in 0...255 {
                pwmSlice.setCompare(UInt16(brightness))
                delayMicroseconds(100)
            }
            for brightness in (0...255).reversed() {
                pwmSlice.setCompare(UInt16(brightness))
                delayMicroseconds(100)
            }
        }
        """
    }

    private static func i2cTemplate(chip: String) -> String {
        return """
        import PicoKit

        let gpio = PicoGPIO(chip: .\(chip))
        let i2c = PicoI2C(.i2c0, speed: .standard)
        i2c.configurePins(sda: 4, scl: 5, using: gpio)

        // Scan for I2C devices
        print("I2C Scan:")
        for addr in 1...127 {
            if i2c.beginTransmission(UInt8(addr)) {
                i2c.endTransmission()
                print("  Found device at 0x\\(String(addr, radix: 16))")
            }
        }

        while true {
            delay(5000)
        }
        """
    }

    private static func spiTemplate(chip: String) -> String {
        return """
        import PicoKit

        let gpio = PicoGPIO(chip: .\(chip))
        let spi = PicoSPI(.spi0, frequencyHz: 1_000_000, mode: .mode0)
        spi.configurePins(sck: 18, mosi: 19, miso: 16, cs: 17, using: gpio)

        // Select chip
        gpio.digitalWrite(17, .low)

        let data: [UInt8] = [0x00, 0xFF, 0xAA, 0x55]
        let response = spi.transfer(UnsafeBufferPointer(data))
        print("SPI response: \\(response)")

        // Deselect chip
        gpio.digitalWrite(17, .high)

        while true {
            delay(1000)
        }
        """
    }

    private static func buttonTemplate(chip: String) -> String {
        return """
        import PicoKit

        let gpio = PicoGPIO(chip: .\(chip))
        let button = Button(ButtonConfig(pin: 17, activeState: .low), using: gpio)
        let led = LEDController(gpio: gpio, pin: 25)

        print("Button demo — press GPIO17 to toggle LED")

        while true {
            if button.wasPressed() {
                led.toggle()
                print("Button pressed! LED toggled.")
            }
            delay(20)
        }
        """
    }

    private static func allTemplate(board: String, ledPin: String, chip: String) -> String {
        return """
        import PicoKit

        // Setup GPIO
        let gpio = PicoGPIO(chip: .\(chip))

        // LED
        let led = LEDController(gpio: gpio, pin: \(ledPin))

        // UART Serial
        let serial = PicoUART(.uart0, baudRate: 115_200)
        serial.configurePins(tx: 0, rx: 1, using: gpio)

        // ADC
        let adc = PicoADC()
        adc.begin(channel: .gpio26)

        // PWM
        let pwmSlice = PicoPWM(PicoPWM.defaultSlices[0])
        pwmSlice.configurePins(using: gpio)
        pwmSlice.setWrap(255)
        pwmSlice.enable()

        // Button
        let button = Button(ButtonConfig(pin: 17, activeState: .low), using: gpio)

        serial.print("PicoKit Full Demo — \(board)")

        var tick: UInt = 0
        while true {
            // Blink LED
            led.toggle()

            // Read ADC
            let adcVal = adc.analogRead(26)
            serial.print("Tick \\(tick): ADC=\\(adcVal)")

            // PWM sweep
            pwmSlice.setCompare(UInt16(tick % 256))

            // Button check
            if button.wasPressed() {
                serial.print("Button pressed!")
            }

            tick += 1
            delay(500)
        }
        """
    }

    private static func packageSwiftContent(name: String) -> String {
        return """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "\(name)",
            platforms: [
                .macOS(.v13),
            ],
            dependencies: [
                .package(path: "../PicoKit"),
            ],
            targets: [
                .executableTarget(
                    name: "\(name)",
                    dependencies: [
                        .product(name: "PicoKit", package: "PicoKit"),
                    ],
                    swiftSettings: [
                        .enableExperimentalFeature("StrictConcurrency"),
                    ]
                ),
            ]
        )
        """
    }

    // MARK: - Helpers

    private static func context(_ arguments: [String]) throws -> ProjectContext {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let configURL: URL
        if let path = option("--context", in: arguments) {
            configURL = URL(fileURLWithPath: path, relativeTo: currentDirectory).standardizedFileURL
        } else if let discovered = findContext(from: currentDirectory) {
            configURL = discovered
        } else {
            throw CLIError.message("no picokit.json found in this directory or its parents. Run 'picokit init --board pico' first, or pass --context /path/to/picokit.json.")
        }
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw CLIError.message("project context not found: \(configURL.path)")
        }
        let config = try JSONDecoder().decode(PicoKitConfig.self, from: Data(contentsOf: configURL))
        return ProjectContext(root: configURL.deletingLastPathComponent(), config: config)
    }

    private static func findContext(from directory: URL) -> URL? {
        var candidate = directory.standardizedFileURL
        while true {
            let context = candidate.appendingPathComponent("picokit.json")
            if FileManager.default.fileExists(atPath: context.path) { return context }
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { return nil }
            candidate = parent
        }
    }

    private static func findPicoKitRoot(from directory: URL) -> URL? {
        var candidate = directory
        while candidate.path != "/" {
            let package = candidate.appendingPathComponent("Package.swift").path
            let library = candidate.appendingPathComponent("Sources/PicoKit").path
            if FileManager.default.fileExists(atPath: package), FileManager.default.fileExists(atPath: library) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }

    private static func option(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func swiftCompilerPath() -> String? {
        let fileManager = FileManager.default
        var candidates: [String] = []
        if let explicit = ProcessInfo.processInfo.environment["PICO_SWIFTC"], !explicit.isEmpty {
            candidates.append(explicit)
        }
        if let toolchains = ProcessInfo.processInfo.environment["SWIFTLY_TOOLCHAINS_DIR"] {
            candidates.append(URL(fileURLWithPath: toolchains)
                .appendingPathComponent("swift-latest.xctoolchain/usr/bin/swiftc").path)
        }
        candidates.append(contentsOf: [
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc",
            "/usr/bin/swiftc",
        ])
        return candidates.first { fileManager.isExecutableFile(atPath: $0) && !$0.hasSuffix("/.swiftly/bin/swiftc") }
    }

    private static func projectRunner(picoKitRoot: URL) -> String {
        let quotedRoot = picoKitRoot.path.replacingOccurrences(of: "'", with: "'\"'\"'")
        return """
        #!/bin/sh
        exec swift run --package-path '\(quotedRoot)' picokit "$@"
        """
    }

    private static func serialDevices() -> [String] {
        let devices = (try? FileManager.default.contentsOfDirectory(atPath: "/dev"))?.filter {
            $0.hasPrefix("cu.usb") || $0.hasPrefix("ttyACM") || $0.hasPrefix("ttyUSB")
        } ?? []
        return devices.sorted().map { "/dev/\($0)" }
    }

    private static func findBootVolume() -> URL? {
        // Finder and Disk Arbitration can expose a newly mounted FAT volume
        // before `mountedVolumeURLs` refreshes its metadata. Check the normal
        // macOS mount paths directly first.
        for path in ["/Volumes/RP2350", "/Volumes/RPI-RP2350", "/Volumes/RPI-RP2"] {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: []) ?? []
        return volumes.first(where: isPicoBootVolume)
    }

    /// Ask a running PicoKit firmware to enter the ROM bootloader, then wait
    /// for macOS to mount its UF2 volume. `pico_stdio_usb` exposes the vendor
    /// reset interface required by `picotool reboot -u -f`.
    private static func requestBootVolume(using config: PicoKitConfig, projectRoot: URL) -> URL? {
        guard let picotool = findPicotool(config, projectRoot: projectRoot) else { return nil }
        do {
            print("Requesting BOOTSEL through USB…")
            try runProcess([picotool, "reboot", "-u", "-f"])
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let volume = findBootVolume() { return volume }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return nil
    }

    private static func findPicotool(_ config: PicoKitConfig, projectRoot: URL) -> String? {
        var candidates = [
            projectRoot.appendingPathComponent("Tools/picotool-build/picotool").path,
            "/opt/homebrew/bin/picotool",
            "/usr/local/bin/picotool",
        ]
        if let configured = config.picotool {
            candidates.insert(
                configured.hasPrefix("/") ? configured : projectRoot.appendingPathComponent(configured).standardizedFileURL.path,
                at: 0
            )
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    #if os(macOS)
    private static func copyUF2ToBootVolume(_ source: URL, destinationRoot: URL) throws {
        let deadline = Date().addingTimeInterval(5)
        var lastError: Error?

        repeat {
            do {
                // The freshly mounted RP2350 FAT volume can briefly reject
                // writes. Disabling macOS metadata copying also avoids ._ files.
                try runProcess(["env", "COPYFILE_DISABLE=1", "cp", "-X", source.path, destinationRoot.path], quiet: true)
                return
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.25)
            }
        } while Date() < deadline

        throw lastError ?? CLIError.message("could not copy UF2 to \(destinationRoot.path)")
    }
    #endif

    private static func isPicoBootVolume(_ volume: URL) -> Bool {
        let name = (try? volume.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? ""
        return ["RPI-RP2", "RPI-RP2350", "RP2350"].contains(name)
    }

    private static func runProcess(_ command: [String], currentDirectory: URL? = nil, quiet: Bool = false) throws {
        precondition(!command.isEmpty)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.currentDirectoryURL = currentDirectory
        if !quiet {
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CLIError.message("command failed (exit \(process.terminationStatus)): \(command.joined(separator: " "))") }
    }

    fileprivate static let usage = """
    PicoKit — Swift Embedded utilities for Raspberry Pi Pico and Pico 2

    Commands:
      init    [--board BOARD] [--name NAME] [--template TPL] [--force]
              [--path PATH]
              Create a standalone sibling project. Templates: blink, serial
      new     Alias for init
      build, b [--configuration debug|release] [--swift-sdk SDK] [--product P]
              Build the firmware
      clean, c Remove build artifacts
      flash, f [--uf2 PATH] [--volume PATH]
              Reboot a running PicoKit firmware into BOOTSEL, then copy UF2
      upload  Alias for flash
      make, m Build then flash
      debug   [--openocd PATH] [--target TARGET]
              Start OpenOCD debug session
      monitor, serial, mon [--device /dev/cu.usbmodem…] [--baud 115200]
              Monitor serial output; automatically selects the only Pico device
      list, devices
              Show Pico boot volumes and serial devices
      info    Show current project configuration
      template List available project templates

    Boards: pico, pico-w, pico2, pico2_w

    Commands locate picokit.json in the current directory or a parent directory.
    Generated projects include ./picokit, so use ./picokit build, flash, or monitor.
    """
}

private struct PicoKitConfig: Codable {
    var board: String
    var firmwareDirectory: String? = nil
    var picoSDKPath: String? = nil
    var picotool: String? = nil
    var swiftSDK: String? = nil
    var product: String? = nil
    var configuration = "release"
    var uf2: String? = nil
    var openOCD = "openocd"
    var openOCDConfig: [String] = []
}

private struct ProjectContext {
    let root: URL
    let config: PicoKitConfig

    func url(for path: String) -> URL {
        path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : root.appendingPathComponent(path).standardizedFileURL
    }
}

private enum CLIError: LocalizedError {
    case usage
    case message(String)
    var errorDescription: String? {
        switch self {
        case .usage: PicoKitCommand.usage
        case .message(let text): text
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
