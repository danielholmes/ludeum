import Foundation
import Testing

@testable import JournalCore

@Suite struct IntentTests {
    let h: JournalHarness
    let game: GameID

    init() throws {
        h = try JournalHarness()
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

    @Test func childhoodIsAFlag() throws {
        try h.journal.setChildhood(game, true)

        #expect(try h.journal.game(game).childhood)
    }
}

@Suite struct ListTests {
    let h: JournalHarness

    init() throws { h = try JournalHarness() }

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

        #expect(throws: JournalError.listNameTaken) { try h.journal.createList("Zelda") }
        #expect(throws: JournalError.listNameTaken) { try h.journal.renameList(other, "Zelda") }
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
