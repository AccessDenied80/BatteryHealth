// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BatteryHealth",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "BatteryHealthCore"),
        .executableTarget(name: "BatteryHealth", dependencies: ["BatteryHealthCore"]),
        .testTarget(
            name: "BatteryHealthCoreTests",
            dependencies: ["BatteryHealthCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
