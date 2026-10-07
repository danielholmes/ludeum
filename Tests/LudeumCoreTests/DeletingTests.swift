import Foundation
import Testing

@testable import LudeumCore

@Suite struct DeletingTests {
    let h: LudeumHarness
    let game: GameID

    init() throws {
        h = try LudeumHarness()
        game = try h.addGame()
    }

    private func recordROM(missing: Bool) throws {
        try h.journal.recordROM(game: game, fileName: "Super Metroid (Japan, USA).sfc", missing: missing)
    }

    @Test func refusesWhileTheGameHasAnyCopy() throws {
        try recordROM(missing: true)
        #expect(throws: LudeumError.gameHasCopies) { try h.journal.deleteGame(game) }

        try h.journal.deleteMissingROMs(of: game)
        let copy = try h.journal.addCopy(game, CopyDraft(kind: .physical, gone: Gone()))
        // A Gone Copy is history I chose to keep, so it blocks too.
        #expect(throws: LudeumError.gameHasCopies) { try h.journal.deleteGame(game) }

        try h.journal.deleteCopy(copy)
        try h.journal.deleteGame(game)
        #expect(throws: LudeumError.gameNotFound) { try h.journal.game(game) }
    }

    @Test func takesItsJournalDataWithIt() throws {
        try h.journal.setRating(game, Rating(tenths: 95))
        try h.journal.addPlaythrough(game, PlaythroughDraft(start: PartialDate("2020")!, outcome: .finished))
        let list = try h.journal.createList("Metroid")
        try h.journal.addToList(list, game)

        try h.journal.deleteGame(game)

        #expect(throws: LudeumError.gameNotFound) { try h.journal.game(game) }
        #expect(try h.journal.ratingHistory(game).isEmpty)
        #expect(try h.journal.playthroughs(game).isEmpty)
        #expect(try h.journal.games(in: list).isEmpty)
    }
}

/// Deleting a ROM from its Game: a missing one just leaves the journal; a present one's files go to the Trash first.
@Suite struct DeletingROMsTests {
    let h: LudeumHarness
    let game: GameID
    let snes: FakeROMFolder
    let trash: URL

    init() throws {
        h = try LudeumHarness()
        game = try h.addGame("Road Rash")
        snes = try FakeROMFolder(in: h.directory, platform: 19)
        trash = h.directory.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    private func rom(_ fileName: String) throws -> LudeumROM {
        try #require(try h.journal.roms(of: game).first { $0.fileName == fileName })
    }

    private func delete(_ rom: LudeumROM) throws {
        let trash = trash
        try h.journal.deleteROM(rom.id, romFolders: [snes.folder]) {
            try FileManager.default.moveItem(at: $0, to: trash.appending(path: $0.lastPathComponent))
        }
    }

    private func trashed() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: trash.path(percentEncoded: false)).sorted()
    }

    @Test func deletesAMissingROMAndKeepsTheGame() throws {
        try h.journal.recordROM(game: game, fileName: "Road Rash.7z", missing: true)
        try h.journal.recordROM(game: game, fileName: "Road Rash (USA).7z", missing: false)

        try delete(try rom("Road Rash.7z"))

        #expect(try h.journal.roms(of: game).map(\.fileName) == ["Road Rash (USA).7z"])
        #expect(try h.journal.game(game).name == "Road Rash")
        #expect(try trashed().isEmpty)
    }

    @Test func aPresentROMsFilesGoToTheTrashFirst() throws {
        try snes.add("Road Rash (USA).sfc")
        try h.journal.recordROM(game: game, fileName: "Road Rash (USA).sfc", missing: false)

        try delete(try rom("Road Rash (USA).sfc"))

        #expect(try trashed() == ["Road Rash (USA).sfc"])
        #expect(try h.journal.roms(of: game).isEmpty)
        #expect(try h.journal.game(game).name == "Road Rash")
    }

    @Test func refusedWithNothingTrashedWhenAPresentROMsFilesArentThere() throws {
        try h.journal.recordROM(game: game, fileName: "Road Rash (USA).sfc", missing: false)

        #expect(throws: ReviewError.romFilesNotFound) { try delete(try rom("Road Rash (USA).sfc")) }
        #expect(try h.journal.roms(of: game).count == 1)
    }

    @Test func deletesEveryMissingROMAtOnceAndKeepsThePresentOnes() throws {
        try h.journal.recordROM(game: game, fileName: "Road Rash.7z", missing: true)
        try h.journal.recordROM(game: game, fileName: "Road Rash (Europe).7z", missing: true)
        try h.journal.recordROM(game: game, fileName: "Road Rash (USA).7z", missing: false)

        try h.journal.deleteMissingROMs(of: game)

        #expect(try h.journal.roms(of: game).map(\.fileName) == ["Road Rash (USA).7z"])
    }
}

@Suite struct ROMGameTests {
    @Test func findsTheGameItsMatchedTo() throws {
        let h = try LudeumHarness()
        let game = try h.addGame("Okami")
        try h.journal.recordROM(game: game, fileName: "Okami (USA).7z", missing: false)
        let rom = try #require(try h.journal.roms(of: game).first)

        #expect(try h.journal.game(ofROM: rom.id) == game)
        #expect(try h.journal.game(ofROM: rom.id + 1) == nil)
    }
}
