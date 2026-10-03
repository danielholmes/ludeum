import Foundation
import Testing

@testable import JournalCore

@Suite struct IGDBPlatformsAndSearchTests {
    @Test func thePlatformsListIsFetchedOnceAndCached() async throws {
        let h = try Harness()
        h.internet.addPlatform(19, "Super Nintendo Entertainment System", abbreviation: "SNES")
        h.internet.addPlatform(6, "PC (Microsoft Windows)", abbreviation: "PC")

        let first = try await h.igdb.platforms()
        h.internet.resetSent()
        let second = try await h.igdb.platforms()

        #expect(first.map(\.name).sorted() == ["PC (Microsoft Windows)", "Super Nintendo Entertainment System"])
        #expect(second == first)
        #expect(h.internet.sent.isEmpty)
    }

    @Test func aSearchWithoutAPlatformSearchesEveryPlatform() async throws {
        let h = try Harness()
        h.internet.addSearch("Celeste", platform: nil, results: [1, 2])

        let search = IGDBSearch(name: "Celeste")
        #expect(try await h.igdb.search([search])[search] == [1, 2])
        #expect(!h.internet.sent(to: FakeInternet.Hosts.igdb).last!.body.contains("where platforms"))
    }
}

@Suite struct GameSearchTests {
    let h: Harness
    let j: JournalHarness
    let snes: [String: Any] = ["id": 19, "name": "SNES"]
    let wii: [String: Any] = ["id": 5, "name": "Wii"]

    init() throws {
        h = try Harness()
        j = try JournalHarness()
    }

    var search: GameSearch { GameSearch(igdb: h.igdb, journal: j.journal) }

    @Test func resultsCarryTheirPlatformsAsChipsAndLeaveOutAddOns() async throws {
        h.internet.addGame(
            1103, "Super Metroid", fields: ["platforms": [snes, wii], "first_release_date": 764_726_400, "cover": ["image_id": "co1"]])
        h.internet.addGame(2, "Super Metroid DLC", fields: ["game_type": 1, "platforms": [snes]])
        h.internet.addGame(3, "Super Metroid Redesign", fields: ["game_type": 5, "platforms": [snes]])
        h.internet.addSearch("super metroid", platform: nil, results: [1103, 2, 3])

        let results = try await search.search("super metroid")

        #expect(results.map(\.name) == ["Super Metroid", "Super Metroid Redesign"])
        #expect(results[0].year == 1994)
        #expect(results[0].gameType == nil)
        #expect(results[0].coverImageID == "co1")
        #expect(results[0].chips.map(\.platformName) == ["SNES", "Wii"])
        #expect(results[1].gameType == "Mod")
    }

    @Test func thePlatformFilterNarrowsTheSearch() async throws {
        h.internet.addGame(1103, "Super Metroid", fields: ["platforms": [snes]])
        h.internet.addSearch("super metroid", platform: 19, results: [1103])

        #expect(try await search.search("super metroid", platform: 19).map(\.igdbGameId) == [1103])
        #expect(try await search.search("super metroid", platform: 5).isEmpty)
    }

    @Test func addingFromAChipTakesIGDBsNameAndLink() async throws {
        h.internet.addGame(1103, "Super Metroid", fields: ["platforms": [snes]])
        h.internet.addSearch("metroid", platform: nil, results: [1103])
        let result = try #require(try await search.search("metroid").first)

        let id = try search.add(result, on: result.chips[0].platform)

        let game = try j.journal.game(id)
        #expect(game.name == "Super Metroid")
        #expect(game.igdbGameId == 1103)
        #expect(game.platformId == 19)
    }

    @Test func aChipAlreadyInTheJournalSaysSoAndAddingOpensThatGame() async throws {
        h.internet.addGame(1103, "Super Metroid", fields: ["platforms": [snes, wii]])
        h.internet.addSearch("metroid", platform: nil, results: [1103])
        let first = try #require(try await search.search("metroid").first)
        let id = try search.add(first, on: first.chips[0].platform)

        let again = try #require(try await search.search("metroid").first)

        #expect(again.chips.map(\.game) == [id, nil])
        #expect(try search.add(again, on: again.chips[0].platform) == id)
    }

    @Test func aDifferentPlatformRecordsTheLinkOnMyPlatform() async throws {
        h.internet.addGame(1103, "Super Metroid", fields: ["platforms": [snes]])
        h.internet.addSearch("metroid", platform: nil, results: [1103])
        let result = try #require(try await search.search("metroid").first)

        let id = try search.add(result, on: IGDBPlatform(id: 130, name: "Nintendo Switch"))

        #expect(try j.journal.game(id).platformId == 130)
        #expect(try await search.search("metroid").first?.chips.map(\.game) == [nil])
    }
}

@Suite struct AddingByHandTests {
    let j: JournalHarness
    init() throws {
        j = try JournalHarness()
        try j.journal.addPlatform(id: 19, name: "SNES")
        try j.journal.addPlatform(id: 5, name: "Wii")
    }

    @Test func aNameAndAPlatformAreRequired() throws {
        let id = try j.journal.addGameByHand(name: "  Hermano  ", platformId: 19)
        #expect(try j.journal.game(id).name == "Hermano")
        #expect(try j.journal.game(id).igdbGameId == nil)
        #expect(throws: JournalError.nameRequired) { try j.journal.addGameByHand(name: " ", platformId: 19) }
    }

    @Test func gamesOnTheSamePlatformWhoseNamesAgreeAreFlagged() throws {
        let linked = try j.journal.addGame(platformId: 19, name: "Lost Vikings, The (U)", igdbGameId: 9, igdbName: "The Lost Vikings")
        _ = try j.journal.addGame(platformId: 5, name: "Lost Vikings")

        #expect(try j.journal.gamesWhoseNamesAgree(with: "lost vikings", platformId: 19).map(\.id) == [linked])
        #expect(try j.journal.gamesWhoseNamesAgree(with: "Lost Vikings 2", platformId: 19).isEmpty)
    }

    @Test func myPlatformsComeFirstInThePicker() {
        let all = [
            IGDBPlatform(id: 6, name: "PC"), IGDBPlatform(id: 5, name: "Wii"), IGDBPlatform(id: 19, name: "SNES"),
            IGDBPlatform(id: 4, name: "N64"),
        ]

        #expect(platformPickerOrder(all, used: [19, 5], filter: "").map(\.id) == [19, 5, 4, 6])
        #expect(platformPickerOrder(all, used: [19, 5], filter: "n").map(\.id) == [19, 4])
    }
}

@Suite struct LinkingLaterTests {
    let j: JournalHarness
    init() throws {
        j = try JournalHarness()
        try j.journal.addPlatform(id: 19, name: "SNES")
    }

    @Test func aHandMadeGameGainsALinkAndFollowsIGDBsName() throws {
        let id = try j.journal.addGameByHand(name: "Metroid 3", platformId: 19)

        try j.journal.link(id, igdbGameId: 1103, igdbName: "Super Metroid")

        #expect(try j.journal.game(id).name == "Super Metroid")
        #expect(try j.journal.game(id).igdbGameId == 1103)
    }

    @Test func anOverriddenNameStays() throws {
        let id = try j.journal.addGameByHand(name: "Metroid 3", platformId: 19)
        try j.journal.setNameOverride(id, "My Metroid")

        try j.journal.link(id, igdbGameId: 1103, igdbName: "Super Metroid")

        #expect(try j.journal.game(id).name == "My Metroid")
    }

    @Test func aLinkHeldByAnotherGameIsRefused() throws {
        let holder = try j.journal.addGame(platformId: 19, name: "Super Metroid", igdbGameId: 1103, igdbName: "Super Metroid")
        let id = try j.journal.addGameByHand(name: "Metroid 3", platformId: 19)

        #expect(throws: JournalError.igdbLinkTaken) { try j.journal.link(id, igdbGameId: 1103, igdbName: "Super Metroid") }
        #expect(try j.journal.gameID(igdbGameId: 1103, platformId: 19) == holder)
    }

    @Test func anExistingLinkIsNeverChanged() throws {
        let id = try j.journal.addGame(platformId: 19, name: "Super Metroid", igdbGameId: 1103, igdbName: "Super Metroid")

        #expect(throws: JournalError.alreadyLinked) { try j.journal.link(id, igdbGameId: 9, igdbName: "Other") }
    }
}
