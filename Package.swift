// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MXRatchet",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "Shared", path: "Sources/Shared"),
        .executableTarget(
            name: "MXRatchetHelper",
            dependencies: ["Shared"],
            path: "Sources/MXRatchetHelper",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .executableTarget(
            name: "MXRatchet",
            dependencies: ["Shared"],
            path: "Sources/MXRatchet",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
            ]
        ),
    ]
)
