import Foundation
import Synchronization

@testable import JournalCore

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
        var maxGamesPerResponse = Int.max  // larger game batches get "413 Payload Too Large"
        // Twitch
        var tokenLifetime: Int = 5_000_000
        var tokensIssued = 0
        var firstValidToken = 1  // tokens numbered below this are rejected
        // Hasheous
        var hashes: [String: (game: Int, platform: Int)] = [:]
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

    func addHash(md5: String, game: Int, platform: Int) {
        state.withLock { $0.hashes[md5.lowercased()] = (game, platform) }
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
            case Hosts.igdbImages: return (200, [:], Data("jpeg:\(request.url!.lastPathComponent)".utf8))
            case Hosts.hasheous: return Self.hasheous(request, s)
            default: return (404, [:], Data())
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (body, response)
    }

    enum Hosts {
        static let twitch = "id.twitch.tv"
        static let igdb = "api.igdb.com"
        static let igdbImages = "images.igdb.com"
        static let hasheous = "hasheous.org"
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
        let platform = ids(after: "where platforms = (", in: body).first.map(String.init) ?? "any"
        return (s.searches["\(platform):\(name)"] ?? []).map { ["id": $0] }
    }

    private static func hasheous(_ request: URLRequest, _ s: State) -> (Int, [String: String], Data) {
        let md5 = request.url!.lastPathComponent.lowercased()
        guard request.url!.path().hasPrefix("/api/v1/Lookup/ByHash/md5/"), let hit = s.hashes[md5] else {
            return (404, [:], Data("The provided hash was not found in any signature database.".utf8))
        }
        let json: [String: Any] = [
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
