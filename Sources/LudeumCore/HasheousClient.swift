import Foundation

/// What Hasheous (hasheous.org) knows about a ROM checksum.
public enum HasheousResult: Sendable, Hashable {
    case match(HasheousMatch)
    case noMatch

    public var match: HasheousMatch? { if case .match(let m) = self { m } else { nil } }
}

/// A Hasheous record for a ROM, kept verbatim, with the IGDB ids pulled out.
public struct HasheousMatch: Sendable, Hashable {
    public let record: JSONValue

    public var igdbGameID: Int? { Self.igdbID(in: record["metadata"]) }
    public var igdbPlatformID: Int? { Self.igdbID(in: record["platform"]?["metadata"]) }

    /// The `immutableId` of the mapped IGDB entry (`id` can be a slug).
    private static func igdbID(in metadata: JSONValue?) -> Int? {
        metadata?.array?
            .first { $0["source"]?.string == "IGDB" && $0["status"]?.string == "Mapped" }?["immutableId"]?
            .string.flatMap(Int.init)
    }
}

public final class HasheousClient: Sendable {
    let cache: CacheStore
    let api: Throttle
    let maxAge: TimeInterval
    let apiKey: String?

    public init(
        cache: CacheStore, transport: HTTPTransport = URLSessionTransport(), clock: TimeSource = SystemTimeSource(),
        maxAge: TimeInterval = CacheStore.defaultMaxAge, apiKey: String? = nil
    ) {
        self.cache = cache
        self.maxAge = maxAge
        self.apiKey = apiKey
        api = Throttle(requestsPerSecond: 1, transport: transport, clock: clock)
    }

    /// Looks up a ROM by MD5. "Not found" is a successful answer and is cached like a match.
    public func lookup(md5: String) async throws -> HasheousResult {
        try await lookup(md5: md5, servesStale: true)
    }

    /// Looks up a ROM by CRC32, as an archive's index gives it, the way `lookup(md5:)` does by MD5.
    public func lookup(crc: String) async throws -> HasheousResult {
        try await lookup(crc: crc, servesStale: true)
    }

    func lookup(md5: String, servesStale: Bool) async throws -> HasheousResult {
        try await lookup("md5", md5, servesStale: servesStale)
    }

    func lookup(crc: String, servesStale: Bool) async throws -> HasheousResult {
        try await lookup("crc", crc, servesStale: servesStale)
    }

    /// `kind` is Hasheous's name for the hash, in its path and the cache key.
    private func lookup(_ kind: String, _ hash: String, servesStale: Bool) async throws -> HasheousResult {
        let hash = hash.lowercased()
        let key = { (hash: String) in "hasheous:\(kind):\(hash)" }
        let payloads = try await cache.resolve(
            [hash], key: key, maxAge: maxAge, batchSize: 1, servesStale: servesStale
        ) { _ in
            [hash: try await fetch(kind, hash)]
        }
        let record = try JSONValue.decode(payloads[hash]!)
        return record == .null ? .noMatch : .match(HasheousMatch(record: record))
    }

    private func fetch(_ kind: String, _ hash: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://hasheous.org/api/v1/Lookup/ByHash/\(kind)/\(hash)")!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "X-Client-API-Key") }
        let (data, response) = try await api.send(request)
        switch response.statusCode {
        case 200: return data
        case 404: return try JSONValue.null.encoded()
        default: throw HTTPStatusError(status: response.statusCode, url: request.url)
        }
    }
}
