// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CLIProxyBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CLIProxyBar", targets: ["MenuBar"])],
    targets: [
        .target(name: "CLIProxyBarCore"),
        .executableTarget(name: "MenuBar", dependencies: ["CLIProxyBarCore"]),
        .testTarget(name: "MenuBarTests", dependencies: ["MenuBar", "CLIProxyBarCore"])
    ]
)
