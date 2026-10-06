import Foundation
import Synchronization

public struct IGDBCredentials: Sendable, Equatable {
    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}

/// A search for games: by name, filters, or both, on one IGDB platform or on every platform.
/// Several genres or themes match a game with any of them; a company matches any involvement
/// (developer, publisher, porting or supporting).
public struct IGDBSearch: Sendable, Hashable {
    public let name: String
    public let platformID: Int?
    public let genreIDs: [Int]
    public let themeIDs: [Int]
    public let companyID: Int?

    public init(name: String, platformID: Int? = nil, genreIDs: [Int] = [], themeIDs: [Int] = [], companyID: Int? = nil) {
        self.name = name
        self.platformID = platformID
        self.genreIDs = Array(Set(genreIDs)).sorted()
        self.themeIDs = Array(Set(themeIDs)).sorted()
        self.companyID = companyID
    }

    /// `igdb:search:<platform>:<name>`, with any filters after the platform: `any|g12,31|t19|c70`.
    var cacheKey: String {
        let normalised = name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var scope = platformID.map(String.init) ?? "any"
        if !genreIDs.isEmpty { scope += "|g" + genreIDs.map(String.init).joined(separator: ",") }
        if !themeIDs.isEmpty { scope += "|t" + themeIDs.map(String.init).joined(separator: ",") }
        if let companyID { scope += "|c\(companyID)" }
        return "igdb:search:\(scope):\(normalised)"
    }

    /// The search a `cacheKey` was made from.
    init?(cacheKey: String) {
        let parts = cacheKey.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "igdb", parts[1] == "search" else { return nil }
        let scope = parts[2].split(separator: "|")
        guard let platform = scope.first else { return nil }
        func ids(_ tag: Character) -> [Int] {
            scope.dropFirst().first { $0.first == tag }.map { $0.dropFirst().split(separator: ",").compactMap { Int($0) } } ?? []
        }
        self.init(
            name: String(parts[3]), platformID: Int(platform), genreIDs: ids("g"), themeIDs: ids("t"), companyID: ids("c").first)
    }

    /// The `where` conditions besides the name: add-ons left out, then the platform and filters.
    var conditions: String {
        var c = ["game_type != (1,2,7,13,14)"]
        if let platformID { c.append("platforms = (\(platformID))") }
        if !genreIDs.isEmpty { c.append("genres = (\(genreIDs.map(String.init).joined(separator: ",")))") }
        if !themeIDs.isEmpty { c.append("themes = (\(themeIDs.map(String.init).joined(separator: ",")))") }
        if let companyID { c.append("involved_companies.company = (\(companyID))") }
        return c.joined(separator: " & ")
    }
}

/// An IGDB genre, theme or company: just what's needed to choose one as a search filter.
public struct IGDBNamed: Sendable, Hashable, Codable, Identifiable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// A full IGDB game record, kept verbatim, with its time-to-beat merged in.
public struct IGDBGame: Sendable, Hashable {
    public let id: Int
    public let record: JSONValue
    public var name: String? { record["name"]?.string }
    public var timeToBeat: JSONValue? { record["time_to_beat"] }
}

public final class IGDBClient: Sendable {
    let credentials: IGDBCredentials
    let cache: CacheStore
    let transport: HTTPTransport
    let clock: TimeSource
    let maxAge: TimeInterval
    let api: Throttle
    let tokenStore: (any SecretStore)?
    /// Each game's Cover art image id (nil for none) as its cached record last gave it.
    private let coverImageIDs = Mutex<[Int: String?]>([:])

    /// With a `tokenStore` (the app's Keychain), the Twitch token is kept there; otherwise in the cache.
    public init(
        credentials: IGDBCredentials, cache: CacheStore,
        transport: HTTPTransport = URLSessionTransport(), clock: TimeSource = SystemTimeSource(),
        maxAge: TimeInterval = CacheStore.defaultMaxAge, tokenStore: (any SecretStore)? = nil
    ) {
        self.credentials = credentials
        self.cache = cache
        self.transport = transport
        self.clock = clock
        self.maxAge = maxAge
        self.tokenStore = tokenStore
        api = Throttle(requestsPerSecond: 3, transport: transport, clock: clock)
    }

    /// Full records for the given IGDB game ids. Ids IGDB doesn't know are absent.
    public func games(ids: [Int]) async throws -> [Int: IGDBGame] {
        try await games(ids: ids, servesStale: true)
    }

    /// Full records, each from the cache if it's there at all, however old, and fetched only if it isn't. For what a
    /// screen is waiting on (a Cover, the Library's facts, Game detail), which shouldn't wait on IGDB for a record it
    /// has: the launch refresh fetches expired ones again.
    public func cachedGames(ids: [Int]) async throws -> [Int: IGDBGame] {
        try await games(ids: ids, servesStale: true, usesExpired: true)
    }

    func games(ids: [Int], servesStale: Bool, usesExpired: Bool = false) async throws -> [Int: IGDBGame] {
        let payloads = try await cache.resolve(
            ids, key: Self.gameKey, maxAge: maxAge, batchSize: Self.maxBatch, servesStale: servesStale, usesExpired: usesExpired
        ) { batch in
            let fetched = try await fetchGames(ids: batch).mapValues { try $0.record.encoded() }
            // Their Cover art may have changed.
            coverImageIDs.withLock { known in for id in batch { known[id] = nil } }
            return fetched
        }
        return try payloads.reduce(into: [:]) { $0[$1.key] = IGDBGame(id: $1.key, record: try JSONValue.decode($1.value)) }
    }

    /// The image id of a game's Cover art, from its cached record, however old. It's remembered until the record is
    /// fetched again, so showing a Cover reads its whole record once, not every time.
    public func coverImageID(game id: Int) async throws -> String? {
        if let known = coverImageIDs.withLock({ $0[id] }) { return known }
        let imageID = try await cachedGames(ids: [id])[id]?.record["cover"]?["image_id"]?.string
        coverImageIDs.withLock { $0[id] = .some(imageID) }
        return imageID
    }

    /// IGDB game ids matching each name search on its platform, best match first.
    /// One request per search: IGDB's multiquery endpoint silently ignores `search`.
    public func search(_ searches: [IGDBSearch]) async throws -> [IGDBSearch: [Int]] {
        try await search(searches, servesStale: true)
    }

    func search(_ searches: [IGDBSearch], servesStale: Bool) async throws -> [IGDBSearch: [Int]] {
        let payloads = try await cache.resolve(
            searches, key: \.cacheKey, maxAge: maxAge, batchSize: 1, servesStale: servesStale
        ) { batch in
            let s = batch[0]
            // With no name there's no relevance order, so the most-rated games come first.
            let body =
                s.name.isEmpty
                ? "fields id; where \(s.conditions); sort total_rating_count desc; limit 100;"
                : """
                search "\(s.name.replacingOccurrences(of: "\"", with: "\\\""))"; \
                fields id; where \(s.conditions); limit 20;
                """
            let ids = (try JSONValue.decode(try await post("games", body)).array ?? []).compactMap { $0["id"]?.int }
            return [s: try JSONEncoder().encode(ids)]
        }
        var results = try payloads.mapValues { try JSONDecoder().decode([Int].self, from: $0) }
        // IGDB's search index misses some games entirely (Einhänder isn't found even as "Einh"), so a
        // search with no results falls back to matching the name, an alternative name or the slug.
        let empty = searches.filter { !$0.name.isEmpty && results[$0]?.isEmpty ?? false }
        if !empty.isEmpty {
            let fallbackKey: (IGDBSearch) -> String = { "igdb:search-fallback:" + $0.cacheKey.dropFirst("igdb:search:".count) }
            let fallback = try await cache.resolve(
                empty, key: fallbackKey, maxAge: maxAge, batchSize: 1,
                servesStale: servesStale
            ) { batch in
                let s = batch[0]
                let text = s.name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
                let slug = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
                    .split { !($0.isLetter || $0.isNumber) }.joined(separator: "-")
                let body = """
                    fields id; where (name ~ *"\(text)"* | alternative_names.name ~ *"\(text)"* | slug = "\(slug)") \
                    & \(s.conditions); limit 20;
                    """
                let ids = (try JSONValue.decode(try await post("games", body)).array ?? []).compactMap { $0["id"]?.int }
                return [s: try JSONEncoder().encode(ids)]
            }
            for (s, data) in fallback { results[s] = try JSONDecoder().decode([Int].self, from: data) }
        }
        return results
    }

    /// Every IGDB platform: the journal's Platforms. Cached as one entry, like any other record.
    public func platforms() async throws -> [IGDBPlatform] {
        try await platforms(servesStale: true)
    }

    func platforms(servesStale: Bool) async throws -> [IGDBPlatform] {
        let payloads = try await cache.resolve(
            ["all"], key: Self.platformsKey, maxAge: maxAge, batchSize: 1, servesStale: servesStale
        ) { _ in
            var all: [IGDBPlatform] = []
            while true {
                let body = "fields id, name, abbreviation; sort id asc; limit 500; offset \(all.count);"
                let page = (try JSONValue.decode(try await post("platforms", body)).array ?? []).compactMap { p -> IGDBPlatform? in
                    guard let id = p["id"]?.int, let name = p["name"]?.string else { return nil }
                    return IGDBPlatform(id: Int64(id), name: name, abbreviation: p["abbreviation"]?.string)
                }
                all += page
                if page.count < 500 { break }
            }
            return ["all": try JSONEncoder().encode(all)]
        }
        return try JSONDecoder().decode([IGDBPlatform].self, from: payloads["all"] ?? Data("[]".utf8))
    }

    /// Every IGDB genre, by name. Cached as one entry.
    public func genres() async throws -> [IGDBNamed] { try await named("genres", servesStale: true) }

    /// Every IGDB theme, by name. Cached as one entry.
    public func themes() async throws -> [IGDBNamed] { try await named("themes", servesStale: true) }

    func named(_ endpoint: String, servesStale: Bool) async throws -> [IGDBNamed] {
        let payloads = try await cache.resolve(
            [endpoint], key: Self.namedKey, maxAge: maxAge, batchSize: 1, servesStale: servesStale
        ) { _ in
            let body = "fields id, name; sort name asc; limit 500;"
            return [endpoint: try JSONEncoder().encode(Self.named(try await post(endpoint, body)))]
        }
        return try JSONDecoder().decode([IGDBNamed].self, from: payloads[endpoint] ?? Data("[]".utf8))
    }

    /// Companies whose name contains `text`, that developed or published something, by name.
    /// IGDB's `search` doesn't work on companies, so this matches the name instead.
    public func companies(matching text: String) async throws -> [IGDBNamed] {
        try await companies(matching: text, servesStale: true)
    }

    func companies(matching text: String, servesStale: Bool) async throws -> [IGDBNamed] {
        let text = text.lowercased().replacingOccurrences(of: "\"", with: "").split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !text.isEmpty else { return [] }
        let payloads = try await cache.resolve(
            [text], key: Self.companiesKey, maxAge: maxAge, batchSize: 1, servesStale: servesStale
        ) { _ in
            let body = """
                fields id, name; where name ~ *"\(text)"* & (developed != null | published != null); sort name asc; limit 50;
                """
            return [text: try JSONEncoder().encode(Self.named(try await post("companies", body)))]
        }
        return try JSONDecoder().decode([IGDBNamed].self, from: payloads[text] ?? Data("[]".utf8))
    }

    private static func named(_ data: Data) throws -> [IGDBNamed] {
        (try JSONValue.decode(data).array ?? []).compactMap { r in
            guard let id = r["id"]?.int, let name = r["name"]?.string else { return nil }
            return IGDBNamed(id: id, name: name)
        }
    }

    /// A local file holding the cover image, downloaded once.
    public func cover(imageID: String) async throws -> URL {
        try await image(imageID: imageID, size: "cover_big_2x")
    }

    /// Any IGDB image (cover, screenshot, artwork) at one of IGDB's named sizes.
    func image(imageID: String, size: String) async throws -> URL {
        try await cache.image(at: "igdb/\(size)/\(imageID).jpg") {
            let url = URL(string: "https://images.igdb.com/igdb/image/upload/t_\(size)/\(imageID).jpg")!
            let (data, response) = try await transport.send(URLRequest(url: url))
            guard response.statusCode == 200 else { throw HTTPStatusError(status: response.statusCode, url: url) }
            return data
        }
    }

    static func gameKey(_ id: Int) -> String { "igdb:game:\(id)" }
    static func platformsKey(_: String) -> String { "igdb:platforms:all" }
    static func namedKey(_ endpoint: String) -> String { "igdb:\(endpoint):all" }
    static func companiesKey(_ text: String) -> String { "igdb:companies:\(text)" }
    /// Fully expanded records are large: IGDB answers 413 for ~250 at once but is fine with 100.
    static let maxBatch = 100

    /// Fetches a batch, halving it whenever IGDB says the response would be too large (413).
    private func fetchGames(ids: [Int]) async throws -> [Int: IGDBGame] {
        do {
            return try await fetchGameBatch(ids: ids)
        } catch let error as HTTPStatusError where error.status == 413 && ids.count > 1 {
            let half = ids.count / 2
            let first = try await fetchGames(ids: Array(ids[..<half]))
            return first.merging(try await fetchGames(ids: Array(ids[half...]))) { a, _ in a }
        }
    }

    private func fetchGameBatch(ids: [Int]) async throws -> [Int: IGDBGame] {
        let idList = ids.map(String.init).joined(separator: ",")
        let body = """
            query games "games" { fields \(Self.gameFields); where id = (\(idList)); limit 500; };
            query game_time_to_beats "ttb" { fields *; where game_id = (\(idList)); limit 500; };
            """
        let results = try await multiquery(body)
        var ttb: [Int: JSONValue] = [:]
        for t in results["ttb"] ?? [] { if let g = t["game_id"]?.int { ttb[g] = t } }
        var games: [Int: IGDBGame] = [:]
        for g in results["games"] ?? [] {
            guard case .object(var o) = g, let id = g["id"]?.int else { continue }
            o["time_to_beat"] = ttb[id] ?? .null
            games[id] = IGDBGame(id: id, record: .object(o))
        }
        return games
    }

    // MARK: - HTTP

    /// Runs up to 10 named queries in one request. Doesn't support `search`.
    private func multiquery(_ body: String) async throws -> [String: [JSONValue]] {
        var out: [String: [JSONValue]] = [:]
        for entry in try JSONValue.decode(try await post("multiquery", body)).array ?? [] {
            if let name = entry["name"]?.string { out[name] = entry["result"]?.array ?? [] }
        }
        return out
    }

    private func post(_ endpoint: String, _ body: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.igdb.com/v4/\(endpoint)")!)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue(credentials.clientID, forHTTPHeaderField: "Client-ID")
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        var (data, response) = try await api.send(request)
        if response.statusCode == 401 {
            // The token was revoked before its expiry (e.g. the secret was rotated): replace it once.
            request.setValue("Bearer \(try await accessToken(replacingStored: true))", forHTTPHeaderField: "Authorization")
            (data, response) = try await api.send(request)
        }
        guard response.statusCode == 200 else { throw HTTPStatusError(status: response.statusCode, url: request.url) }
        return data
    }

    private struct StoredToken: Codable {
        let token: String
        let expiresAt: Date
    }

    /// The Twitch app access token, kept in the token store (or the cache) and replaced an hour before it expires.
    private func accessToken(replacingStored: Bool = false) async throws -> String {
        if !replacingStored, let payload = try storedToken(),
            let stored = try? JSONDecoder().decode(StoredToken.self, from: payload),
            clock.now() < stored.expiresAt.addingTimeInterval(-3_600)
        {
            return stored.token
        }
        // Credentials go in the form body, not the URL, so they never appear in logged URLs.
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "client_secret", value: credentials.clientSecret),
            URLQueryItem(name: "grant_type", value: "client_credentials"),
        ]
        var request = URLRequest(url: URL(string: "https://id.twitch.tv/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await transport.send(request)
        let json = try? JSONValue.decode(data)
        guard response.statusCode == 200, let token = json?["access_token"]?.string, let lifetime = json?["expires_in"]?.number else {
            throw HTTPStatusError(status: response.statusCode, url: request.url)
        }
        let stored = StoredToken(token: token, expiresAt: clock.now().addingTimeInterval(lifetime))
        try storeToken(try JSONEncoder().encode(stored))
        return token
    }

    private func storedToken() throws -> Data? {
        if let tokenStore { return try tokenStore.secret(for: "twitch-token:\(credentials.clientID)").map { Data($0.utf8) } }
        return try cache.entries(["twitch:token:\(credentials.clientID)"]).values.first?.payload
    }

    private func storeToken(_ payload: Data) throws {
        if let tokenStore {
            try tokenStore.setSecret(String(decoding: payload, as: UTF8.self), for: "twitch-token:\(credentials.clientID)")
        } else {
            try cache.store(["twitch:token:\(credentials.clientID)": payload])
        }
    }

    /// Everything on the game, with the game's own sub-records expanded inline.
    /// Other games (similar, remakes, ports…) are referenced by id and name only.
    static let gameFields = [
        "*",
        "cover.*", "screenshots.*", "artworks.*", "videos.*", "websites.*",
        "external_games.*", "release_dates.*", "alternative_names.*", "game_localizations.*",
        "involved_companies.*", "involved_companies.company.*",
        "genres.*", "themes.*", "keywords.*", "franchise.*", "franchises.*", "collections.*",
        "game_modes.*", "player_perspectives.*", "multiplayer_modes.*", "language_supports.*",
        "age_ratings.*", "platforms.*", "game_engines.*",
        "similar_games.name", "remakes.name", "remasters.name", "ports.name", "forks.name",
        "dlcs.name", "expansions.name", "standalone_expansions.name", "expanded_games.name",
        "bundles.name", "parent_game.name", "version_parent.name",
    ].joined(separator: ",")
}
