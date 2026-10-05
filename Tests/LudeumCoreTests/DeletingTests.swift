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
        try h.journal.recordROM(
            game: game, openEmuPk: 42, md5: "d41d8cd98f00b204e9800998ecf8427e",
            fileName: "Super Metroid (Japan, USA).sfc", systemId: "openemu.system.snes", missing: missing)
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
        try h.journal.recordROM(
            game: again, openEmuPk: 42, md5: "d41d8cd98f00b204e9800998ecf8427e",
            fileName: "Super Metroid (Japan, USA).sfc", systemId: "openemu.system.snes", missing: false)
    }
}
