import Foundation
import GRDB
import Testing

@testable import LudeumCore

@Suite struct IntentTests {
    let h: LudeumHarness
    let game: GameID

    init() throws {
        h = try LudeumHarness()
        game = try h.addGame()
    }

    @Test func remembersWhenItWasSet() throws {
        let setAt = h.clock.now()

        try h.journal.setIntent(game, .upNext)

        #expect(try h.journal.game(game).intent == .upNext)
        #expect(try h.journal.game(game).intentSetAt == setAt)
    }

    @Test func changingTheValueResetsTheTimeButTheSameValueDoesNothing() throws {
        try h.journal.setIntent(game, .backlog)
        let first = h.clock.now()
        h.clock.advance(days: 1)

        try h.journal.setIntent(game, .backlog)
        #expect(try h.journal.game(game).intentSetAt == first)

        try h.journal.setIntent(game, .upNext)
        #expect(try h.journal.game(game).intentSetAt == h.clock.now())
    }

    @Test func clearingDropsTheTime() throws {
        try h.journal.setIntent(game, .backlog)

        try h.journal.setIntent(game, nil)

        #expect(try h.journal.game(game).intent == nil)
        #expect(try h.journal.game(game).intentSetAt == nil)
    }

    @Test func importedIntentIsUndated() throws {
        try h.journal.importIntent(game, .backlog)

        #expect(try h.journal.game(game).intent == .backlog)
        #expect(try h.journal.game(game).intentSetAt == nil)
    }

    @Test func wantToBuyIsAFlagBesideTheIntentAndTheLibraryFiltersByIt() throws {
        try h.journal.setIntent(game, .upNext)
        try h.journal.setWantToBuy(game, true)
        let backlogged = try h.addGame("Backlogged")
        try h.journal.setIntent(backlogged, .backlog)

        #expect(try h.journal.game(game).wantToBuy)
        #expect(try h.journal.game(game).intent == .upNext)
        #expect(try h.journal.library(LibraryFilter(wantToBuy: true), sort: .name, ascending: true).map(\.id) == [game])
        #expect(try h.journal.library(LibraryFilter(wantToBuy: false), sort: .name, ascending: true).map(\.id) == [backlogged])
        #expect(try h.journal.library(LibraryFilter(), sort: .name, ascending: true).first { $0.id == game }?.wantToBuy == true)

        try h.journal.setWantToBuy(game, false)
        #expect(try !h.journal.game(game).wantToBuy)
        #expect(try h.journal.game(game).intent == .upNext)
    }

    @Test func startingToPlayClearsTheIntentButNotWantToBuy() throws {
        try h.journal.setIntent(game, .upNext)
        try h.journal.setWantToBuy(game, true)

        try h.journal.startPlaying(game)

        #expect(try h.journal.game(game).intent == nil)
        #expect(try h.journal.game(game).wantToBuy)
    }

    @Test func childhoodIsAFlag() throws {
        try h.journal.setChildhood(game, true)

        #expect(try h.journal.game(game).childhood)
    }
}

/// The migration that lets a Game's Intent be Want to buy.
@Suite struct WantToBuyMigrationTests {
    @Test func gamesKeepEverythingAndANewGameDoesntTakeADeletedOnesId() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "migration \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let db = try DatabaseQueue(path: directory.appending(path: "journal.sqlite").path(percentEncoded: false))
        try LudeumSchema.migrator.migrate(db, upTo: "v20 face-off")
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO platform VALUES (19, 'SNES');
                    INSERT INTO game (id, platformId, igdbGameId, igdbName, nameOverride, childhood, intent, intentSetAt,
                        runAheadFrames, gameBoyModel)
                        VALUES (1, 19, 1234, 'Contra III', 'Contra', 1, 'upNext', '2026-01-01 00:00:00.000', 2, 'sgb'),
                            (2, 19, NULL, NULL, 'Gone', 0, NULL, NULL, NULL, NULL);
                    INSERT INTO playthrough (gameId, start) VALUES (1, '2026');
                    DELETE FROM game WHERE id = 2;
                    """)
        }
        try db.close()

        let journal = try LudeumStore(directory: directory)

        let contra = try journal.game(1)
        #expect(contra.name == "Contra")
        #expect(contra.childhood)
        #expect(contra.intent == .upNext)
        #expect(contra.intentSetAt != nil)
        #expect(try journal.playthroughs(1).count == 1)
        let row = try DatabaseQueue(path: directory.appending(path: "journal.sqlite").path(percentEncoded: false)).read { db in
            try Row.fetchOne(db, sql: "SELECT igdbGameId, igdbName, runAheadFrames, gameBoyModel FROM game WHERE id = 1")
        }
        #expect(row == ["igdbGameId": 1234, "igdbName": "Contra III", "runAheadFrames": 2, "gameBoyModel": "sgb"])
        #expect(try journal.addGame(platformId: 19, name: "New") == 3)
    }

    @Test func aJournalWhoseGamesWereAllDeletedStillDoesntReuseTheirIds() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "migration \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let db = try DatabaseQueue(path: directory.appending(path: "journal.sqlite").path(percentEncoded: false))
        try LudeumSchema.migrator.migrate(db, upTo: "v20 face-off")
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO platform VALUES (19, 'SNES');
                    INSERT INTO game (id, platformId, name) VALUES (5, 19, 'Gone');
                    DELETE FROM game;
                    """)
        }
        try db.close()

        let journal = try LudeumStore(directory: directory)

        #expect(try journal.addGame(platformId: 19, name: "New") == 6)
    }
}

/// The migration that makes Want to buy a flag beside the Intent (ADR 0043).
@Suite struct WantToBuyFlagMigrationTests {
    @Test func wantToBuyIntentsBecomeTheFlagAndNothingElseChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "migration \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appending(path: "journal.sqlite").path(percentEncoded: false)
        let db = try DatabaseQueue(path: path)
        try LudeumSchema.migrator.migrate(db, upTo: "v46 dos program")
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO platform (id, name) VALUES (19, 'SNES');
                    INSERT INTO game (id, platformId, name, intent, intentSetAt) VALUES
                        (1, 19, 'Earthbound', 'wantToBuy', '2026-01-01 00:00:00.000'),
                        (2, 19, 'Chrono Trigger', 'upNext', '2026-01-02 00:00:00.000'),
                        (3, 19, 'F-Zero', NULL, NULL);
                    UPDATE game SET updatedAt = '2026-02-0' || id || ' 00:00:00.000';
                    """)
        }
        try db.close()

        let journal = try LudeumStore(directory: directory)

        let earthbound = try journal.game(1)
        #expect(earthbound.wantToBuy)
        #expect(earthbound.intent == nil)
        #expect(earthbound.intentSetAt == nil)
        let chrono = try journal.game(2)
        #expect(!chrono.wantToBuy)
        #expect(chrono.intent == .upNext)
        #expect(chrono.intentSetAt != nil)
        #expect(try !journal.game(3).wantToBuy)
        let updated = try DatabaseQueue(path: path).read { db in
            try String.fetchAll(db, sql: "SELECT updatedAt FROM game ORDER BY id")
        }
        #expect(updated == ["2026-02-01 00:00:00.000", "2026-02-02 00:00:00.000", "2026-02-03 00:00:00.000"])

        // The trigger is back, watching the new column too.
        try journal.setWantToBuy(3, true)
        let fZero = try DatabaseQueue(path: path).read { db in
            try String.fetchOne(db, sql: "SELECT updatedAt FROM game WHERE id = 3")
        }
        #expect(fZero != "2026-02-03 00:00:00.000")
    }
}

/// The migration that removes Lists.
@Suite struct NoListsMigrationTests {
    @Test func theGamesInListsStayWhenListsGo() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "migration \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let db = try DatabaseQueue(path: directory.appending(path: "journal.sqlite").path(percentEncoded: false))
        try LudeumSchema.migrator.migrate(db, upTo: "v33 no held openemu data")
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO platform (id, name) VALUES (19, 'SNES');
                    INSERT INTO game (id, platformId, name) VALUES (1, 19, 'Super Metroid');
                    INSERT INTO list (id, name) VALUES (1, 'Metroid');
                    INSERT INTO listGame (listId, gameId) VALUES (1, 1);
                    """)
        }
        try db.close()

        let journal = try LudeumStore(directory: directory)

        #expect(try journal.game(1).name == "Super Metroid")
        // `v44 lists` makes new tables, and the ones `v34 no lists` dropped don't come back with it (ADR 0039).
        #expect(try journal.lists().isEmpty)
    }
}
