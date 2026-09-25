import Foundation
import GRDB

/// The local cache of external data (`cache.sqlite` plus downloaded images).
/// Throwaway: deleting it only costs re-fetching.
public final class CacheStore: Sendable {
    struct Entry: Sendable {
        let payload: Data
        let fetchedAt: Date
    }

    /// How long a cached entry stays fresh unless a client says otherwise.
    public static let defaultMaxAge: TimeInterval = 60 * 86_400

    let db: DatabaseQueue
    let directory: URL
    let clock: TimeSource

    public init(directory: URL, clock: TimeSource = SystemTimeSource()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
        self.clock = clock
        db = try DatabaseQueue(path: directory.appending(path: "cache.sqlite").path(percentEncoded: false))
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "entry") { t in
                t.primaryKey("key", .text)
                t.column("payload", .blob).notNull()
                t.column("fetched_at", .double).notNull()
            }
        }
        try migrator.migrate(db)
    }

    /// Payloads for `items`, served from the cache where fresh (younger than `maxAge`),
    /// otherwise fetched in batches via `fetch`. Each batch is stored as soon as it arrives,
    /// so an interrupted run resumes where it stopped. If a batch fails and every item in
    /// it has an expired copy, those copies are served instead. Items `fetch` doesn't
    /// return are absent from the result and not cached.
    func resolve<Item: Hashable>(
        _ items: [Item], key: (Item) -> String, maxAge: TimeInterval, batchSize: Int,
        fetch: ([Item]) async throws -> [Item: Data]
    ) async throws -> [Item: Data] {
        let unique = Array(Set(items))
        let cached = try entries(unique.map(key))
        let now = clock.now()
        var result: [Item: Data] = [:]
        var stale: [Item: Data] = [:]
        for item in unique {
            guard let entry = cached[key(item)] else { continue }
            if now.timeIntervalSince(entry.fetchedAt) <= maxAge { result[item] = entry.payload } else { stale[item] = entry.payload }
        }
        for batch in unique.filter({ result[$0] == nil }).chunked(batchSize) {
            do {
                let fetched = try await fetch(batch)
                try store(Dictionary(uniqueKeysWithValues: fetched.map { (key($0.key), $0.value) }))
                result.merge(fetched) { _, new in new }
            } catch {
                guard batch.allSatisfy({ stale[$0] != nil }) else { throw error }
                for item in batch { result[item] = stale[item] }
            }
        }
        return result
    }

    func entries(_ keys: [String]) throws -> [String: Entry] {
        try db.read { db in
            var out: [String: Entry] = [:]
            for chunk in keys.chunked(900) {
                let rows = try Row.fetchAll(
                    db, sql: "SELECT key, payload, fetched_at FROM entry WHERE key IN (\(chunk.map { _ in "?" }.joined(separator: ",")))",
                    arguments: StatementArguments(chunk))
                for row in rows {
                    out[row["key"]] = Entry(payload: row["payload"], fetchedAt: Date(timeIntervalSince1970: row["fetched_at"]))
                }
            }
            return out
        }
    }

    func store(_ payloads: [String: Data]) throws {
        let fetchedAt = clock.now().timeIntervalSince1970
        try db.write { db in
            for (key, payload) in payloads {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO entry (key, payload, fetched_at) VALUES (?, ?, ?)",
                    arguments: [key, payload, fetchedAt])
            }
        }
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

extension CacheStore {
    /// A cached image file at `path` (relative to the cache's images folder),
    /// downloaded with `download` the first time. Images never expire.
    func image(at path: String, download: () async throws -> Data) async throws -> URL {
        let file = directory.appending(path: "images").appending(path: path)
        if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) { return file }
        let data = try await download()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        return file
    }
}
