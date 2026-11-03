import Foundation

/// Wikidata (query.wikidata.org, CC0): the ids other databases give an IGDB game, found by its IGDB slug (P5794, which is
/// the slug, not the numeric id). No key. Answers, none included, are kept as long as RetroAchievements' are.
public final class WikidataClient: Sendable {
    let cache: CacheStore
    let api: Throttle

    public init(cache: CacheStore, transport: HTTPTransport = URLSessionTransport(), clock: TimeSource = SystemTimeSource()) {
        self.cache = cache
        api = Throttle(requestsPerSecond: 1, transport: transport, clock: clock)
    }

    /// The RetroAchievements set ids (P11393) of the item whose IGDB slug this is: one per console it has a set on,
    /// lowest first. Empty when Wikidata has none.
    public func retroAchievementsIDs(igdbSlug: String) async throws -> [Int] {
        try await retroAchievementsIDs(igdbSlug: igdbSlug, servesStale: true)
    }

    func retroAchievementsIDs(igdbSlug slug: String, servesStale: Bool) async throws -> [Int] {
        let payloads = try await cache.resolve(
            [slug], key: Self.retroAchievementsKey, maxAge: RetroAchievementsClient.maxAge, batchSize: 1, servesStale: servesStale
        ) { _ in
            let literal = slug.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let rows = try await select("SELECT ?id WHERE { ?item wdt:P5794 \"\(literal)\" ; wdt:P11393 ?id . }")
            let ids = Set(rows.compactMap { $0["id"]?["value"]?.string.flatMap { Int($0) } }).sorted()
            return [slug: try JSONEncoder().encode(ids)]
        }
        return try JSONDecoder().decode([Int].self, from: payloads[slug] ?? Data("[]".utf8))
    }

    static func retroAchievementsKey(_ slug: String) -> String { "wikidata:retroachievements:\(slug)" }

    /// A SPARQL query's result rows.
    private func select(_ query: String) async throws -> [JSONValue] {
        var components = URLComponents(string: "https://query.wikidata.org/sparql")!
        components.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "format", value: "json")]
        var request = URLRequest(url: components.url!)
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        // Wikimedia asks every client to say who it is.
        request.setValue("Ludeum/1.0 (personal game journal)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await api.send(request)
        guard response.statusCode == 200 else { throw HTTPStatusError(status: response.statusCode, url: request.url) }
        return try JSONValue.decode(data)["results"]?["bindings"]?.array ?? []
    }
}
