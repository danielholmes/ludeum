// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Ludeum",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LudeumCore", targets: ["LudeumCore"]),
        .executable(name: "ludeum-import", targets: ["ludeum-import"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "LudeumCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "ludeum-import",
            dependencies: ["LudeumCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "LudeumCoreTests",
            dependencies: ["LudeumCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
    ]
)
