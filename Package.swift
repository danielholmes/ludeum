// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GamesJournal",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "JournalCore", targets: ["JournalCore"]),
        .executable(name: "journal-import", targets: ["journal-import"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "JournalCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "journal-import",
            dependencies: ["JournalCore"]
        ),
        .testTarget(
            name: "JournalCoreTests",
            dependencies: ["JournalCore"]
        ),
    ]
)
