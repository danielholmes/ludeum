import Testing

@testable import LudeumCore

@Suite struct ListTests {
    let j: LudeumHarness
    let snes: Int64 = 19
    let xbox: Int64 = 49

    init() throws {
        j = try LudeumHarness()
        try j.journal.addPlatform(id: snes, name: "SNES")
        try j.journal.addPlatform(id: xbox, name: "Xbox One")
    }

    @Test func listsAreKeptByNameWithHowManyGamesEachHas() throws {
        let zelda = try j.journal.addGame(platformId: snes, name: "A Link to the Past")
        let kirby = try j.journal.addGame(platformId: snes, name: "Kirby Super Star")
        let withJasmine = try j.journal.createList(named: "With Jasmine")
        let cosy = try j.journal.createList(named: "cosy")

        try j.journal.addGame(zelda, toList: withJasmine.id)
        try j.journal.addGame(kirby, toList: withJasmine.id)
        try j.reopen()

        #expect(
            try j.journal.lists() == [
                GameList(id: cosy.id, name: "cosy", games: 0),
                GameList(id: withJasmine.id, name: "With Jasmine", games: 2),
            ])
    }

    @Test func aListsNameIsTrimmedRequiredAndUniqueIgnoringCase() throws {
        let list = try j.journal.createList(named: "  Couch co-op  ")

        #expect(list.name == "Couch co-op")
        #expect(list.games == 0)
        #expect(throws: LudeumError.nameRequired) { try j.journal.createList(named: "   ") }
        #expect(throws: LudeumError.listNameTaken) { try j.journal.createList(named: "COUCH CO-OP") }
    }

    @Test func renamingAListKeepsItsGamesAndMovesItToItsNewPlaceByName() throws {
        let game = try j.journal.addGame(platformId: snes, name: "Super Metroid")
        let list = try j.journal.createList(named: "Zebra")
        _ = try j.journal.createList(named: "Middle")
        try j.journal.addGame(game, toList: list.id)

        try j.journal.renameList(list.id, to: "  Apple  ")

        #expect(try j.journal.lists().map(\.name) == ["Apple", "Middle"])
        #expect(try j.journal.lists(containing: game) == [GameList(id: list.id, name: "Apple", games: 1)])
    }

    @Test func aRenamedListsNameIsRequiredAndUniqueIgnoringCaseButCanChangeItsOwnCase() throws {
        let list = try j.journal.createList(named: "Couch co-op")
        _ = try j.journal.createList(named: "Cosy")

        #expect(throws: LudeumError.nameRequired) { try j.journal.renameList(list.id, to: "   ") }
        #expect(throws: LudeumError.listNameTaken) { try j.journal.renameList(list.id, to: "COSY") }
        #expect(try j.journal.lists().map(\.name) == ["Cosy", "Couch co-op"])

        try j.journal.renameList(list.id, to: "Couch Co-op")

        #expect(try j.journal.lists().map(\.name) == ["Cosy", "Couch Co-op"])
    }

    @Test func aGameOfAnyKindCanBeInAnyNumberOfListsOnceEach() throws {
        let owned = try j.journal.addGame(platformId: snes, name: "Super Metroid")
        let unowned = try j.journal.addGame(platformId: xbox, name: "Rayman Legends")
        let first = try j.journal.createList(named: "First")
        let second = try j.journal.createList(named: "Second")
        try j.journal.addCopy(owned, CopyDraft(kind: .physical))

        try j.journal.addGame(owned, toList: first.id)
        try j.journal.addGame(owned, toList: first.id)
        try j.journal.addGame(owned, toList: second.id)
        try j.journal.addGame(unowned, toList: first.id)

        #expect(try j.journal.lists(containing: owned).map(\.name) == ["First", "Second"])
        #expect(try j.journal.lists(containing: unowned).map(\.name) == ["First"])
        #expect(try j.journal.lists().map(\.games) == [2, 1])
    }

    @Test func removingAGameFromAListLeavesItsOtherListsAndTheGame() throws {
        let game = try j.journal.addGame(platformId: snes, name: "Super Metroid")
        let first = try j.journal.createList(named: "First")
        let second = try j.journal.createList(named: "Second")
        try j.journal.addGame(game, toList: first.id)
        try j.journal.addGame(game, toList: second.id)

        try j.journal.removeGame(game, fromList: first.id)

        #expect(try j.journal.lists(containing: game).map(\.name) == ["Second"])
        #expect(try j.journal.game(game).name == "Super Metroid")
    }

    /// A Bundle is not a Game and is never a Library row (ADR 0016), so a List could never show it.
    @Test func aBundleCantBeInAList() throws {
        let bundle = try j.journal.addBundle(platformId: snes, name: "Super Mario All-Stars")
        let list = try j.journal.createList(named: "First")

        #expect(throws: LudeumError.cantBeInList) { try j.journal.addGame(bundle, toList: list.id) }
        #expect(try j.journal.lists().map(\.games) == [0])
    }

    @Test func addingAGameThatsGoneSaysSo() throws {
        let list = try j.journal.createList(named: "First")

        #expect(throws: LudeumError.gameNotFound) { try j.journal.addGame(999, toList: list.id) }
    }

    @Test func deletingAListLeavesItsGames() throws {
        let game = try j.journal.addGame(platformId: snes, name: "Super Metroid")
        let doomed = try j.journal.createList(named: "Doomed")
        let kept = try j.journal.createList(named: "Kept")
        try j.journal.addGame(game, toList: doomed.id)
        try j.journal.addGame(game, toList: kept.id)

        try j.journal.deleteList(doomed.id)

        #expect(try j.journal.lists().map(\.name) == ["Kept"])
        #expect(try j.journal.lists(containing: game).map(\.name) == ["Kept"])
        #expect(try j.journal.game(game).name == "Super Metroid")
    }

    @Test func deletingAGameTakesItOutOfItsListsAndSaysHowMany() throws {
        let game = try j.journal.addGame(platformId: snes, name: "Super Metroid")
        let list = try j.journal.createList(named: "First")
        try j.journal.addGame(game, toList: list.id)

        #expect(try j.journal.deletionSummary(game).lists == 1)
        try j.journal.deleteGame(game)

        #expect(try j.journal.lists().map(\.games) == [0])
    }

    @Test func aListFiltersTheLibraryToItsGamesAlongsideOtherFilters() throws {
        let metroid = try j.journal.addGame(platformId: snes, name: "Super Metroid")
        let rayman = try j.journal.addGame(platformId: xbox, name: "Rayman Legends")
        _ = try j.journal.addGame(platformId: snes, name: "Not In The List")
        let list = try j.journal.createList(named: "First")
        try j.journal.addGame(metroid, toList: list.id)
        try j.journal.addGame(rayman, toList: list.id)

        func names(_ filter: LibraryFilter) throws -> [String] {
            try j.journal.library(filter, sort: .name, ascending: true).map(\.name)
        }
        #expect(try names(LibraryFilter(listId: list.id)) == ["Rayman Legends", "Super Metroid"])
        #expect(try names(LibraryFilter(platformId: snes, listId: list.id)) == ["Super Metroid"])
        // The Text filter narrows through the facts path, which the screen takes for a search.
        let searched = try j.journal.library(LibraryFilter(listId: list.id, name: "rayman"), sort: .name, ascending: true, facts: [:])
        #expect(searched.map(\.name) == ["Rayman Legends"])
    }

    @Test func aListsScopeWinsOverTheScreensOwnFilters() {
        let scoped = LibraryFilter(listId: 1).scoped(by: LibraryFilter(listId: 2))

        #expect(scoped.listId == 2)
    }
}
