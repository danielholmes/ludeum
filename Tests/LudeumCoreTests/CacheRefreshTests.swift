import Foundation
import Testing

@testable import LudeumCore

@Suite struct CacheRefreshTests {
    let h = try! Harness()

    private func refresh(gate: WorkGate = WorkGate()) -> CacheRefresh {
        CacheRefresh(cache: h.cache, igdb: h.igdb, hasheous: h.hasheous, launchBox: nil, gate: gate)
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
        #expect(result.launchBoxWarning == nil)
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
        #expect(gate.beginImport())

        let refresh = refresh(gate: gate)
        let running = Task { await refresh.run() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(h.internet.sent.isEmpty)

        gate.endImport()
        #expect(await running.value.refreshed == 1)
    }

    @Test func readsLaunchBoxsDumpWhenThereIsNoneOrItsOlderThan30Days() async throws {
        h.internet.setLaunchBox([LaunchBoxGame(id: 1, name: "Half-Life", platform: "Windows", boxes: [(nil, "hl.jpg")])])
        let refresh = CacheRefresh(cache: h.cache, igdb: h.igdb, hasheous: h.hasheous, launchBox: h.launchBox, gate: WorkGate())

        #expect(await refresh.run().refreshed == 1)
        #expect(try h.launchBox.boxart(platform: 6, titles: ["Half-Life"], regions: [], year: nil) == "hl.jpg")

        h.clock.advance(days: 29)
        h.internet.resetSent()
        #expect(await refresh.run().refreshed == 0)
        #expect(h.internet.sent.isEmpty)

        h.clock.advance(days: 2)
        #expect(await refresh.run().refreshed == 1)
        #expect(h.internet.sent(to: FakeInternet.Hosts.launchBox).count == 1)
    }

    @Test func aLaunchBoxDumpThatCantBeDownloadedOrReadIsAWarningSayingWhatShowsMeanwhile() async throws {
        let refresh = CacheRefresh(cache: h.cache, igdb: h.igdb, hasheous: h.hasheous, launchBox: h.launchBox, gate: WorkGate())
        h.internet.setDown(FakeInternet.Hosts.launchBox, true)

        let first = try #require(await refresh.run().launchBoxWarning)

        #expect(first.title == "LaunchBox's games database couldn't be updated")
        #expect(first.message.hasPrefix("LaunchBox's Metadata.zip couldn't be downloaded: HTTP 503.\n\n"))
        #expect(first.message.contains("Until one is read"))

        h.internet.setDown(FakeInternet.Hosts.launchBox, false)
        h.internet.setLaunchBox([LaunchBoxGame(id: 1, name: "Half-Life", platform: "Windows", boxes: [(nil, "hl.jpg")])])
        h.clock.advance(days: 1)
        #expect(await refresh.run().launchBoxWarning == nil)
        h.internet.state.withLock { $0.launchBoxDump = Data("not a zip".utf8) }
        h.clock.advance(days: 31)

        let second = try #require(await refresh.run().launchBoxWarning)

        #expect(second.message.contains("couldn't be read"))
        #expect(!second.message.contains(".."))
        let readOn = h.clock.now().addingTimeInterval(-31 * 86_400).formatted(date: .long, time: .omitted)
        #expect(second.message.contains("keeps using the one read on \(readOn)."))
    }
}

@Suite struct WorkGateTests {
    @Test func oneImportRunsAtATime() {
        let gate = WorkGate()

        #expect(gate.beginImport())
        #expect(!gate.beginImport())
        #expect(gate.isImporting)

        gate.endImport()
        #expect(!gate.isImporting)
        #expect(gate.beginImport())
    }

    @Test func endingWorkThatIsntRunningChangesNothing() {
        let gate = WorkGate()

        gate.endImport()

        #expect(!gate.isImporting)
    }

    @Test func aCancelledWaiterStopsWaiting() async {
        let gate = WorkGate()
        #expect(gate.beginImport())

        let waiting = Task { await gate.waitUntilClear() }
        waiting.cancel()
        await waiting.value

        #expect(gate.isImporting)
    }
}
