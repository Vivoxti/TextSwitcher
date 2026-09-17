// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TextSwitcher",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "TextSwitcher", targets: ["TextSwitcher"])],
    targets: [
        .target(name: "TextSwitcherCore"),
        .executableTarget(name: "TextSwitcher", dependencies: ["TextSwitcherCore"]),
        .testTarget(name: "TextSwitcherCoreTests", dependencies: ["TextSwitcherCore"])
    ],
    swiftLanguageModes: [.v5]
)
