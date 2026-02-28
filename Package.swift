// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Magpie",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "ClipboardEngine"),
    ],
    targets: [
        .executableTarget(
            name: "Magpie",
            dependencies: ["ClipboardEngine"],
            path: "Magpie"
        ),
    ]
)
