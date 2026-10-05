import Foundation
import Testing

@testable import JournalCore

@Suite struct IGDBClientTests {
    @Test func fetchesTheFullGameRecord() async throws {
        let h = try Harness()
        h.internet.addGame(1070, "Super Mario World")

        let games = try await h.igdb.games(ids: [1070])

        #expect(games[1070]?.name == "Super Mario World")
        #expect(games[1070]?.record["screenshots"]?[0]?["image_id"]?.string == "sc1070")
    }

    @Test func servesARepeatRequestFromTheCacheWithoutTouchingTheNetwork() async throws {
        let h = try Harness()
        h.internet.addGame(1070, "Super Mario World")
        _ = try await h.igdb.games(ids: [1070])
        h.internet.resetSent()

        let games = try await h.igdb.games(ids: [1070])

        #expect(games[1070]?.name == "Super Mario World")
        #expect(h.internet.sent.isEmpty)
    }

    @Test func keepsCachedGamesAcrossAppRestarts() async throws {
        let h = try Harness()
        h.internet.addGame(1070, "Super Mario World")
        _ = try await h.igdb.games(ids: [1070])
        try h.reopen()
        h.internet.resetSent()

        let games = try await h.igdb.games(ids: [1070])

        #expect(games[1070]?.name == "Super Mario World")
        #expect(h.internet.sent.isEmpty)
    }

    @Test func includesTimeToBeatInTheGameRecord() async throws {
        let h = try Harness()
        h.internet.addGame(1070, "Super Mario World", normallySeconds: 36_000)

        let games = try await h.igdb.games(ids: [1070])

        #expect(games[1070]?.timeToBeat?["normally"]?.int == 36_000)
    }

    @Test func requestsOnlyTheGamesThatAreNotAlreadyCached() async throws {
        let h = try Harness()
        h.internet.addGame(1070, "Super Mario World")
        h.internet.addGame(1071, "Super Mario Kart")
        _ = try await h.igdb.games(ids: [1070])
        h.internet.resetSent()

        let games = try await h.igdb.games(ids: [1070, 1071])

        #expect(games.keys.sorted() == [1070, 1071])
        #expect(h.internet.requestedGameIDBatches == [[1071]])
    }

    @Test func splitsLargeRequestsIntoBatchesOfAtMost100() async throws {
        let h = try Harness()
        let ids = Array(1...250)
        for id in ids { h.internet.addGame(id, "Game \(id)") }

        let games = try await h.igdb.games(ids: ids)

        #expect(games.count == 250)
        #expect(h.internet.requestedGameIDBatches.map(\.count) == [100, 100, 50])
    }

    @Test func halvesABatchThatIGDBRejectsAsTooLarge() async throws {
        let h = try Harness()
        let ids = Array(1...100)
        for id in ids { h.internet.addGame(id, "Game \(id)") }
        h.internet.state.withLock { $0.maxGamesPerResponse = 30 }

        let games = try await h.igdb.games(ids: ids)

        #expect(games.count == 100)
    }

    @Test func searchReturnsMatchingGameIDsInIGDBsOrder() async throws {
        let h = try Harness()
        h.internet.addSearch("Super Mario World", platform: 19, results: [1070, 5_000, 42])

        let results = try await h.igdb.search([IGDBSearch(name: "Super Mario World", platformID: 19)])

        #expect(results[IGDBSearch(name: "Super Mario World", platformID: 19)] == [1070, 5_000, 42])
    }

    @Test func cachesSearchResults() async throws {
        let h = try Harness()
        h.internet.addSearch("Super Mario World", platform: 19, results: [1070])
        let searches = [IGDBSearch(name: "Super Mario World", platformID: 19), IGDBSearch(name: "Unknown", platformID: 19)]
        _ = try await h.igdb.search(searches)
        h.internet.resetSent()

        let again = try await h.igdb.search(searches)

        #expect(again[searches[0]] == [1070])
        #expect(again[searches[1]] == [])
        #expect(h.internet.sent.isEmpty)
    }

    @Test func keepsUsingACachedGameForUpTo60Days() async throws {
        let h = try Harness()
        h.internet.addGame(1070, "Super Mario World")
        _ = try await h.igdb.games(ids: [1070])
        h.internet.addGame(1070, "Super Mario World (renamed)")
        h.clock.advance(days: 59)

        let games = try await h.igdb.games(ids: [1070])

        #expect(games[1070]?.name == "Super Mario World")
    }

    @Test func refetchesAGameOnceItsCacheEntryIsOlderThan60Days() async throws {
        let h = try Harness()
        h.internet.addGame(1070, "Super Mario World")
        _ = try await h.igdb.games(ids: [1070])
        h.internet.addGame(1070, "Super Mario World (renamed)")
        h.clock.advance(days: 61)

        let games = try await h.igdb.games(ids: [1070])

        #expect(games[1070]?.name == "Super Mario World (renamed)")
    }

    @Test func fallsBackToAnExpiredCopyWhenRefetchingFails() async throws {
        let h = try Harness()
        h.internet.addGame(1070, "Super Mario World")
        _ = try await h.igdb.games(ids: [1070])
        h.clock.advance(days: 61)
        h.internet.setDown(FakeInternet.Hosts.igdb, true)

        let games = try await h.igdb.games(ids: [1070])

        #expect(games[1070]?.name == "Super Mario World")
    }

    @Test func doesNotCacheAFailedRequest() async throws {
        let h = try Harness()
        h.internet.addGame(1070, "Super Mario World")
        h.internet.setDown(FakeInternet.Hosts.igdb, true)
        await #expect(throws: HTTPStatusError.self) { try await h.igdb.games(ids: [1070]) }

        h.internet.setDown(FakeInternet.Hosts.igdb, false)
        let games = try await h.igdb.games(ids: [1070])

        #expect(games[1070]?.name == "Super Mario World")
    }
}

@Suite struct SearchFallbackTests {
    @Test func aGameIGDBsSearchMissesIsFoundByNameOrAlternativeName() async throws {
        let h = try Harness()
        h.internet.addGame(1360, "Einhänder", fields: ["alternative_names": [["name": "Einhander"]]])
        let searches = [IGDBSearch(name: "Einhänder"), IGDBSearch(name: "einhander")]

        let results = try await h.igdb.search(searches)

        #expect(results[searches[0]] == [1360])
        #expect(results[searches[1]] == [1360])
    }

    @Test func theFallbackRunsOnlyWhenTheSearchFindsNothing() async throws {
        let h = try Harness()
        h.internet.addGame(1103, "Super Metroid")
        h.internet.addSearch("Super Metroid", platform: nil, results: [1103])

        _ = try await h.igdb.search([IGDBSearch(name: "Super Metroid")])

        #expect(h.internet.sent(to: FakeInternet.Hosts.igdb).filter { $0.body.contains("alternative_names") }.isEmpty)
    }
}
