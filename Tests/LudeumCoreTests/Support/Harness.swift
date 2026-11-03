import Foundation

@testable import LudeumCore

/// Wires the real clients and a real on-disk cache to the fake internet.
/// Calling `reopen()` simulates quitting and relaunching the app.
final class Harness {
    let directory: URL
    let clock = TestClock()
    let internet: FakeInternet
    private(set) var cache: CacheStore
    private(set) var igdb: IGDBClient
    private(set) var hasheous: HasheousClient
    private(set) var launchBox: LaunchBoxGamesDB

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "journal tests (with spaces) \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        internet = FakeInternet(clock: clock)
        (cache, igdb, hasheous, launchBox) = try Self.make(directory, internet, clock)
    }

    func reopen() throws {
        (cache, igdb, hasheous, launchBox) = try Self.make(directory, internet, clock)
    }

    private static func make(_ dir: URL, _ internet: FakeInternet, _ clock: TestClock) throws
        -> (CacheStore, IGDBClient, HasheousClient, LaunchBoxGamesDB)
    {
        let cache = try CacheStore(directory: dir, clock: clock)
        let igdb = IGDBClient(
            credentials: IGDBCredentials(clientID: "client", clientSecret: "secret"),
            cache: cache, transport: internet, clock: clock
        )
        let hasheous = HasheousClient(cache: cache, transport: internet, clock: clock)
        return (cache, igdb, hasheous, LaunchBoxGamesDB(cache: cache, transport: internet))
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

extension Harness {
    /// A RetroAchievements client with the key the fake internet takes, on the current cache.
    var retroAchievements: RetroAchievementsClient {
        RetroAchievementsClient(key: "ra-key", cache: cache, transport: internet, clock: clock)
    }

    var wikidata: WikidataClient { WikidataClient(cache: cache, transport: internet, clock: clock) }

    /// RetroAchievements times for `journal`'s Games, with every source wired to the fake internet.
    func retroAchievementsTimes(_ journal: LudeumStore) -> RetroAchievementsTimes {
        RetroAchievementsTimes(journal: journal, retroAchievements: retroAchievements, hasheous: hasheous, igdb: igdb, wikidata: wikidata)
    }

    /// Covers with every source wired to the fake internet.
    func covers(_ journal: LudeumStore) -> Covers {
        Covers(journal: journal, igdb: igdb, launchBox: launchBox)
    }
}
