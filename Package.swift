// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EmulatorStudio",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "EmulatorStudio",
            path: "Sources/EmulatorStudio"
        )
    ]
)
