import Foundation
import Testing

@testable import LudeumCore

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
        let body = h.internet.sent(to: FakeInternet.Hosts.igdb).last!.body
        #expect(!body.contains("platforms ="))
        #expect(body.contains("game_type != (1,2,7,13,14)"))
    }
}

@Suite struct GameSearchTests {
    let h: Harness
    let j: LudeumHarness
    let snes: [String: Any] = ["id": 19, "name": "SNES"]
    let wii: [String: Any] = ["id": 5, "name": "Wii"]

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
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

    @Test func searchesByCompanyGenreAndThemeWithNoName() async throws {
        let apogee = ["company": ["id": 70]]
        h.internet.addGame(1, "Rise of the Triad", fields: ["involved_companies": [apogee], "themes": [["id": 19]]])
        h.internet.addGame(2, "Duke Nukem", fields: ["involved_companies": [apogee], "themes": [["id": 1]]])
        h.internet.addGame(3, "Doom", fields: ["themes": [["id": 19]]])
        let horror = IGDBNamed(id: 19, name: "Horror")

        let byApogee = try await search.search("", filters: GameSearchFilters(company: IGDBNamed(id: 70, name: "Apogee")))
        let horrorByApogee = try await search.search(
            "", filters: GameSearchFilters(themes: [horror], company: IGDBNamed(id: 70, name: "Apogee")))

        #expect(byApogee.map(\.igdbGameId) == [1, 2])
        #expect(horrorByApogee.map(\.igdbGameId) == [1])
    }

    @Test func severalGenresMatchAGameWithAnyOfThem() async throws {
        h.internet.addGame(1, "Super Metroid", fields: ["genres": [["id": 8]]])
        h.internet.addGame(2, "Final Fantasy", fields: ["genres": [["id": 12]]])
        h.internet.addGame(3, "Tetris", fields: ["genres": [["id": 9]]])

        let results = try await search.search(
            "", filters: GameSearchFilters(genres: [IGDBNamed(id: 8, name: "Platform"), IGDBNamed(id: 12, name: "RPG")]))

        #expect(results.map(\.igdbGameId) == [1, 2])
    }

    @Test func aSearchWithNoNameAndNoFiltersFindsNothing() async throws {
        h.internet.addGame(1, "Super Metroid")

        #expect(try await search.search("  ").isEmpty)
        #expect(h.internet.sent.isEmpty)
    }

    @Test func offersCompaniesThatMadeSomethingByName() async throws {
        h.internet.addCompany(70, "Apogee Software")
        h.internet.addCompany(71, "Apogee Entertainment")
        h.internet.addCompany(72, "Apogee Holdings", developed: false)

        #expect(try await search.companies(matching: "  APOGEE ").map(\.name) == ["Apogee Software", "Apogee Entertainment"])
    }

    @Test func listsGenresAndThemes() async throws {
        h.internet.addGenre(8, "Platform")
        h.internet.addTheme(19, "Horror")

        #expect(try await search.genres() == [IGDBNamed(id: 8, name: "Platform")])
        #expect(try await search.themes() == [IGDBNamed(id: 19, name: "Horror")])
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

    @Test func resultsSortByNameOrByReleaseDateWithUndatedLast() async throws {
        h.internet.addGame(1, "Metroid II", fields: ["first_release_date": 690_000_000])
        h.internet.addGame(2, "Metroid", fields: ["first_release_date": 520_000_000])
        h.internet.addGame(3, "metroid fan game", fields: [:])
        h.internet.addGame(4, "Metroid Fusion", fields: ["first_release_date": 1_037_000_000])
        h.internet.addSearch("metroid", platform: nil, results: [1, 2, 3, 4])
        let results = try await search.search("metroid")

        #expect(
            GameSearchSort.name.sorted(results, ascending: true).map(\.name) == [
                "Metroid", "metroid fan game", "Metroid Fusion", "Metroid II",
            ])
        #expect(GameSearchSort.releaseDate.sorted(results, ascending: false).map(\.igdbGameId) == [4, 1, 2, 3])
        #expect(GameSearchSort.releaseDate.sorted(results, ascending: true).map(\.igdbGameId) == [2, 1, 4, 3])
        #expect(GameSearchSort.name.defaultAscending)
        #expect(!GameSearchSort.releaseDate.defaultAscending)
    }

    @Test func chipsAreReadAgainFromTheLibraryIncludingADifferentPlatform() async throws {
        h.internet.addGame(1103, "Super Metroid", fields: ["platforms": [snes, wii]])
        h.internet.addSearch("metroid", platform: nil, results: [1103])
        let result = try #require(try await search.search("metroid").first)
        let snesGame = try search.add(result, on: result.chips[0].platform)
        let pc = IGDBPlatform(id: 6, name: "PC (Microsoft Windows)", abbreviation: "PC")
        let pcGame = try search.add(result, on: pc)

        let chips = try search.currentChips(for: result)

        #expect(chips.map(\.platform.id) == [19, 5, 6])
        #expect(chips.map(\.game) == [snesGame, nil, pcGame])
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
    let j: LudeumHarness
    init() throws {
        j = try LudeumHarness()
        try j.journal.addPlatform(id: 19, name: "SNES")
        try j.journal.addPlatform(id: 5, name: "Wii")
    }

    @Test func aNameAndAPlatformAreRequired() throws {
        let id = try j.journal.addGameByHand(name: "  Hermano  ", platformId: 19)
        #expect(try j.journal.game(id).name == "Hermano")
        #expect(try j.journal.game(id).igdbGameId == nil)
        #expect(throws: LudeumError.nameRequired) { try j.journal.addGameByHand(name: " ", platformId: 19) }
    }

    @Test func gamesOnTheSamePlatformWhoseNamesAgreeAreFlagged() throws {
        let linked = try j.journal.addGame(platformId: 19, name: "Lost Vikings, The (U)", igdbGameId: 9, igdbName: "The Lost Vikings")
        _ = try j.journal.addGame(platformId: 5, name: "Lost Vikings")

        #expect(try j.journal.gamesWhoseNamesAgree(with: "lost vikings", platformId: 19).map(\.id) == [linked])
        #expect(try j.journal.gamesWhoseNamesAgree(with: "Lost Vikings 2", platformId: 19).isEmpty)
        #expect(try j.journal.gamesWhoseNamesAgree(with: "Lost Vikings, The (U) [!]", platformId: 19).map(\.id) == [linked])
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
    let j: LudeumHarness
    init() throws {
        j = try LudeumHarness()
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

        #expect(throws: LudeumError.igdbLinkTaken) { try j.journal.link(id, igdbGameId: 1103, igdbName: "Super Metroid") }
        #expect(try j.journal.gameID(igdbGameId: 1103, platformId: 19) == holder)
    }

    @Test func anExistingLinkIsNeverChanged() throws {
        let id = try j.journal.addGame(platformId: 19, name: "Super Metroid", igdbGameId: 1103, igdbName: "Super Metroid")

        #expect(throws: LudeumError.alreadyLinked) { try j.journal.link(id, igdbGameId: 9, igdbName: "Other") }
    }
}

@Suite struct ChangingALinkTests {
    @Test func aMistakenLinkCanBeChangedButNotToOneAnotherGameHolds() throws {
        let j = try LudeumHarness()
        try j.journal.addPlatform(id: 7, name: "PlayStation")
        let game = try j.journal.addGame(platformId: 7, name: "Einhander", igdbGameId: 1, igdbName: "Wrong Game")
        try j.journal.addGame(platformId: 7, name: "Taken", igdbGameId: 2, igdbName: "Taken")

        #expect(throws: LudeumError.alreadyLinked) { try j.journal.link(game, igdbGameId: 1360, igdbName: "Einhänder") }
        try j.journal.link(game, igdbGameId: 1360, igdbName: "Einhänder", replacing: true)
        #expect(try j.journal.game(game).igdbGameId == 1360)
        #expect(try j.journal.game(game).name == "Einhänder")
        #expect(throws: LudeumError.igdbLinkTaken) { try j.journal.link(game, igdbGameId: 2, igdbName: "Taken", replacing: true) }
    }
}

@Suite struct ChangingPlatformTests {
    @Test func aGameWithoutROMsCanMovePlatformWithItsNewLinkButOneWithROMsCant() throws {
        let j = try LudeumHarness()
        try j.journal.addPlatform(id: 6, name: "PC")
        let pc = try j.journal.addGame(platformId: 6, name: "Doom", igdbGameId: 1, igdbName: "Doom")

        try j.journal.link(pc, igdbGameId: 2, igdbName: "Doom", replacing: true, platform: IGDBPlatform(id: 13, name: "DOS"))

        #expect(try j.journal.game(pc).platformId == 13)
        try j.journal.db.write { db in
            try db.execute(
                sql:
                    "INSERT INTO rom (folderName, fileName, platformId, gameId, matchKind, matchedAt) VALUES ('doom', 'doom.zip', 13, ?, 'manual', 0)",
                arguments: [pc])
        }
        #expect(throws: LudeumError.gameHasROMs) {
            try j.journal.link(pc, igdbGameId: 3, igdbName: "Doom", replacing: true, platform: IGDBPlatform(id: 6, name: "PC"))
        }
    }
}
