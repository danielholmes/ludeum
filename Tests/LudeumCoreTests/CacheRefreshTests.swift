import Foundation
import Testing

@testable import LudeumCore

@Suite struct CacheRefreshTests {
    let h = try! Harness()

    private func refresh(gate: WorkGate = WorkGate()) -> CacheRefresh {
        CacheRefresh(cache: h.cache, igdb: h.igdb, hasheous: h.hasheous, gate: gate)
    }

    @Test func refetchesOnlyExpiredEntries() async throws {
        h.internet.addGame(1, "Old")
        h.internet.addGame(2, "Recent")
        _ = try await h.igdb.games(ids: [1])
        h.clock.advance(days: 50)
        _ = try await h.igdb.games(ids: [2])
        h.clock.advance(days: 15)
        h.internet.addGame(1, "Old, renamed")
        h.internet.resetSent()

        let result = await refresh().run()

        #expect(h.internet.requestedGameIDBatches == [[1]])
        #expect(result.refreshed == 1)
        #expect(result.errors.isEmpty)
        #expect(try await h.igdb.games(ids: [1])[1]?.name == "Old, renamed")
    }

    @Test func refreshesEveryKindOfEntry() async throws {
        h.internet.addGame(1, "Super Metroid")
        h.internet.addSearch("super metroid", platform: 19, results: [1])
        h.internet.addPlatform(19, "SNES")
        h.internet.addHash(md5: "AA", game: 1, platform: 19)
        _ = try await h.igdb.games(ids: [1])
        _ = try await h.igdb.search([IGDBSearch(name: "Super  Metroid", platformID: 19)])
        _ = try await h.igdb.platforms()
        _ = try await h.hasheous.lookup(md5: "aa")
        _ = try await h.hasheous.lookup(md5: "bb")
        h.clock.advance(days: 61)
        h.internet.resetSent()

        let result = await refresh().run()

        #expect(result.refreshed == 5)
        #expect(result.errors.isEmpty)
        #expect(h.internet.sent(to: FakeInternet.Hosts.hasheous).count == 2)
        // Games, search, platforms (the token is still valid).
        #expect(h.internet.sent(to: FakeInternet.Hosts.igdb).count == 3)
        h.internet.resetSent()
        _ = try await h.igdb.search([IGDBSearch(name: "super metroid", platformID: 19)])
        #expect(h.internet.sent.isEmpty)
    }

    @Test func refreshesFilteredSearchesGenresThemesAndCompanies() async throws {
        h.internet.addGame(1, "Rise of the Triad", fields: ["involved_companies": [["company": ["id": 70]]], "themes": [["id": 19]]])
        h.internet.addGenre(8, "Platform")
        h.internet.addTheme(19, "Horror")
        h.internet.addCompany(70, "Apogee")
        let filtered = IGDBSearch(name: "", genreIDs: [], themeIDs: [19], companyID: 70)
        _ = try await h.igdb.search([filtered])
        _ = try await h.igdb.genres()
        _ = try await h.igdb.themes()
        _ = try await h.igdb.companies(matching: "apogee")
        h.clock.advance(days: 61)
        h.internet.resetSent()

        let result = await refresh().run()

        #expect(result.errors.isEmpty)
        #expect(result.refreshed == 4)
        h.internet.resetSent()
        #expect(try await h.igdb.search([filtered])[filtered] == [1])
        #expect(h.internet.sent.isEmpty)
    }

    @Test func aFailedRefreshKeepsTheOldEntryAndCarriesOn() async throws {
        h.internet.addGame(1, "Super Metroid")
        h.internet.addHash(md5: "aa", game: 1, platform: 19)
        _ = try await h.igdb.games(ids: [1])
        _ = try await h.hasheous.lookup(md5: "aa")
        h.clock.advance(days: 61)
        h.internet.setDown(FakeInternet.Hosts.igdb, true)

        let result = await refresh().run()

        #expect(result.refreshed == 1)
        #expect(result.errors.count == 1)
        // Still served from the expired copy, and still expired, so the next launch tries again.
        #expect(try await h.igdb.games(ids: [1])[1]?.name == "Super Metroid")
        h.internet.setDown(FakeInternet.Hosts.igdb, false)
        h.internet.resetSent()
        #expect(await refresh().run().refreshed == 1)
        #expect(h.internet.requestedGameIDBatches == [[1]])
    }

    @Test func nothingExpiredSendsNothing() async throws {
        h.internet.addGame(1, "Super Metroid")
        _ = try await h.igdb.games(ids: [1])
        h.internet.resetSent()

        let result = await refresh().run()

        #expect(result.refreshed == 0)
        #expect(h.internet.sent.isEmpty)
    }

    @Test func waitsWhileAnImportOrSyncRuns() async throws {
        h.internet.addHash(md5: "aa", game: 1, platform: 19)
        _ = try await h.hasheous.lookup(md5: "aa")
        h.clock.advance(days: 61)
        h.internet.resetSent()
        let gate = WorkGate()
        #expect(gate.begin(.importing))

        let refresh = refresh(gate: gate)
        let running = Task { await refresh.run() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(h.internet.sent.isEmpty)

        gate.end(.importing)
        #expect(await running.value.refreshed == 1)
    }
}

@Suite struct WorkGateTests {
    @Test func oneImportRunsAtATime() {
        let gate = WorkGate()

        #expect(gate.begin(.importing))
        #expect(!gate.begin(.importing))
        #expect(gate.current == .importing)

        gate.end(.importing)
        #expect(gate.current == nil)
        #expect(gate.begin(.importing))
    }

    @Test func endingWorkThatIsntRunningChangesNothing() {
        let gate = WorkGate()

        gate.end(.importing)

        #expect(gate.current == nil)
    }

    @Test func aCancelledWaiterStopsWaiting() async {
        let gate = WorkGate()
        #expect(gate.begin(.importing))

        let waiting = Task { await gate.waitUntilClear() }
        waiting.cancel()
        await waiting.value

        #expect(gate.current == .importing)
    }
}
