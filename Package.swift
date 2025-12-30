// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LanLens",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "lanlens", targets: ["LanLens"]),
        .executable(name: "LanLensMenuBar", targets: ["LanLensMenuBar"]),
        .library(name: "LanLensCore", targets: ["LanLensCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "LanLens",
            dependencies: ["LanLensCore"],
            path: "Sources/LanLens/App"
        ),
        .executableTarget(
            name: "LanLensMenuBar",
            dependencies: ["LanLensCore"],
            path: "Sources/LanLens/MenuBarApp",
            exclude: ["Resources/Info.plist"]
        ),
        .target(
            name: "LanLensCore",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "Hummingbird", package: "hummingbird")
            ],
            path: "Sources/LanLens/Core"
        ),
        .testTarget(
            name: "LanLensTests",
            dependencies: ["LanLensCore"],
            path: "Tests/LanLensTests"
        )
    ]
)
