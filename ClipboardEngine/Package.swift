// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipboardEngine",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ClipboardEngine", targets: ["ClipboardEngine"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "ClipboardEngine",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "ClipboardEngineTests",
            dependencies: ["ClipboardEngine"]
        ),
    ]
)
