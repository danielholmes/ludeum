import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// A Game's RetroAchievements time (ADR 0030): the set for its Platform, by its ROMs' checksums at Hasheous, else by its
/// IGDB link at Wikidata.
@Suite struct RetroAchievementsTests {
    let h: Harness
    let j: LudeumHarness

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        try j.journal.addPlatform(id: 19, name: "Super Nintendo Entertainment System")
        try j.journal.addPlatform(id: 29, name: "Sega Mega Drive/Genesis")
    }

    var times: RetroAchievementsTimes { h.retroAchievementsTimes(j.journal) }

    /// A Game on `platform`, linked to an IGDB game with `slug` when given.
    func game(_ name: String, platform: Int64 = 19, igdb: (id: Int, slug: String)? = nil) throws -> GameID {
        if let igdb { h.internet.addGame(igdb.id, name, fields: ["slug": igdb.slug]) }
        return try j.journal.addGame(
            platformId: platform, name: name, igdbGameId: igdb.map { Int64($0.id) }, igdbName: igdb.map { _ in name })
    }

    /// A ROM of `game` with checksum `md5`.
    func rom(of game: GameID, md5: String, named name: String) async throws {
        try j.journal.recordROM(game: game, fileName: "\(name).sfc", missing: true)
        try await j.journal.db.write { try $0.execute(sql: "UPDATE rom SET md5 = ? WHERE folderName = ?", arguments: [md5, name]) }
    }

    @Test func aROMsChecksumFindsItsSetAndItsMediansFromTheMostPlayers() async throws {
        let metroid = try game("Super Metroid")
        try await rom(of: metroid, md5: "aa", named: "Super Metroid (Japan, USA) (En)")
        h.internet.addHash(md5: "aa", game: 1, platform: 19, retroAchievements: 1446)
        h.internet.addSet(
            1446, console: 3, beat: (36_360, 2_558), beatHardcore: (30_240, 5_489), master: (63_000, 364), complete: (60_000, 20))

        #expect(try await times.time(of: metroid) == RetroAchievementsTime(beat: 30_240, master: 63_000))
    }

    @Test func aMedianFromFewerThanFivePlayersIsLeftOut() async throws {
        let populous = try game("Populous")
        try await rom(of: populous, md5: "aa", named: "Populous (USA)")
        h.internet.addHash(md5: "aa", game: 1, platform: 19, retroAchievements: 1104)
        h.internet.addSet(1104, console: 3, beat: (61_242, 1), beatHardcore: (47_574, 4), master: (53_569, 21))
        let tetris = try game("Tetris Attack")
        try await rom(of: tetris, md5: "bb", named: "Tetris Attack (USA)")
        h.internet.addHash(md5: "bb", game: 2, platform: 19, retroAchievements: 2000)
        h.internet.addSet(2000, console: 3, beat: (3_600, 2), master: (7_200, 4))

        #expect(try await times.time(of: populous) == RetroAchievementsTime(beat: nil, master: 53_569))
        #expect(try await times.time(of: tetris) == nil)
    }

    @Test func withNoROMWikidataGivesTheSetOnTheGamesPlatform() async throws {
        // Sonic 2 has a set on Mega Drive (1) and one on Game Gear (15); Wikidata lists both on one item.
        let sonic = try game("Sonic the Hedgehog 2", platform: 29, igdb: (1, "sonic-the-hedgehog-2"))
        h.internet.addWikidataSets(igdbSlug: "sonic-the-hedgehog-2", [6, 1_500])
        h.internet.addSet(6, console: 15, beat: (5_040, 180))
        h.internet.addSet(1_500, console: 1, beat: (18_720, 91), beatHardcore: (19_080, 438))

        #expect(try await times.time(of: sonic) == RetroAchievementsTime(beat: 19_080, master: nil))
    }

    @Test func hasheousWinsOverWikidataUnlessItsSetIsOnAnotherConsole() async throws {
        let metroid = try game("Super Metroid", igdb: (1, "super-metroid"))
        try await rom(of: metroid, md5: "aa", named: "Super Metroid (Japan, USA) (En)")
        h.internet.addHash(md5: "aa", game: 1, platform: 19, retroAchievements: 1446)
        h.internet.addSet(1446, console: 3, beat: (30_000, 50))
        h.internet.addWikidataSets(igdbSlug: "super-metroid", [9_999])
        h.internet.addSet(9_999, console: 3, beat: (99_000, 50))

        #expect(try await times.time(of: metroid)?.beat == 30_000)
        #expect(h.internet.sent(to: FakeInternet.Hosts.wikidata).isEmpty)

        // A checksum Hasheous ties to a set on another console (a mislabelled dump) is passed over.
        let zelda = try game("A Link to the Past", igdb: (2, "a-link-to-the-past"))
        try await rom(of: zelda, md5: "bb", named: "Legend of Zelda, The - A Link to the Past (USA)")
        h.internet.addHash(md5: "bb", game: 2, platform: 19, retroAchievements: 77)
        h.internet.addSet(77, console: 4, beat: (1_000, 50))
        h.internet.addWikidataSets(igdbSlug: "a-link-to-the-past", [355])
        h.internet.addSet(355, console: 3, beat: (40_000, 50))

        #expect(try await times.time(of: zelda)?.beat == 40_000)
    }

    @Test func noneForAPlatformWithoutSetsOrAGameNoSourceKnows() async throws {
        try j.journal.addPlatform(id: 49, name: "Xbox One")
        let halo = try game("Halo 5", platform: 49, igdb: (1, "halo-5-guardians"))
        let unknown = try game("Somebody's Homebrew", igdb: (2, "somebodys-homebrew"))
        try await rom(of: unknown, md5: "aa", named: "Somebody's Homebrew")

        #expect(try await times.time(of: halo) == nil)
        #expect(h.internet.sent.isEmpty)
        #expect(try await times.time(of: unknown) == nil)
        // An unknown set is an answer too, kept like any other.
        h.internet.addWikidataSets(igdbSlug: "somebodys-homebrew", [42])
        h.internet.resetSent()
        #expect(try await times.time(of: unknown) == nil)
        #expect(h.internet.sent(to: FakeInternet.Hosts.wikidata).isEmpty)
    }

    @Test func answersAreKeptAndAskedAgainOnlyAfter180Days() async throws {
        let sonic = try game("Sonic the Hedgehog 2", platform: 29, igdb: (1, "sonic-the-hedgehog-2"))
        h.internet.addWikidataSets(igdbSlug: "sonic-the-hedgehog-2", [1_500])
        h.internet.addSet(1_500, console: 1, beat: (18_720, 91))
        _ = try await times.time(of: sonic)
        h.internet.resetSent()

        #expect(try await times.time(of: sonic)?.beat == 18_720)
        #expect(h.internet.sent.isEmpty)

        h.internet.addSet(1_500, console: 1, beat: (20_000, 120))
        h.clock.advance(days: 61)
        let refresh = CacheRefresh(
            cache: h.cache, igdb: h.igdb, hasheous: h.hasheous, launchBox: nil, retroAchievements: h.retroAchievements,
            wikidata: h.wikidata, gate: WorkGate())
        _ = await refresh.run()
        #expect(h.internet.sent(to: FakeInternet.Hosts.retroAchievements).isEmpty)
        #expect(h.internet.sent(to: FakeInternet.Hosts.wikidata).isEmpty)

        h.clock.advance(days: 120)
        let result = await refresh.run()
        #expect(result.errors.isEmpty)
        #expect(h.internet.sent(to: FakeInternet.Hosts.retroAchievements).count == 1)
        #expect(h.internet.sent(to: FakeInternet.Hosts.wikidata).count == 1)
        h.internet.resetSent()
        #expect(try await times.time(of: sonic)?.beat == 20_000)
        #expect(h.internet.sent(to: FakeInternet.Hosts.retroAchievements).isEmpty)
    }

    @Test func aWrongKeyThrowsWithoutTheKeyInTheErrorAndKeepsNothing() async throws {
        let sonic = try game("Sonic the Hedgehog 2", platform: 29, igdb: (1, "sonic-the-hedgehog-2"))
        h.internet.addWikidataSets(igdbSlug: "sonic-the-hedgehog-2", [1_500])
        h.internet.addSet(1_500, console: 1, beat: (18_720, 91))
        h.internet.state.withLock { $0.retroAchievementsKey = "another-key" }

        let error = await #expect(throws: HTTPStatusError.self) { try await times.time(of: sonic) }
        #expect(error?.status == 401)
        #expect(!(error?.description.contains("ra-key") ?? true))

        h.internet.state.withLock { $0.retroAchievementsKey = "ra-key" }
        #expect(try await times.time(of: sonic)?.beat == 18_720)
    }

    @Test func hasheousGivesItsMappedRetroAchievementsSet() async throws {
        h.internet.addHash(md5: "aa", game: 1, platform: 19, retroAchievements: 1446)
        h.internet.addHash(md5: "bb", game: 2, platform: 19)

        #expect(try await h.hasheous.lookup(md5: "aa").match?.retroAchievementsGameID == 1446)
        #expect(try await h.hasheous.lookup(md5: "bb").match?.retroAchievementsGameID == nil)
    }
}
