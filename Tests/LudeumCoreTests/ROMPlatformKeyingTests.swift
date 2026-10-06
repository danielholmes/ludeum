import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// A journal written before ROMs were keyed by Platform, reopened by this build.
@Suite struct ROMPlatformKeyingTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "rom keying \(UUID().uuidString)", directoryHint: .isDirectory)

    /// A journal at "v13 players", with `setUp` run against it, then opened as the current schema.
    func oldJournal(_ setUp: (Database) throws -> Void) throws -> LudeumStore {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let db = try DatabaseQueue(path: directory.appending(path: "journal.sqlite").path(percentEncoded: false))
        try LudeumSchema.migrator.migrate(db, upTo: "v13 players")
        try db.write(setUp)
        try db.close()
        return try LudeumStore(directory: directory)
    }

    @Test func eachROMTakesItsGamesPlatformElseItsSystemsFirst() throws {
        let journal = try oldJournal { db in
            try db.execute(
                sql: """
                    INSERT INTO platform VALUES (22, 'Game Boy Color'), (8, 'PlayStation 2');
                    INSERT INTO game (id, platformId, name) VALUES (1, 22, 'Pokemon Gold'), (2, 8, 'Okami');
                    INSERT INTO rom (openEmuPk, md5, fileName, systemId, gameId, matchKind, matchedAt)
                        VALUES (10, 'aa', 'Pokemon Gold.gbc', 'openemu.system.gb', 1, 'manual', 0);
                    INSERT INTO rom (openEmuPk, md5, fileName, systemId) VALUES (11, 'bb', 'Tetris.gb', 'openemu.system.gb');
                    INSERT INTO rom (folderName, fileName, systemId, gameId, matchKind, matchedAt)
                        VALUES ('Okami (USA)', 'Okami (USA).iso', 'ludeum.folder.ps2', 2, 'manual', 0);
                    """)
        }

        #expect(try journal.roms(of: 1).map(\.platformId) == [22])
        #expect(try journal.roms(of: 2).map(\.platformId) == [8])
        let review = try #require(try journal.reviewQueue().noSuggestion.first)
        #expect(review.platformId == 33)
        #expect(try journal.platform(33)?.name == "Game Boy")
        let columns = try journal.db.read { try $0.columns(in: "rom").map(\.name) }
        #expect(!columns.contains("systemId"))
        #expect(try journal.db.read { try String.fetchOne($0, sql: "SELECT md5 FROM rom WHERE openEmuPk = 11") } == "bb")
    }

    @Test func twoROMsOfOnePlatformCantShareAName() throws {
        let journal = try oldJournal { _ in }
        try journal.addPlatform(id: 8, name: "PlayStation 2")
        let insert = "INSERT INTO rom (platformId, folderName, fileName) VALUES (8, 'Okami (USA)', ?)"
        try journal.db.write { try $0.execute(sql: insert, arguments: ["Okami (USA).iso"]) }
        #expect(throws: DatabaseError.self) {
            try journal.db.write { try $0.execute(sql: insert, arguments: ["Okami (USA).7z"]) }
        }
    }
}
