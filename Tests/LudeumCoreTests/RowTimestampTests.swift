import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// Every journal row's `createdAt` and `updatedAt` (ADR 0015), kept by triggers.
@Suite struct RowTimestampTests {
    let h: LudeumHarness

    init() throws {
        h = try LudeumHarness()
    }

    private func timestamps(_ table: String, _ condition: String) throws -> (created: String, updated: String) {
        try h.journal.db.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT createdAt, updatedAt FROM \(table) WHERE \(condition)")!
            return (row["createdAt"], row["updatedAt"])
        }
    }

    /// Puts both of a row's timestamps in the past, so a change to either shows.
    private func age(_ table: String, _ condition: String) throws {
        try h.journal.db.write { db in
            try db.execute(
                sql: "UPDATE \(table) SET createdAt = '2000-01-01 00:00:00.000', updatedAt = '2000-01-01 00:00:00.000' WHERE \(condition)")
        }
    }

    @Test func everyTableKeepsTimestampsWatchingEveryOtherColumn() throws {
        try h.journal.db.read { db in
            let tables = try String.fetchAll(
                db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name <> 'grdb_migrations'")
            #expect(tables.contains("game") && tables.contains("copy"))
            for table in tables {
                let columns = try db.columns(in: table).map(\.name)
                #expect(columns.contains("createdAt") && columns.contains("updatedAt"), "\(table) has no timestamps")
                #expect(
                    try String.fetchOne(
                        db, sql: "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name = ?", arguments: ["\(table)_createdAt"])
                        != nil, "\(table) has no createdAt trigger")
                let updated = try String.fetchOne(
                    db, sql: "SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = ?", arguments: ["\(table)_updatedAt"])
                #expect(updated != nil, "\(table) has no updatedAt trigger")
                for column in columns where !["createdAt", "updatedAt"].contains(column) {
                    #expect(
                        updated?.contains("NEW.\(column.quotedDatabaseIdentifier)") == true,
                        "\(table)'s updatedAt trigger doesn't watch \(column): call LudeumSchema.keepTimestamps for it in the migration that added it"
                    )
                }
            }
        }
    }

    @Test func aNewRowIsCreatedAndUpdatedNow() throws {
        let start = Date()
        let game = try h.addGame()

        let (created, updated) = try timestamps("game", "id = \(game)")
        let date = try #require(Date.fromDatabaseValue(created.databaseValue))
        #expect(abs(date.timeIntervalSince(start)) < 5)
        #expect(updated == created)
    }

    @Test func anUpdateThatChangesSomethingMovesUpdatedAtOnly() throws {
        let game = try h.addGame("Super Metroid")
        try age("game", "id = \(game)")

        try h.journal.db.write { db in try db.execute(sql: "UPDATE game SET name = 'Super Metroid' WHERE id = ?", arguments: [game]) }
        #expect(try timestamps("game", "id = \(game)").updated == "2000-01-01 00:00:00.000")

        try h.journal.db.write { db in try db.execute(sql: "UPDATE game SET name = 'Metroid' WHERE id = ?", arguments: [game]) }
        let (created, updated) = try timestamps("game", "id = \(game)")
        #expect(created == "2000-01-01 00:00:00.000")
        #expect(updated > "2026")
    }

    @Test func replacingACoverKeepsWhenItWasCreated() throws {
        let game = try h.addGame()
        try h.journal.storeCover(game, NormalisedCover(jpeg: Data([1]), width: 1, height: 1, sha256: "a"))
        try age("cover", "gameId = \(game)")

        try h.journal.storeCover(game, NormalisedCover(jpeg: Data([2]), width: 2, height: 2, sha256: "b"))

        let (created, updated) = try timestamps("cover", "gameId = \(game)")
        #expect(created == "2000-01-01 00:00:00.000")
        #expect(updated > "2026")
        #expect(try h.journal.uploadedCover(game) == NormalisedCover(jpeg: Data([2]), width: 2, height: 2, sha256: "b"))
    }

    @Test func changingAPlaythroughsPlayersKeepsThoseWhoStay() throws {
        let game = try h.addGame()
        let sam = try h.journal.addPlayer(PlayerDraft(firstName: "Sam", lastName: "Lee", colour: .teal))
        let alex = try h.journal.addPlayer(PlayerDraft(firstName: "Alex", lastName: "Smith", colour: .red))
        let id = try h.journal.addPlaythrough(game, PlaythroughDraft(start: PartialDate("2024")!, players: [sam, alex]))
        try age("playthroughPlayer", "playthroughId = \(id)")

        try h.journal.updatePlaythrough(id, PlaythroughDraft(start: PartialDate("2024")!, players: [sam]))

        #expect(try timestamps("playthroughPlayer", "playthroughId = \(id) AND playerId = \(sam)").created == "2000-01-01 00:00:00.000")
        #expect(try h.journal.playthroughs(game).map(\.draft.players) == [[sam]])
    }

    @Test func rowsFromBeforeTakeTheStartOfTheDayTimestampsCameIn() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "migration \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let db = try DatabaseQueue(path: directory.appending(path: "journal.sqlite").path(percentEncoded: false))
        try LudeumSchema.migrator.migrate(db, upTo: "v30 attachments")
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO platform VALUES (18, 'NES');
                    INSERT INTO game (id, platformId, name) VALUES (1, 18, 'Castlevania');
                    INSERT INTO copy (gameId, kind) VALUES (1, 'physical');
                    """)
        }
        try db.close()

        let journal = try LudeumStore(directory: directory)

        try journal.db.read { db in
            for table in ["platform", "game", "copy"] {
                let row = try Row.fetchOne(db, sql: "SELECT createdAt, updatedAt FROM \(table)")!
                #expect(row["createdAt"] == "2026-10-14 13:00:00.000")
                #expect(row["updatedAt"] == "2026-10-14 13:00:00.000")
            }
        }
    }
}
