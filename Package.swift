// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CLIProxyBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CLIProxyBar", targets: ["MenuBar"])],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            from: "2.10.0"
        ),
    ],
    targets: [
        .target(name: "CLIProxyBarCore"),
        .executableTarget(name: "MenuBar", dependencies: ["CLIProxyBarCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "MenuBarTests", dependencies: ["MenuBar", "CLIProxyBarCore"])
    ]
)
