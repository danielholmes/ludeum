import Foundation
import Testing

@testable import JournalCore

@Suite struct CacheRefreshTests {
    let h = try! Harness()

    private func refresh(gate: WorkGate = WorkGate(), covers: Covers? = nil) -> CacheRefresh {
        CacheRefresh(cache: h.cache, igdb: h.igdb, hasheous: h.hasheous, gate: gate, covers: covers)
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

    @Test func aRefreshThatBringsACoverRemovesTheJournalsOwn() async throws {
        let j = try JournalHarness()
        let covers = Covers(journal: j.journal, igdb: h.igdb)
        h.internet.addGame(1103, "Super Metroid")
        try j.journal.addPlatform(id: 19, name: "SNES")
        let game = try j.journal.addGameByHand(name: "Super Metroid", platformId: 19)
        try j.journal.link(game, igdbGameId: 1103, igdbName: "Super Metroid")
        try await covers.upload(testImage(width: 10, height: 10), for: game)
        h.clock.advance(days: 61)
        h.internet.addGame(1103, "Super Metroid", fields: ["cover": ["image_id": "co1"]])

        _ = await refresh(covers: covers).run()

        #expect(try j.journal.journalCover(game) == nil)
    }
}

@Suite struct WorkGateTests {
    @Test func importAndSyncAreExclusive() {
        let gate = WorkGate()

        #expect(gate.begin(.importing))
        #expect(!gate.begin(.syncing))
        #expect(!gate.begin(.importing))
        #expect(gate.current == .importing)

        gate.end(.importing)
        #expect(gate.begin(.syncing))
        #expect(gate.current == .syncing)
    }

    @Test func endingWorkThatIsntRunningChangesNothing() {
        let gate = WorkGate()
        #expect(gate.begin(.syncing))

        gate.end(.importing)

        #expect(gate.current == .syncing)
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
