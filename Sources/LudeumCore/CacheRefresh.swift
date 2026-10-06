import Foundation

/// What a background refresh did. Errors are for the log, not alerts.
public struct CacheRefreshResult: Sendable {
    public var refreshed = 0
    public var errors: [String] = []
}

/// The low-priority refresh at launch: re-fetches every expired cache entry, one request (or IGDB
/// batch) at a time, waiting whenever an Import holds the rate limiters. An entry that
/// fails to refresh keeps its expired copy and is tried again next launch.
public struct CacheRefresh: Sendable {
    let cache: CacheStore
    let igdb: IGDBClient?
    let hasheous: HasheousClient
    let gate: WorkGate

    public init(cache: CacheStore, igdb: IGDBClient?, hasheous: HasheousClient, gate: WorkGate) {
        self.cache = cache
        self.igdb = igdb
        self.hasheous = hasheous
        self.gate = gate
    }

    /// `progress` gets (done, total) after each step. Stops early, without error, when cancelled.
    public func run(progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async -> CacheRefreshResult {
        var result = CacheRefreshResult()
        let keys: [String]
        do {
            keys = try cache.expiredKeys(maxAge: CacheStore.defaultMaxAge)
        } catch {
            result.errors.append("Reading the cache: \(error.localizedDescription)")
            return result
        }
        var steps: [(count: Int, label: String, refresh: @Sendable () async throws -> Void)] = []
        var gameIDs: [Int] = []
        for key in keys {
            let parts = key.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            switch (parts.first, parts.count > 1 ? parts[1] : nil) {
            case ("igdb", "game") where parts.count == 3:
                if let id = Int(parts[2]) { gameIDs.append(id) }
            case ("igdb", "search") where parts.count == 4:
                guard let igdb, let search = IGDBSearch(cacheKey: key) else { continue }
                steps.append((1, key, { _ = try await igdb.search([search], servesStale: false) }))
            case ("igdb", "genres"), ("igdb", "themes"):
                guard let igdb else { continue }
                let endpoint = parts[1]
                steps.append((1, key, { _ = try await igdb.named(endpoint, servesStale: false) }))
            case ("igdb", "companies") where parts.count == 3:
                guard let igdb else { continue }
                steps.append((1, key, { _ = try await igdb.companies(matching: parts[2], servesStale: false) }))
            case ("igdb", "platforms"):
                guard let igdb else { continue }
                steps.append((1, key, { _ = try await igdb.platforms(servesStale: false) }))
            case ("hasheous", "md5") where parts.count == 3:
                let hasheous = hasheous
                steps.append((1, key, { _ = try await hasheous.lookup(md5: parts[2], servesStale: false) }))
            case ("hasheous", "crc") where parts.count == 3:
                let hasheous = hasheous
                steps.append((1, key, { _ = try await hasheous.lookup(crc: parts[2], servesStale: false) }))
            default:
                continue  // e.g. the CLI's Twitch token, which manages its own expiry
            }
        }
        if let igdb {
            for batch in gameIDs.chunked(IGDBClient.maxBatch) {
                steps.append(
                    (
                        batch.count, "IGDB games \(batch.first!)…",
                        { _ = try await igdb.games(ids: batch, servesStale: false) }
                    ))
            }
        }
        let total = steps.reduce(0) { $0 + $1.count }
        var done = 0
        progress(0, total)
        for step in steps {
            await gate.waitUntilClear()
            if Task.isCancelled { break }
            do {
                try await step.refresh()
                result.refreshed += step.count
            } catch is CancellationError {
                break
            } catch {
                result.errors.append("\(step.label): \(error.localizedDescription)")
            }
            done += step.count
            progress(done, total)
        }
        return result
    }
}
