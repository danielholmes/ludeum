import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// libretro-thumbnails is no longer a source of Box art (ADR 0020): the journal's `v38` drops what each ROM kept of it,
/// and the cache's `v5` what it kept, listings and images.
@Suite struct NoLibretroTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "no libretro \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test func aROMKeepsNothingOfLibretroAndEverythingElse() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = try DatabaseQueue(path: directory.appending(path: "journal.sqlite").path(percentEncoded: false))
        try LudeumSchema.migrator.migrate(db, upTo: "v37 regions looked up")
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO platform (id, name) VALUES (19, 'SNES');
                    INSERT INTO rom (id, platformId, folderName, fileName, name, regions, libretroLookedUp, libretroBoxart)
                    VALUES (1, 19, 'Gods (USA)', 'Gods (USA).sfc', 'Gods (USA)', '["USA"]', 1,
                        'Nintendo - Super Nintendo Entertainment System/Named_Boxarts/Gods (USA).png');
                    UPDATE rom SET updatedAt = '2026-10-01 00:00:00.000';
                    """)
        }
        try db.close()

        let journal = try LudeumStore(directory: directory)

        try journal.db.read { db in
            let columns = try db.columns(in: "rom").map(\.name)
            #expect(!columns.contains { $0.hasPrefix("libretro") })
            let row = try #require(try Row.fetchOne(db, sql: "SELECT folderName, regions, updatedAt FROM rom WHERE id = 1"))
            #expect(row["folderName"] as String == "Gods (USA)")
            #expect(row["regions"] as String == #"["USA"]"#)
            #expect(row["updatedAt"] as String == "2026-10-01 00:00:00.000")
        }
    }

    @Test func theCacheKeepsNothingOfLibretroAndEverythingElse() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = try DatabaseQueue(path: directory.appending(path: "cache.sqlite").path(percentEncoded: false))
        try CacheStore.migrator(directory: directory).migrate(db, upTo: "v4")
        try db.write { db in
            try db.execute(
                sql: "INSERT INTO entry VALUES ('libretro:listing:Nintendo_-_Game_Boy', x'7B7D', 0), ('igdb:game:1', x'7B7D', 0)")
        }
        try db.close()
        let images = directory.appending(path: "images", directoryHint: .isDirectory)
        for path in ["libretro/Nintendo - Game Boy/Named_Boxarts/Tetris (World).png", "launchbox/sm1.jpg"] {
            let file = images.appending(path: path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: file)
        }

        let cache = try CacheStore(directory: directory)

        #expect(try cache.entries(["libretro:listing:Nintendo_-_Game_Boy", "igdb:game:1"]).keys.sorted() == ["igdb:game:1"])
        #expect(!FileManager.default.fileExists(atPath: images.appending(path: "libretro").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: images.appending(path: "launchbox/sm1.jpg").path(percentEncoded: false)))
    }
}
