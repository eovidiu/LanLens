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
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "LanLensCore",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "Hummingbird", package: "hummingbird")
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
