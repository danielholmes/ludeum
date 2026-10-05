import Foundation

@testable import JournalCore

/// Wires the real clients and a real on-disk cache to the fake internet.
/// Calling `reopen()` simulates quitting and relaunching the app.
final class Harness {
    let directory: URL
    let clock = TestClock()
    let internet: FakeInternet
    private(set) var cache: CacheStore
    private(set) var igdb: IGDBClient
    private(set) var hasheous: HasheousClient
    private(set) var libretro: LibretroThumbnails

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "journal tests (with spaces) \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        internet = FakeInternet(clock: clock)
        (cache, igdb, hasheous, libretro) = try Self.make(directory, internet, clock)
    }

    func reopen() throws {
        (cache, igdb, hasheous, libretro) = try Self.make(directory, internet, clock)
    }

    private static func make(_ dir: URL, _ internet: FakeInternet, _ clock: TestClock) throws
        -> (CacheStore, IGDBClient, HasheousClient, LibretroThumbnails)
    {
        let cache = try CacheStore(directory: dir, clock: clock)
        let igdb = IGDBClient(
            credentials: IGDBCredentials(clientID: "client", clientSecret: "secret"),
            cache: cache, transport: internet, clock: clock
        )
        let hasheous = HasheousClient(cache: cache, transport: internet, clock: clock)
        return (cache, igdb, hasheous, LibretroThumbnails(cache: cache, transport: internet, clock: clock))
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

extension Harness {
    /// Covers with every source wired to the fake internet.
    func covers(_ journal: JournalStore) -> Covers { Covers(journal: journal, cache: cache, igdb: igdb, libretro: libretro) }
}
