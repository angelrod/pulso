// swift-tools-version: 6.0
// Pulso 2.0, native: the core (PulsoCore), the panel (PulsoUI), the app, and a preview tool.
import PackageDescription

let package = Package(
    name: "PulsoCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PulsoCore", targets: ["PulsoCore"]),
        .executable(name: "Pulso", targets: ["Pulso"]),
        .executable(name: "PulsoPreview", targets: ["PulsoPreview"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "PulsoCore"),
        .target(name: "PulsoUI", dependencies: ["PulsoCore"]),
        .executableTarget(name: "Pulso", dependencies: [
            "PulsoCore",
            "PulsoUI",
            .product(name: "Sparkle", package: "Sparkle"),
        ], linkerSettings: [
            .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
        ]),
        .executableTarget(name: "PulsoPreview", dependencies: ["PulsoCore", "PulsoUI"]),
        .testTarget(name: "PulsoCoreTests", dependencies: ["PulsoCore"]),
    ]
)
