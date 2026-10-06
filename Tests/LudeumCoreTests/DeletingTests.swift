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

    @Test func refusesWhileTheGameHasAPresentROM() throws {
        try recordROM(missing: false)

        #expect(throws: LudeumError.gameHasPresentROMs) { try h.journal.deleteGame(game) }
        #expect(try h.journal.game(game).name == "Super Metroid")
    }

    @Test func takesItsJournalDataAndMissingROMsWithIt() throws {
        try recordROM(missing: true)
        try h.journal.setRating(game, Rating(tenths: 95))
        try h.journal.addPlaythrough(game, PlaythroughDraft(start: PartialDate("2020")!, outcome: .finished))
        let list = try h.journal.createList("Metroid")
        try h.journal.addToList(list, game)

        try h.journal.deleteGame(game)

        #expect(throws: LudeumError.gameNotFound) { try h.journal.game(game) }
        #expect(try h.journal.ratingHistory(game).isEmpty)
        #expect(try h.journal.playthroughs(game).isEmpty)
        #expect(try h.journal.games(in: list).isEmpty)
        // The ROM went too, so it can be recorded afresh if it reappears.
        let again = try h.addGame("Super Metroid again")
        try h.journal.recordROM(game: again, fileName: "Super Metroid (Japan, USA).sfc", missing: false)
    }
}

@Suite struct ForgettingROMsTests {
    let h: LudeumHarness
    let game: GameID

    init() throws {
        h = try LudeumHarness()
        game = try h.addGame("Road Rash")
    }

    private func rom(_ fileName: String) throws -> LudeumROM {
        try #require(try h.journal.roms(of: game).first { $0.fileName == fileName })
    }

    @Test func forgetsAMissingROMAndKeepsTheGame() throws {
        try h.journal.recordROM(game: game, fileName: "Road Rash.7z", missing: true)
        try h.journal.recordROM(game: game, fileName: "Road Rash (USA).7z", missing: false)

        try h.journal.forgetROM(try rom("Road Rash.7z").id)

        #expect(try h.journal.roms(of: game).map(\.fileName) == ["Road Rash (USA).7z"])
        #expect(try h.journal.game(game).name == "Road Rash")
    }

    @Test func refusesAPresentROM() throws {
        try h.journal.recordROM(game: game, fileName: "Road Rash (USA).7z", missing: false)

        #expect(throws: LudeumError.romIsPresent) { try h.journal.forgetROM(try rom("Road Rash (USA).7z").id) }
        #expect(try h.journal.roms(of: game).count == 1)
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
