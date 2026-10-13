import Foundation
import Testing

@testable import LudeumCore

@Suite struct ExpansionSearchTests {
    let h: Harness
    let j: LudeumHarness
    let pc: [String: Any] = ["id": 6, "name": "PC"]

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        h.internet.addGame(1, "Diablo II", fields: ["platforms": [pc]])
        h.internet.addGame(
            2, "Diablo II: Lord of Destruction",
            fields: ["game_type": 2, "platforms": [pc], "parent_game": ["id": 1, "name": "Diablo II"]])
        h.internet.addGame(
            3, "Diablo II Soundtrack", fields: ["game_type": 1, "platforms": [pc], "parent_game": ["id": 1, "name": "Diablo II"]])
        h.internet.addGame(
            4, "Diablo II: Blood Dragon", fields: ["game_type": 4, "platforms": [pc], "parent_game": ["id": 1, "name": "Diablo II"]])
        h.internet.addGame(5, "Diablo II: Mystery", fields: ["game_type": 2, "platforms": [pc]])
        h.internet.addSearch("diablo ii", platform: nil, results: [1, 2, 3, 4, 5])
    }

    var search: GameSearch { GameSearch(igdb: h.igdb, journal: j.journal) }

    @Test func baseGamesLeaveOutExpansionsButKeepStandaloneExpansions() async throws {
        let results = try await search.search("diablo ii")

        #expect(results.map(\.igdbGameId) == [1, 4])
        #expect(h.internet.sent(to: FakeInternet.Hosts.igdb).contains { $0.body.contains("game_type != (1,2,7,13,14)") })
    }

    @Test func expansionsAreOnlyExpansionsAndStandaloneExpansionsSayingWhatTheyExpand() async throws {
        let results = try await search.search("diablo ii", expansions: true)

        #expect(results.map(\.igdbGameId) == [2, 4, 5])
        #expect(results.map(\.baseGameName) == ["Diablo II", "Diablo II", nil])
        #expect(h.internet.sent(to: FakeInternet.Hosts.igdb).contains { $0.body.contains("game_type = (2,4)") })
    }

    @Test func aBaseGameIsNoExpansion() async throws {
        let base = try await search.search("diablo ii")[0]

        #expect(base.baseGameName == nil)
    }

    @Test func anExpansionsSearchIsCachedApartAndRefreshesAsItself() {
        let base = IGDBSearch(name: "diablo", platformID: 6)
        let expansions = IGDBSearch(name: "diablo", platformID: 6, expansions: true)

        #expect(base.cacheKey != expansions.cacheKey)
        #expect(IGDBSearch(cacheKey: expansions.cacheKey) == expansions)
        #expect(IGDBSearch(cacheKey: base.cacheKey) == base)
        let filtered = IGDBSearch(name: "", themeIDs: [19], companyID: 70, expansions: true)
        #expect(IGDBSearch(cacheKey: filtered.cacheKey) == filtered)
    }
}

@Suite struct ExpansionDetailTests {
    let h: Harness
    let j: LudeumHarness

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        try j.journal.addPlatform(id: 6, name: "PC")
        try j.journal.addPlatform(id: 14, name: "Mac")
        h.internet.addGame(
            1, "Diablo II",
            fields: [
                "expansions": [["id": 2, "name": "Diablo II: Lord of Destruction"], ["id": 5, "name": "Diablo II: Mystery"]],
                "standalone_expansions": [["id": 4, "name": "Diablo II: Blood Dragon"]],
            ])
        h.internet.addGame(2, "Diablo II: Lord of Destruction", fields: ["game_type": 2, "parent_game": ["id": 1, "name": "Diablo II"]])
        h.internet.addGame(4, "Diablo II: Blood Dragon", fields: ["game_type": 4, "parent_game": ["id": 1, "name": "Diablo II"]])
        h.internet.addGame(5, "Diablo II: Mystery", fields: ["game_type": 2])
        h.internet.addGame(6, "Diablo II Soundtrack", fields: ["game_type": 1, "parent_game": ["id": 1, "name": "Diablo II"]])
    }

    func facts(_ id: Int64) async throws -> GameFacts { try await h.igdb.facts(igdbGameId: id) }

    @Test func anExpansionsFactsNameItsBaseGame() async throws {
        #expect(try await facts(2).expansion == ExpansionOf(baseGame: IGDBNamed(id: 1, name: "Diablo II")))
        #expect(try await facts(4).expansion == ExpansionOf(baseGame: IGDBNamed(id: 1, name: "Diablo II")))
        #expect(try await facts(5).expansion == ExpansionOf(baseGame: nil))
        #expect(try await facts(1).expansion == nil)
        #expect(try await facts(6).expansion == nil)
        #expect(try await facts(1).expansionIDs == [2, 5, 4])
    }

    @Test func theBaseGameIsMyGameOnTheSamePlatformByMyName() async throws {
        let base = try j.journal.addGame(platformId: 6, name: "Diablo II", igdbGameId: 1, igdbName: "Diablo II")
        try j.journal.setNameOverride(base, "Diablo 2")
        let expansion = try j.journal.addGame(platformId: 6, name: "LoD", igdbGameId: 2, igdbName: "Diablo II: Lord of Destruction")

        let line = try j.journal.baseGame(of: try j.journal.game(expansion), facts: try await facts(2))

        #expect(line == BaseGameLine(name: "Diablo 2", game: base))
    }

    @Test func aBaseGameOnlyOnAnotherPlatformIsIGDBsNameUnlinked() async throws {
        _ = try j.journal.addGame(platformId: 14, name: "Diablo II", igdbGameId: 1, igdbName: "Diablo II")
        let expansion = try j.journal.addGame(platformId: 6, name: "LoD", igdbGameId: 2, igdbName: "Diablo II: Lord of Destruction")

        let line = try j.journal.baseGame(of: try j.journal.game(expansion), facts: try await facts(2))

        #expect(line == BaseGameLine(name: "Diablo II", game: nil))
    }

    @Test func anExpansionIGDBGivesNoBaseGameSaysOnlyThatItIsOne() async throws {
        let expansion = try j.journal.addGame(platformId: 6, name: "Mystery", igdbGameId: 5, igdbName: "Diablo II: Mystery")

        #expect(try j.journal.baseGame(of: try j.journal.game(expansion), facts: try await facts(5)) == BaseGameLine(name: nil, game: nil))
    }

    @Test func aGameThatIsNoExpansionHasNoBaseGame() async throws {
        let base = try j.journal.addGame(platformId: 6, name: "Diablo II", igdbGameId: 1, igdbName: "Diablo II")

        #expect(try j.journal.baseGame(of: try j.journal.game(base), facts: try await facts(1)) == nil)
    }

    @Test func aBaseGameListsItsExpansionsInTheJournalOnTheSamePlatform() async throws {
        let base = try j.journal.addGame(platformId: 6, name: "Diablo II", igdbGameId: 1, igdbName: "Diablo II")
        let lod = try j.journal.addGame(platformId: 6, name: "Diablo II: Lord of Destruction", igdbGameId: 2)
        let blood = try j.journal.addGame(platformId: 6, name: "Diablo II: Blood Dragon", igdbGameId: 4)
        _ = try j.journal.addGame(platformId: 14, name: "Diablo II: Mystery", igdbGameId: 5)

        let expansions = try j.journal.expansions(of: try j.journal.game(base), facts: try await facts(1))

        #expect(expansions.map(\.id) == [blood, lod])
    }
}
