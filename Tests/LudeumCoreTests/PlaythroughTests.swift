import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// The migration from a Playthrough's free-text Version and Played via to the Copy it was played on.
@Suite struct PlaythroughCopyMigrationTests {
    @Test func aVersionOfOneOfItsROMsBecomesThatROMAndTheRestGoIntoNotes() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "migration \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let db = try DatabaseQueue(path: directory.appending(path: "journal.sqlite").path(percentEncoded: false))
        try LudeumSchema.migrator.migrate(db, upTo: "v22 copies")
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO platform VALUES (18, 'NES'), (21, 'GameCube');
                    INSERT INTO game (id, platformId, name) VALUES (1, 18, 'Castlevania'), (2, 21, 'Tales of Symphonia');
                    INSERT INTO rom (id, platformId, folderName, fileName, name, version, discNumber, gameId, matchKind, matchedAt)
                    VALUES
                        (10, 18, 'Castlevania (USA)', 'Castlevania (USA).7z', 'Castlevania (USA)', 'USA', NULL, 1, 'manual', 0),
                        (11, 18, 'Castlevania (USA) (Rev A)', 'Castlevania (USA) (Rev A).7z', 'Castlevania (USA) (Rev A)',
                            'USA · Rev A', NULL, 1, 'manual', 0),
                        (20, 21, 'ToS (USA) (Disc 1)', 'ToS (USA) (Disc 1).rvz', 'ToS (USA) (Disc 1)', 'USA', 1, 2, 'manual', 0),
                        (21, 21, 'ToS (USA)', 'ToS (USA).m3u', 'ToS (USA)', 'USA', NULL, 2, 'manual', 0);
                    INSERT INTO playthrough (id, gameId, start, notes, version, playedVia) VALUES
                        (1, 1, '2026-09', 'Loop 1', 'USA · Rev A', NULL),
                        (2, 1, '2020', NULL, 'Japan', 'Analogue Pocket'),
                        (3, 2, '2004', NULL, 'USA', NULL),
                        (4, 2, '2005', 'Kept', '  ', '');
                    """)
        }
        try db.close()

        let journal = try LudeumStore(directory: directory)

        let castlevania = try journal.playthroughs(1).map(\.draft)
        #expect(castlevania.map(\.copy) == [nil, .rom(11)])
        #expect(castlevania.map(\.notes) == ["Version: Japan\nPlayed via Analogue Pocket", "Loop 1"])
        // A playlist before its Discs; blank text is nothing.
        let tales = try journal.playthroughs(2).map(\.draft)
        #expect(tales.map(\.copy) == [.rom(21), nil])
        #expect(tales.map(\.notes) == [nil, "Kept"])
    }
}

/// The migration that rebuilds `playthrough` with its CHECK that an ended Playthrough has an end date.
@Suite struct PlaythroughEndMigrationTests {
    @Test func keepsEveryRowWithItsTimestampsPlayersAndCopy() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "migration \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let db = try DatabaseQueue(path: directory.appending(path: "journal.sqlite").path(percentEncoded: false))
        try LudeumSchema.migrator.migrate(db, upTo: "v47 want to buy flag")
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO platform (id, name) VALUES (19, 'SNES');
                    INSERT INTO game (id, platformId, name) VALUES (1, 19, 'Super Metroid');
                    INSERT INTO copy (id, gameId, kind) VALUES (5, 1, 'physical');
                    INSERT INTO player (id, firstName, lastName, colour) VALUES (3, 'Sam', 'Aran', 'blue');
                    INSERT INTO playthrough (id, gameId, start, "end", outcome, notes, copyId) VALUES
                        (7, 1, '2024-03', '2024-04', 'finished', '100%', 5),
                        (8, 1, '2026', NULL, NULL, NULL, NULL);
                    INSERT INTO playthroughPlayer (playthroughId, playerId) VALUES (7, 3);
                    UPDATE playthrough SET createdAt = '2026-01-01 00:00:00.000', updatedAt = '2026-02-01 00:00:00.000';
                    """)
        }
        let before = try db.read { db in try Row.fetchAll(db, sql: "SELECT * FROM playthrough ORDER BY id") }

        try LudeumSchema.migrator.migrate(db)

        let (after, players, foreignKeyProblems, attached) = try db.read { db in
            (
                try Row.fetchAll(db, sql: "SELECT * FROM playthrough ORDER BY id"),
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM playthroughPlayer"),
                try Row.fetchAll(db, sql: "PRAGMA foreign_key_check"),
                Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE tbl_name = 'playthrough' AND type != 'table'"))
            )
        }
        #expect(after == before)
        #expect(players == 1)
        #expect(foreignKeyProblems.isEmpty)
        #expect(
            attached == [
                "playthrough_on_gameId", "playthrough_on_romId", "playthrough_on_copyId", "playthrough_createdAt",
                "playthrough_updatedAt",
            ])
        // The timestamps' triggers still work.
        try db.write { db in try db.execute(sql: "UPDATE playthrough SET notes = 'Again' WHERE id = 8") }
        let updatedAt = try db.read { db in try String.fetchOne(db, sql: "SELECT updatedAt FROM playthrough WHERE id = 8") }
        #expect(updatedAt != "2026-02-01 00:00:00.000")
    }

    @Test func failsChangingNothingWhileAnEndedPlaythroughHasNoEnd() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "migration \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let db = try DatabaseQueue(path: directory.appending(path: "journal.sqlite").path(percentEncoded: false))
        try LudeumSchema.migrator.migrate(db, upTo: "v47 want to buy flag")
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO platform (id, name) VALUES (19, 'SNES');
                    INSERT INTO game (id, platformId, name) VALUES (1, 19, 'Super Metroid');
                    INSERT INTO playthrough (gameId, start, outcome) VALUES (1, '2024', 'finished');
                    """)
        }

        #expect(throws: DatabaseError.self) { try LudeumSchema.migrator.migrate(db) }
        let (applied, count) = try db.read { db in
            (try LudeumSchema.migrator.appliedMigrations(db).last, try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM playthrough"))
        }
        #expect(applied == "v47 want to buy flag")
        #expect(count == 1)
    }
}

@Suite struct PlaythroughTests {
    let h: LudeumHarness
    let game: GameID

    init() throws {
        h = try LudeumHarness()
        game = try h.addGame()
    }

    private func date(_ text: String) -> PartialDate { PartialDate(text)! }

    @Test func keepsEveryFieldAcrossARelaunch() throws {
        try h.journal.recordROM(game: game, fileName: "Super Metroid (Japan, USA).sfc", missing: false)
        let draft = PlaythroughDraft(
            start: date("2024-03"), end: date("2024-04-02"), outcome: .finished, notes: "100% items",
            copy: .rom(try h.journal.roms(of: game)[0].id))
        let id = try h.journal.addPlaythrough(game, draft)
        try h.reopen()

        #expect(try h.journal.playthroughs(game) == [Playthrough(id: id, draft)])
    }

    @Test func everyFieldButTheStartIsOptional() throws {
        _ = try h.journal.addPlaythrough(game, PlaythroughDraft(start: date("2026")))

        #expect(try h.journal.playthroughs(game).count == 1)
    }

    @Test func refusesAnEndBeforeTheStart() throws {
        #expect(throws: LudeumError.endBeforeStart) {
            try h.journal.addPlaythrough(game, PlaythroughDraft(start: date("2024-03"), end: date("2023"), outcome: .finished))
        }
        #expect(throws: LudeumError.endBeforeStart) {
            try h.journal.addPlaythrough(game, PlaythroughDraft(start: date("2024-03-10"), end: date("2024-03-09"), outcome: .finished))
        }
    }

    @Test func refusesAFinishedOrDroppedPlaythroughWithNoEnd() throws {
        for outcome in [Outcome.finished, .dropped] {
            #expect(throws: LudeumError.endRequired) {
                try h.journal.addPlaythrough(game, PlaythroughDraft(start: date("2024"), outcome: outcome))
            }
        }
        let id = try h.journal.addPlaythrough(game, PlaythroughDraft(start: date("2024")))
        #expect(throws: LudeumError.endRequired) {
            try h.journal.updatePlaythrough(id, PlaythroughDraft(start: date("2024"), outcome: .finished))
        }
        #expect(try h.journal.playthroughs(game).map(\.draft) == [PlaythroughDraft(start: date("2024"))])
    }

    @Test func theJournalItselfRefusesAnEndedPlaythroughWithNoEnd() throws {
        #expect(throws: DatabaseError.self) {
            try h.journal.db.write { db in
                try db.execute(sql: "INSERT INTO playthrough (gameId, start, outcome) VALUES (?, '2024', 'dropped')", arguments: [game])
            }
        }
    }

    @Test func allowsALessPreciseDateThatContainsTheOther() throws {
        _ = try h.journal.addPlaythrough(game, PlaythroughDraft(start: date("2024-03"), end: date("2024"), outcome: .finished))
        _ = try h.journal.addPlaythrough(game, PlaythroughDraft(start: date("2024"), end: date("2024-01"), outcome: .finished))

        #expect(try h.journal.playthroughs(game).count == 2)
    }

    @Test func canBeEditedAndDeleted() throws {
        let id = try h.journal.addPlaythrough(game, PlaythroughDraft(start: date("2026-09")))
        let finished = PlaythroughDraft(start: date("2026-09"), end: date("2026-10"), outcome: .finished)

        try h.journal.updatePlaythrough(id, finished)
        #expect(try h.journal.playthroughs(game) == [Playthrough(id: id, finished)])

        try h.journal.deletePlaythrough(id)
        #expect(try h.journal.playthroughs(game).isEmpty)
    }
}

/// The Copy a Playthrough was played on: one of its own Game's, which then can't be deleted until it says otherwise.
@Suite struct PlaythroughCopyTests {
    let h: LudeumHarness
    let game: GameID

    init() throws {
        h = try LudeumHarness()
        game = try h.addGame()
    }

    /// A ROM of the Game, present unless `missing`.
    func rom(_ fileName: String = "Super Metroid (USA).sfc", missing: Bool = false, of game: GameID? = nil) throws -> Int64 {
        let game = game ?? self.game
        try h.journal.recordROM(game: game, fileName: fileName, missing: missing)
        return try #require(try h.journal.roms(of: game).first { $0.fileName == fileName }).id
    }

    @discardableResult
    func playthrough(on copy: CopyID?) throws -> Int64 {
        try h.journal.addPlaythrough(game, PlaythroughDraft(start: PartialDate("2026")!, copy: copy))
    }

    @Test func aHandRecordedCopyOrAROMReadsBack() throws {
        let copy = try h.journal.addCopy(game, CopyDraft(kind: .physical))
        let rom = try rom()
        try playthrough(on: .copy(copy))
        try playthrough(on: .rom(rom))

        #expect(try h.journal.playthroughs(game).map(\.draft.copy) == [.copy(copy), .rom(rom)])
    }

    @Test func itCanChangeOrBeCleared() throws {
        let copy = try h.journal.addCopy(game, CopyDraft(kind: .physical))
        let id = try playthrough(on: .copy(copy))
        let rom = try rom()

        try h.journal.updatePlaythrough(id, PlaythroughDraft(start: PartialDate("2026")!, copy: .rom(rom)))
        #expect(try h.journal.playthroughs(game).map(\.draft.copy) == [.rom(rom)])
        try h.journal.updatePlaythrough(id, PlaythroughDraft(start: PartialDate("2026")!))
        #expect(try h.journal.playthroughs(game).map(\.draft.copy) == [nil])
    }

    @Test func anotherGamesCopyIsRefused() throws {
        let other = try h.addGame("Contra III")
        let theirs = try h.journal.addCopy(other, CopyDraft(kind: .physical))
        let theirROM = try rom("Contra III (USA).sfc", of: other)

        #expect(throws: LudeumError.copyNotOfGame) { try playthrough(on: .copy(theirs)) }
        #expect(throws: LudeumError.copyNotOfGame) { try playthrough(on: .rom(theirROM)) }
        let id = try playthrough(on: nil)
        #expect(throws: LudeumError.copyNotOfGame) {
            try h.journal.updatePlaythrough(id, PlaythroughDraft(start: PartialDate("2026")!, copy: .copy(theirs)))
        }
    }

    @Test func aCopyPlayedOnCantBeDeletedUntilThePlaythroughLetsGo() throws {
        let copy = try h.journal.addCopy(game, CopyDraft(kind: .physical))
        let id = try playthrough(on: .copy(copy))

        #expect(throws: LudeumError.copyPlayedOn) { try h.journal.deleteCopy(copy) }
        #expect(try h.journal.copies(of: game).count == 1)

        try h.journal.updatePlaythrough(id, PlaythroughDraft(start: PartialDate("2026")!))
        try h.journal.deleteCopy(copy)
        #expect(try h.journal.copies(of: game).isEmpty)
    }

    @Test func aROMPlayedOnCantBeDeletedAndNothingGoesToTheTrash() throws {
        let present = try rom()
        let missing = try rom("Super Metroid (Japan).sfc", missing: true)
        try playthrough(on: .rom(present))
        try playthrough(on: .rom(missing))
        var trashed: [URL] = []

        #expect(throws: LudeumError.copyPlayedOn) {
            try h.journal.deleteROM(present, romFolders: []) { trashed.append($0) }
        }
        #expect(throws: LudeumError.copyPlayedOn) { try h.journal.deleteROM(missing, romFolders: []) }
        #expect(throws: LudeumError.copyPlayedOn) { try h.journal.deleteMissingROMs(of: game) }
        #expect(trashed.isEmpty)
        #expect(try h.journal.roms(of: game).count == 2)
    }

    @Test func otherMissingROMsStillGoTogether() throws {
        _ = try rom("Super Metroid (Japan).sfc", missing: true)
        _ = try rom("Super Metroid (Europe).sfc", missing: true)
        try playthrough(on: .rom(try rom()))

        try h.journal.deleteMissingROMs(of: game)

        #expect(try h.journal.roms(of: game).map(\.fileName) == ["Super Metroid (USA).sfc"])
    }

    @Test func deletingThePlaythroughLetsItsCopyGo() throws {
        let copy = try h.journal.addCopy(game, CopyDraft(kind: .physical))
        let id = try playthrough(on: .copy(copy))

        try h.journal.deletePlaythrough(id)
        try h.journal.deleteCopy(copy)

        #expect(try h.journal.copies(of: game).isEmpty)
    }
}
