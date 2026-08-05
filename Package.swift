// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Magpie",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "ClipboardEngine"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.0.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
        .package(url: "https://github.com/mixpanel/mixpanel-swift.git", from: "4.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "Magpie",
            dependencies: [
                "ClipboardEngine",
                "MagpieKeeperCore",
                .product(name: "Sparkle", package: "Sparkle"),
                "KeyboardShortcuts",
                .product(name: "Mixpanel", package: "mixpanel-swift"),
            ],
            path: "Magpie",
            exclude: [
                "Magpie.entitlements",
                "Info.plist",
                "Resources",
            ]
        ),
        .target(
            name: "MagpieKeeperCore",
            path: "MagpieKeeperCore"
        ),
        .executableTarget(
            name: "MagpieKeeper",
            dependencies: ["MagpieKeeperCore"],
            path: "MagpieKeeper",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "MagpieKeeper/Info.plist",
                ]),
            ]
        ),
        .testTarget(
            name: "MagpieTests",
            dependencies: ["Magpie"],
            path: "Tests/MagpieTests"
        ),
        .testTarget(
            name: "MagpieKeeperCoreTests",
            dependencies: ["MagpieKeeperCore"],
            path: "Tests/MagpieKeeperCoreTests"
        ),
    ]
)
