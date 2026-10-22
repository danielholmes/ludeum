import Foundation
import Synchronization
import UniformTypeIdentifiers

@testable import LudeumCore

/// Fake versions of the external services (Twitch auth, IGDB, IGDB images, Hasheous),
/// routed by host. Each request is recorded along with the time it was sent.
final class FakeInternet: HTTPTransport, Sendable {
    struct SentRequest {
        let request: URLRequest
        let at: Date
        var host: String { request.url?.host() ?? "" }
        var body: String { request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? "" }
    }

    struct State {
        // IGDB
        var games: [Int: String] = [:]
        var gameFields: [Int: Data] = [:]  // extra record fields, as a JSON object
        var timeToBeat: [Int: Int] = [:]
        var searches: [String: [Int]] = [:]  // "<platform or any>:<name>" → ids
        var platforms: [[String: Any]] = []
        var genres: [[String: Any]] = []
        var themes: [[String: Any]] = []
        var companies: [[String: Any]] = []  // each with "developed": Bool
        var maxGamesPerResponse = Int.max  // larger game batches get "413 Payload Too Large"
        // Twitch
        var tokenLifetime: Int = 5_000_000
        var tokensIssued = 0
        var firstValidToken = 1  // tokens numbered below this are rejected
        // Hasheous
        var hashes: [String: (game: Int, platform: Int)] = [:]  // "md5/<hash>" or "crc/<hash>"
        var signatures: [String: (romName: String?, country: [String: String])] = [:]  // the DAT entry's, keyed as `hashes`
        var failingHashes: Set<String> = []  // answered with a 500, keyed as `hashes`
        // The LaunchBox Games Database's daily dump, `Metadata.zip`
        var launchBoxDump: Data?
        // Failure injection, keyed by host
        var down: Set<String> = []
        var rateLimitOnce: [String: Int] = [:]  // host → Retry-After seconds
        var sent: [SentRequest] = []
    }

    let clock: TestClock
    let state = Mutex(State())

    init(clock: TestClock) { self.clock = clock }

    // MARK: - Test setup and inspection

    func addGame(_ id: Int, _ name: String, normallySeconds: Int? = nil) {
        state.withLock {
            $0.games[id] = name
            if let s = normallySeconds { $0.timeToBeat[id] = s }
        }
    }

    /// A game whose record carries extra fields, e.g. `game_type`, `alternative_names` or `parent_game`.
    func addGame(_ id: Int, _ name: String, fields: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: fields)
        state.withLock {
            $0.games[id] = name
            $0.gameFields[id] = data
        }
    }

    /// A search on one platform, or with `platform: nil` on every platform.
    func addSearch(_ name: String, platform: Int?, results: [Int]) {
        state.withLock { $0.searches["\(platform.map(String.init) ?? "any"):\(name)"] = results }
    }

    func addPlatform(_ id: Int, _ name: String, abbreviation: String? = nil) {
        state.withLock { $0.platforms.append(["id": id, "name": name, "abbreviation": abbreviation as Any? ?? NSNull()]) }
    }

    func addGenre(_ id: Int, _ name: String) { state.withLock { $0.genres.append(["id": id, "name": name]) } }
    func addTheme(_ id: Int, _ name: String) { state.withLock { $0.themes.append(["id": id, "name": name]) } }
    /// A company; one that never developed or published anything isn't offered as a filter.
    func addCompany(_ id: Int, _ name: String, developed: Bool = true) {
        state.withLock { $0.companies.append(["id": id, "name": name, "developed": developed]) }
    }

    /// A checksum Hasheous knows, with its DAT entry's name and countries in its signature when given.
    func addHash(md5: String, game: Int, platform: Int, romName: String? = nil, country: [String: String] = [:]) {
        addHash("md5/\(md5.lowercased())", game, platform, romName, country)
    }

    func addHash(crc: String, game: Int, platform: Int, romName: String? = nil, country: [String: String] = [:]) {
        addHash("crc/\(crc.lowercased())", game, platform, romName, country)
    }

    private func addHash(_ key: String, _ game: Int, _ platform: Int, _ romName: String?, _ country: [String: String]) {
        state.withLock {
            $0.hashes[key] = (game, platform)
            if romName != nil || !country.isEmpty { $0.signatures[key] = (romName, country) }
        }
    }

    /// The LaunchBox Games Database's dump, `Metadata.zip` holding `games` as its `Metadata.xml`.
    func setLaunchBox(_ games: [LaunchBoxGame]) {
        let dump = LaunchBoxGame.zip(games)
        state.withLock { $0.launchBoxDump = dump }
    }

    func setDown(_ host: String, _ isDown: Bool) {
        state.withLock { if isDown { $0.down.insert(host) } else { $0.down.remove(host) } }
    }

    func rateLimitOnce(_ host: String, retryAfter: Int) {
        state.withLock { $0.rateLimitOnce[host] = retryAfter }
    }

    /// Twitch revokes every token issued so far (e.g. the secret was rotated).
    func revokeAllTokens() { state.withLock { $0.firstValidToken = $0.tokensIssued + 1 } }

    func setTokenLifetime(seconds: Int) { state.withLock { $0.tokenLifetime = seconds } }

    var sent: [SentRequest] { state.withLock { $0.sent } }
    func sent(to host: String) -> [SentRequest] { sent.filter { $0.host == host } }
    var tokensIssued: Int { state.withLock { $0.tokensIssued } }
    func resetSent() { state.withLock { $0.sent = [] } }

    /// Game ids requested from IGDB's games endpoint, one array per HTTP request.
    var requestedGameIDBatches: [[Int]] {
        sent(to: Hosts.igdb).compactMap { r in
            let ids = Self.queryBlocks(r.body)
                .filter { $0.endpoint == "games" && !$0.text.contains("search \"") }
                .flatMap { Self.ids(after: "where id = (", in: $0.text) }
            return ids.isEmpty ? nil : ids
        }
    }

    // MARK: - HTTPTransport

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let host = request.url?.host() ?? ""
        let (status, headers, body): (Int, [String: String], Data) = state.withLock { s in
            s.sent.append(SentRequest(request: request, at: clock.now()))
            if s.down.contains(host) { return (503, [:], Data("down".utf8)) }
            if let retry = s.rateLimitOnce.removeValue(forKey: host) {
                return (429, ["Retry-After": "\(retry)"], Data())
            }
            switch host {
            case Hosts.twitch: return Self.token(&s)
            case Hosts.igdb: return Self.igdb(request, s)
            case Hosts.igdbImages: return (200, [:], Self.coverJPEG)
            case Hosts.hasheous: return Self.hasheous(request, s)
            case Hosts.launchBox:
                guard request.url?.path() == "/Metadata.zip", let dump = s.launchBoxDump else { return (404, [:], Data()) }
                return (200, [:], dump)
            case Hosts.launchBoxImages: return (200, [:], Self.boxartPNG)
            default: return (404, [:], Data())
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (body, response)
    }

    /// What LaunchBox's image host serves: a real (tiny) PNG, 12 × 16.
    static let boxartPNG = testImage(width: 12, height: 16, type: .png)

    /// What IGDB's image host serves: a real (tiny) JPEG, 10 × 14.
    static let coverJPEG = testImage(width: 10, height: 14, type: .jpeg)

    enum Hosts {
        static let twitch = "id.twitch.tv"
        static let igdb = "api.igdb.com"
        static let igdbImages = "images.igdb.com"
        static let hasheous = "hasheous.org"
        static let launchBox = "gamesdb.launchbox-app.com"
        static let launchBoxImages = "images.launchbox-app.com"
    }

    // MARK: - Fake services

    private static func token(_ s: inout State) -> (Int, [String: String], Data) {
        s.tokensIssued += 1
        let json = #"{"access_token":"token-\#(s.tokensIssued)","expires_in":\#(s.tokenLifetime),"token_type":"bearer"}"#
        return (200, [:], Data(json.utf8))
    }

    private static func igdb(_ request: URLRequest, _ s: State) -> (Int, [String: String], Data) {
        let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
        guard auth.hasPrefix("Bearer token-"), let n = Int(auth.dropFirst("Bearer token-".count)), n >= s.firstValidToken else {
            return (401, [:], Data())
        }
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        switch request.url?.path() {
        case "/v4/games" where body.contains("search \""):
            return (200, [:], try! JSONSerialization.data(withJSONObject: searchResult(body, s)))
        case "/v4/games" where body.contains("alternative_names.name ~"):
            // The search fallback: name or alternative name containing the text, ignoring case, or the slug.
            let text = body.components(separatedBy: "name ~ *\"")[1].components(separatedBy: "\"")[0].lowercased()
            let found = s.games.keys.sorted().filter { id in
                let extra = s.gameFields[id].flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                let alternatives = (extra["alternative_names"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                let platforms = (extra["platforms"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? Int }
                let platformOK = Self.ids(after: "platforms = (", in: body).first.map(platforms.contains) ?? true
                return platformOK && ([s.games[id]!] + alternatives).contains { $0.lowercased().contains(text) }
            }
            return (200, [:], try! JSONSerialization.data(withJSONObject: found.map { ["id": $0] }))
        case "/v4/games" where body.contains("sort total_rating_count"):
            // A filter-only search: games with any of the genres, any of the themes, and the company.
            let found = s.games.keys.sorted().filter { id in
                let extra = s.gameFields[id].flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                func has(_ field: String, _ marker: String, id path: ([String: Any]) -> Int?) -> Bool {
                    let wanted = Self.ids(after: marker, in: body)
                    let actual = (extra[field] as? [[String: Any]] ?? []).compactMap(path)
                    return wanted.isEmpty || actual.contains(where: wanted.contains)
                }
                return has("platforms", "platforms = (") { $0["id"] as? Int }
                    && has("genres", "genres = (") { $0["id"] as? Int }
                    && has("themes", "themes = (") { $0["id"] as? Int }
                    && has("involved_companies", "involved_companies.company = (") { ($0["company"] as? [String: Any])?["id"] as? Int }
            }
            return (200, [:], try! JSONSerialization.data(withJSONObject: found.map { ["id": $0] }))
        case "/v4/games" where body.contains("where bundles = ("):
            // A bundle's contents: games whose record lists it in `bundles` (as ids, like IGDB's unexpanded field).
            let bundle = Self.ids(after: "where bundles = (", in: body).first
            let found = s.games.keys.sorted().filter { id in
                let extra = s.gameFields[id].flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                return (extra["bundles"] as? [Int] ?? []).contains { $0 == bundle }
            }
            return (200, [:], try! JSONSerialization.data(withJSONObject: found.map { ["id": $0] }))
        case "/v4/genres":
            return (200, [:], try! JSONSerialization.data(withJSONObject: s.genres))
        case "/v4/themes":
            return (200, [:], try! JSONSerialization.data(withJSONObject: s.themes))
        case "/v4/companies":
            let text = body.components(separatedBy: "name ~ *\"")[1].components(separatedBy: "\"")[0].lowercased()
            let found = s.companies.filter { ($0["developed"] as! Bool) && ($0["name"] as! String).lowercased().contains(text) }
            return (200, [:], try! JSONSerialization.data(withJSONObject: found.map { ["id": $0["id"]!, "name": $0["name"]!] }))
        case "/v4/platforms":
            let offset = Int(body.components(separatedBy: "offset ").dropFirst().first?.prefix { $0.isNumber } ?? "0") ?? 0
            return (200, [:], try! JSONSerialization.data(withJSONObject: Array(s.platforms.dropFirst(offset).prefix(500))))
        case "/v4/multiquery" where body.contains("search \""):
            // Like real IGDB: multiquery silently ignores `search` and returns nothing at all.
            return (200, [:], Data("[]".utf8))
        case "/v4/multiquery":
            break
        default:
            return (404, [:], Data())
        }
        let requestedGames = queryBlocks(body).filter { $0.endpoint == "games" }.flatMap { ids(after: "where id = (", in: $0.text) }
        if requestedGames.count > s.maxGamesPerResponse { return (413, [:], Data()) }
        var results: [[String: Any]] = []
        for block in queryBlocks(body) {
            let result: [Any]
            switch block.endpoint {
            case "games":
                result = ids(after: "where id = (", in: block.text).compactMap { id in
                    s.games[id].map { name in
                        let extra = s.gameFields[id].flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                        return extra.merging(["id": id, "name": name, "screenshots": [["id": id * 10, "image_id": "sc\(id)"]]]) { a, _ in a
                        }
                    }
                }
            case "game_time_to_beats":
                result = ids(after: "where game_id = (", in: block.text).compactMap { id in
                    s.timeToBeat[id].map { ["id": id + 100_000, "game_id": id, "normally": $0] }
                }
            default:
                result = []
            }
            results.append(["name": block.name, "result": result])
        }
        return (200, [:], try! JSONSerialization.data(withJSONObject: results))
    }

    private static func searchResult(_ body: String, _ s: State) -> [[String: Any]] {
        let name = body.components(separatedBy: "search \"")[1].components(separatedBy: "\"")[0]
        let platform = ids(after: "platforms = (", in: body).first.map(String.init) ?? "any"
        return (s.searches["\(platform):\(name)"] ?? []).map { ["id": $0] }
    }

    private static func hasheous(_ request: URLRequest, _ s: State) -> (Int, [String: String], Data) {
        let prefix = "/api/v1/Lookup/ByHash/"
        let path = request.url!.path()
        let key = String(path.dropFirst(prefix.count)).lowercased()
        if s.failingHashes.contains(key) { return (500, [:], Data()) }
        guard path.hasPrefix(prefix), let hit = s.hashes[key] else {
            return (404, [:], Data("The provided hash was not found in any signature database.".utf8))
        }
        var json: [String: Any] = [
            "id": 1, "name": "Some Game",
            "platform": [
                "name": "Some Platform",
                "metadata": [
                    ["objectType": "Platform", "id": "x", "immutableId": "\(hit.platform)", "source": "IGDB", "status": "Mapped"]
                ],
            ],
            "metadata": [
                ["objectType": "Game", "id": "slug", "immutableId": "\(hit.game)", "source": "IGDB", "status": "Mapped"],
                ["objectType": "Game", "id": "77", "immutableId": "77", "source": "RetroAchievements", "status": "Mapped"],
            ],
        ]
        if let signature = s.signatures[key] {
            var rom: [String: Any] = ["country": signature.country, "signatureSource": "NoIntros"]
            if let name = signature.romName { rom["name"] = name }
            json["signature"] = ["game": ["name": "Some Game", "country": [:] as [String: String]], "rom": rom]
        }
        return (200, [:], try! JSONSerialization.data(withJSONObject: json))
    }

    private struct Block {
        let endpoint: String
        let name: String
        let text: String
    }

    private static func queryBlocks(_ body: String) -> [Block] {
        body.components(separatedBy: "query ").dropFirst().map { chunk in
            let endpoint = chunk.components(separatedBy: " ")[0]
            let name = chunk.components(separatedBy: "\"")[1]
            return Block(endpoint: endpoint, name: name, text: chunk)
        }
    }

    static func ids(after marker: String, in text: String) -> [Int] {
        guard let range = text.range(of: marker) else { return [] }
        let rest = text[range.upperBound...]
        let list = rest.prefix { $0 != ")" }
        return list.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
}
