// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Magpie",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "ClipboardEngine"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.0.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Magpie",
            dependencies: [
                "ClipboardEngine",
                .product(name: "Sparkle", package: "Sparkle"),
                "KeyboardShortcuts",
            ],
            path: "Magpie",
            exclude: [
                "Magpie.entitlements",
                "Info.plist",
                "Resources",
            ]
        ),
    ]
)
