// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LanLens",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LanLensCore", targets: ["LanLensCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.2.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "LanLensCore",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/LanLensCore"
        ),
        .testTarget(
            name: "LanLensCoreTests",
            dependencies: ["LanLensCore"],
            path: "Tests/LanLensCoreTests"
        )
    ]
)
