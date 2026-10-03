import Testing

@testable import JournalCore

@Suite struct GameTests {
    @Test func keepsAGameAcrossARelaunch() throws {
        let h = try JournalHarness()
        let id = try h.addGame("Super Metroid")
        try h.reopen()

        let game = try h.journal.game(id)

        #expect(game.name == "Super Metroid")
        #expect(game.platformId == 19)
        #expect(game.rating == nil)
        #expect(game.intent == nil)
        #expect(!game.childhood)
    }

    @Test func showsTheOverrideThenIGDBsNameThenItsOwnName() throws {
        let h = try JournalHarness()
        try h.journal.addPlatform(id: 19, name: "Super Nintendo Entertainment System")
        let linked = try h.journal.addGame(platformId: 19, name: "Super Metroid (Japan, USA)", igdbGameId: 1103, igdbName: "Super Metroid")
        #expect(try h.journal.game(linked).name == "Super Metroid")

        try h.journal.setNameOverride(linked, "Metroid 3")

        #expect(try h.journal.game(linked).name == "Metroid 3")
    }

    @Test func refusesASecondGameWithTheSameIGDBLinkOnOnePlatform() throws {
        let h = try JournalHarness()
        try h.journal.addPlatform(id: 19, name: "Super Nintendo Entertainment System")
        try h.journal.addPlatform(id: 5, name: "Wii")
        _ = try h.journal.addGame(platformId: 19, name: "Super Metroid", igdbGameId: 1103, igdbName: "Super Metroid")

        #expect(throws: JournalError.igdbLinkTaken) {
            try h.journal.addGame(platformId: 19, name: "Super Metroid", igdbGameId: 1103, igdbName: "Super Metroid")
        }
        _ = try h.journal.addGame(platformId: 5, name: "Super Metroid", igdbGameId: 1103, igdbName: "Super Metroid")
    }
}
