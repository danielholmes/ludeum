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

    @Test func wantToBuyIsAnIntentAndTheLibraryFiltersByIt() throws {
        try h.journal.setIntent(game, .wantToBuy)
        try h.journal.setIntent(try h.addGame("Backlogged"), .backlog)

        #expect(try h.journal.game(game).intent == .wantToBuy)
        #expect(try h.journal.library(LibraryFilter(intent: .wantToBuy), sort: .name, ascending: true).map(\.id) == [game])
    }

    @Test func childhoodIsAFlag() throws {
        try h.journal.setChildhood(game, true)

        #expect(try h.journal.game(game).childhood)
    }
}

@Suite struct ListTests {
    let h: LudeumHarness

    init() throws { h = try LudeumHarness() }

    @Test func aGameCanBeInManyLists() throws {
        let metroid = try h.addGame("Super Metroid")
        let castlevania = try h.journal.createList("Castlevania")
        let favourites = try h.journal.createList("Favourites")

        try h.journal.addToList(favourites, metroid)
        try h.journal.addToList(castlevania, metroid)
        try h.journal.addToList(favourites, metroid)

        #expect(try h.journal.lists().map(\.name) == ["Castlevania", "Favourites"])
        #expect(try h.journal.lists(containing: metroid).map(\.name) == ["Castlevania", "Favourites"])
        #expect(try h.journal.games(in: favourites) == [metroid])
    }

    @Test func namesAreUnique() throws {
        _ = try h.journal.createList("Zelda")
        let other = try h.journal.createList("Zelda games")

        #expect(throws: LudeumError.listNameTaken) { try h.journal.createList("Zelda") }
        #expect(throws: LudeumError.listNameTaken) { try h.journal.renameList(other, "Zelda") }
    }

    @Test func deletingAListLeavesItsGames() throws {
        let metroid = try h.addGame("Super Metroid")
        let list = try h.journal.createList("Metroid")
        try h.journal.addToList(list, metroid)
        try h.journal.removeFromList(list, metroid)
        try h.journal.addToList(list, metroid)

        try h.journal.deleteList(list)

        #expect(try h.journal.lists().isEmpty)
        #expect(try h.journal.game(metroid).name == "Super Metroid")
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
        try journal.setIntent(1, .wantToBuy)
        #expect(try journal.game(1).intent == .wantToBuy)
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
