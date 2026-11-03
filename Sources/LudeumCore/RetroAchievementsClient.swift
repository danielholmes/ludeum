import Foundation

/// How long RetroAchievements says players take with one set: the median time to beat it and to master it, in seconds,
/// each nil when too few players have (`RetroAchievementsProgression.time`). Beat is roughly IGDB's "normally", master
/// its "completely"; there's nothing like its "hastily".
public struct RetroAchievementsTime: Sendable, Equatable {
    public let beat: Int?
    public let master: Int?

    public init(beat: Int?, master: Int?) {
        self.beat = beat
        self.master = master
    }
}

/// What RetroAchievements' `API_GetGameProgression` says about one set: its console, and its medians with how many
/// players each is the median of. Kept verbatim in the cache.
public struct RetroAchievementsProgression: Sendable, Equatable {
    public let gameID: Int
    public let record: JSONValue

    /// RetroAchievements' console id: a set is one console's (Sonic 2 on Mega Drive and on Game Gear are two).
    public var consoleID: Int? { record["ConsoleID"]?.int }

    /// Its time to beat, from softcore or hardcore players, whichever more have beaten it, and its time to master (every
    /// achievement in hardcore) or to complete (every one in softcore), likewise. Each is left out when fewer than
    /// `minimumPlayers` are behind it, as a median of one or two players can be anything (Populous: 17 hours from
    /// one). Nil when it has neither.
    public var time: RetroAchievementsTime? {
        func median(_ pairs: [(time: String, players: String)]) -> Int? {
            let best = pairs.compactMap { pair -> (time: Int, players: Int)? in
                guard let time = record[pair.time]?.int, time > 0, let players = record[pair.players]?.int else { return nil }
                return (time, players)
            }.max { $0.players < $1.players }
            guard let best, best.players >= Self.minimumPlayers else { return nil }
            return best.time
        }
        let beat = median([
            ("MedianTimeToBeat", "TimesUsedInBeatMedian"), ("MedianTimeToBeatHardcore", "TimesUsedInHardcoreBeatMedian"),
        ])
        let master = median([
            ("MedianTimeToMaster", "TimesUsedInMasteryMedian"), ("MedianTimeToComplete", "TimesUsedInCompletionMedian"),
        ])
        return beat == nil && master == nil ? nil : RetroAchievementsTime(beat: beat, master: master)
    }

    /// How many players a median needs to be shown.
    static let minimumPlayers = 5
}

/// RetroAchievements (retroachievements.org): each set's median times to beat and to master, from the time its
/// players spent in the emulator. Its web API needs an account's key, which goes in each request's query (it has no
/// other way), so it's left out of any error. Set data hardly changes, and its API docs ask for it to be cached: an
/// answer is kept for 180 days, an unknown set included.
public final class RetroAchievementsClient: Sendable {
    let cache: CacheStore
    let api: Throttle
    let key: String

    /// How long an answer is kept before the launch refresh asks again.
    public static let maxAge: TimeInterval = 180 * 86_400

    public init(key: String, cache: CacheStore, transport: HTTPTransport = URLSessionTransport(), clock: TimeSource = SystemTimeSource()) {
        self.key = key
        self.cache = cache
        api = Throttle(requestsPerSecond: 1, transport: transport, clock: clock)
    }

    /// A set's progression; nil when RetroAchievements has no set with that id.
    public func progression(gameID: Int) async throws -> RetroAchievementsProgression? {
        try await progression(gameID: gameID, servesStale: true)
    }

    func progression(gameID: Int, servesStale: Bool) async throws -> RetroAchievementsProgression? {
        let payloads = try await cache.resolve(
            [gameID], key: Self.progressionKey, maxAge: Self.maxAge, batchSize: 1, servesStale: servesStale
        ) { _ in
            [gameID: try await fetch("API_GetGameProgression", ["i": String(gameID)])]
        }
        let record = try JSONValue.decode(payloads[gameID]!)
        return record == .null ? nil : RetroAchievementsProgression(gameID: gameID, record: record)
    }

    static func progressionKey(_ id: Int) -> String { "retroachievements:progression:\(id)" }

    /// An answer, or JSON null for 404 (no such set).
    private func fetch(_ endpoint: String, _ query: [String: String]) async throws -> Data {
        let url = URL(string: "https://retroachievements.org/API/\(endpoint).php")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        let errorURL = components.url
        components.queryItems?.append(URLQueryItem(name: "y", value: key))
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await api.send(request)
        switch response.statusCode {
        case 200: return data
        case 404: return try JSONValue.null.encoded()
        default: throw HTTPStatusError(status: response.statusCode, url: errorURL)
        }
    }

    /// RetroAchievements' console for each IGDB platform it has sets for (`API_GetConsoleIDs`). SNES and Super Famicom
    /// are one console there, as are NES and Famicom.
    static let consoles: [Int64: Int] = [
        29: 1,  // Mega Drive/Genesis
        4: 2,  // Nintendo 64
        19: 3, 58: 3,  // SNES, Super Famicom
        33: 4,  // Game Boy
        24: 5,  // Game Boy Advance
        22: 6,  // Game Boy Color
        18: 7, 99: 7,  // NES, Family Computer
        86: 8, 128: 8,  // TurboGrafx-16/PC Engine, SuperGrafx
        78: 9,  // Sega CD
        30: 10,  // 32X
        64: 11,  // Master System
        7: 12,  // PlayStation
        61: 13,  // Atari Lynx
        119: 14, 120: 14,  // Neo Geo Pocket, Neo Geo Pocket Color
        35: 15,  // Game Gear
        21: 16,  // GameCube
        62: 17,  // Atari Jaguar
        20: 18,  // Nintendo DS
        5: 19,  // Wii
        41: 20,  // Wii U
        8: 21,  // PlayStation 2
        11: 22,  // Xbox
        59: 25,  // Atari 2600
        13: 26,  // DOS
        52: 27,  // Arcade
        87: 28,  // Virtual Boy
        27: 29, 53: 29,  // MSX, MSX2
        15: 30,  // Commodore 64
        16: 35,  // Amiga
        25: 37,  // Amstrad CPC
        75: 38,  // Apple II
        32: 39,  // Saturn
        23: 40,  // Dreamcast
        38: 41,  // PlayStation Portable
        50: 43,  // 3DO
        68: 44,  // ColecoVision
        67: 45,  // Intellivision
        70: 46,  // Vectrex
        66: 50,  // Atari 5200
        60: 51,  // Atari 7800
        57: 53, 123: 53,  // WonderSwan, WonderSwan Color
        26: 59,  // ZX Spectrum
        37: 62,  // Nintendo 3DS
        84: 33,  // SG-1000
        150: 76,  // PC Engine CD
        410: 77,  // Atari Jaguar CD
        159: 78,  // Nintendo DSi
        51: 81,  // Famicom Disk System
        9: 82,  // PlayStation 3
    ]
}
