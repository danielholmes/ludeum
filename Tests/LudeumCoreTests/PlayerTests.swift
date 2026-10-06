import Testing

@testable import LudeumCore

@Suite struct PlayerTests {
    let h: LudeumHarness

    init() throws {
        h = try LudeumHarness()
    }

    @Test func keepsNamesAndColourByName() throws {
        let zoe = try h.journal.addPlayer(PlayerDraft(firstName: "Zoe", lastName: "Adams", colour: .teal))
        let alex = try h.journal.addPlayer(PlayerDraft(firstName: "Alex", lastName: "Smith", colour: .red))
        try h.reopen()

        #expect(
            try h.journal.players() == [
                Player(id: alex, PlayerDraft(firstName: "Alex", lastName: "Smith", colour: .red)),
                Player(id: zoe, PlayerDraft(firstName: "Zoe", lastName: "Adams", colour: .teal)),
            ])
    }

    @Test func initialsAreTheFirstLetterOfEachName() {
        #expect(PlayerDraft(firstName: "alex", lastName: "Smith", colour: .red).initials == "AS")
    }

    @Test func namesAreRequiredAndTheFullNameIsUnique() throws {
        try h.journal.addPlayer(PlayerDraft(firstName: "Alex", lastName: "Smith", colour: .red))

        #expect(throws: LudeumError.playerNameTaken) {
            try h.journal.addPlayer(PlayerDraft(firstName: "alex", lastName: " SMITH ", colour: .blue))
        }
        #expect(throws: LudeumError.nameRequired) {
            try h.journal.addPlayer(PlayerDraft(firstName: "Alex", lastName: " ", colour: .blue))
        }
        try h.journal.addPlayer(PlayerDraft(firstName: "Anna", lastName: "Smith", colour: .blue))
    }

    @Test func editsAPlayer() throws {
        let id = try h.journal.addPlayer(PlayerDraft(firstName: "Alex", lastName: "Smith", colour: .red))
        let taken = PlayerDraft(firstName: "Sam", lastName: "Jones", colour: .red)
        try h.journal.addPlayer(taken)

        try h.journal.updatePlayer(id, PlayerDraft(firstName: "Alexandra", lastName: "Smith", colour: .green))

        #expect(try h.journal.players().first == Player(id: id, PlayerDraft(firstName: "Alexandra", lastName: "Smith", colour: .green)))
        #expect(throws: LudeumError.playerNameTaken) { try h.journal.updatePlayer(id, taken) }
    }

    @Test func aNewPlayerSuggestsTheFirstUnusedColour() throws {
        #expect(try h.journal.nextPlayerColour() == .red)
        try h.journal.addPlayer(PlayerDraft(firstName: "Alex", lastName: "Smith", colour: .red))
        try h.journal.addPlayer(PlayerDraft(firstName: "Sam", lastName: "Jones", colour: .amber))

        #expect(try h.journal.nextPlayerColour() == .orange)
    }

    @Test func aPlaythroughKeepsItsPlayers() throws {
        let game = try h.addGame()
        let alex = try h.journal.addPlayer(PlayerDraft(firstName: "Alex", lastName: "Smith", colour: .red))
        let sam = try h.journal.addPlayer(PlayerDraft(firstName: "Sam", lastName: "Jones", colour: .blue))
        let id = try h.journal.addPlaythrough(game, PlaythroughDraft(start: PartialDate("2024")!, players: [sam, alex]))
        #expect(try h.journal.playthroughs(game).first?.draft.players == [alex, sam])

        try h.journal.updatePlaythrough(id, PlaythroughDraft(start: PartialDate("2024")!, players: [sam]))
        try h.reopen()

        #expect(try h.journal.playthroughs(game).first?.draft.players == [sam])
    }

    @Test func deletingAPlayerTakesThemOffTheirPlaythroughs() throws {
        let game = try h.addGame()
        let alex = try h.journal.addPlayer(PlayerDraft(firstName: "Alex", lastName: "Smith", colour: .red))
        let sam = try h.journal.addPlayer(PlayerDraft(firstName: "Sam", lastName: "Jones", colour: .blue))
        try h.journal.addPlaythrough(game, PlaythroughDraft(start: PartialDate("2024")!, players: [alex, sam]))
        try h.journal.addPlaythrough(game, PlaythroughDraft(start: PartialDate("2025")!, players: [alex]))
        #expect(try h.journal.playthroughCount(with: alex) == 2)

        try h.journal.deletePlayer(alex)

        #expect(try h.journal.players().map(\.id) == [sam])
        #expect(try h.journal.playthroughs(game).map(\.draft.players) == [[sam], []])
    }
}
