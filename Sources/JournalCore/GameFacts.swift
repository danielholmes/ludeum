import Foundation

/// What a linked Game's cached IGDB record says beyond its name: genres, themes, franchises,
/// series and screenshots.
public struct GameFacts: Sendable, Equatable {
    /// e.g. Platform, Role-playing (RPG).
    public let genres: [String]
    /// The setting and mood, e.g. Fantasy, Horror.
    public let themes: [String]
    /// The broad IP, e.g. Looney Tunes, Disney.
    public let franchises: [String]
    /// The game line (IGDB's "collections"), e.g. Castlevania.
    public let series: [String]
    /// Each company once, in IGDB's order, with its roles on this game.
    public let credits: [CompanyCredit]
    /// Every company, whatever its role.
    public var companies: Set<String> { Set(credits.map(\.name)) }
    /// Reference and store pages, most useful first (social media left out).
    public let links: [GameLink]
    /// IGDB users' average score, and IGDB's average of critics' reviews.
    public let playerScore: CommunityScore?
    public let criticScore: CommunityScore?
    /// The year of IGDB's first release date, anywhere.
    public let releaseYear: Int?
    /// IGDB image ids, in IGDB's order.
    public let screenshots: [String]
    /// IGDB's description of the game.
    public var summary: String? = nil
    /// How long players say it takes.
    public var timeToBeat: TimeToBeat? = nil
    /// IGDB's fine-grained tags, e.g. metroidvania, female protagonist.
    public var keywords: [String] = []
    /// The first of IGDB's videos called a trailer, on YouTube.
    public var trailer: URL? = nil

    public init(
        genres: [String], themes: [String], franchises: [String] = [], series: [String] = [], credits: [CompanyCredit] = [],
        releaseYear: Int? = nil, links: [GameLink] = [], playerScore: CommunityScore? = nil, criticScore: CommunityScore? = nil,
        screenshots: [String]
    ) {
        self.playerScore = playerScore
        self.criticScore = criticScore
        self.links = links
        self.credits = credits
        self.releaseYear = releaseYear
        self.genres = genres
        self.themes = themes
        self.franchises = franchises
        self.series = series
        self.screenshots = screenshots
    }

    public static let none = GameFacts(genres: [], themes: [], screenshots: [])
}

/// IGDB's time to beat, in seconds: rushing, a normal playthrough, and 100%.
public struct TimeToBeat: Sendable, Equatable {
    public let hastily: Int?
    public let normally: Int?
    public let completely: Int?

    public init(hastily: Int?, normally: Int?, completely: Int?) {
        self.hastily = hastily
        self.normally = normally
        self.completely = completely
    }
}

/// An average score from IGDB, 0–100, and how many ratings or reviews it averages.
public struct CommunityScore: Sendable, Equatable {
    public let score: Double
    public let count: Int

    public init(score: Double, count: Int) {
        self.score = score
        self.count = count
    }

    init?(_ score: JSONValue?, count: JSONValue?) {
        guard let score = score?.number, let count = count?.int, count > 0 else { return nil }
        self.init(score: score, count: count)
    }

    /// On the journal's 0–10 scale, to one decimal place.
    public var rating: Rating { Rating(tenths: Int(score.rounded()))! }
}

/// A web page about a game.
public struct GameLink: Sendable, Equatable {
    public let title: String
    public let url: URL

    /// IGDB `websites.type` → title, in the order shown. Social media (Twitch, Twitter, YouTube…) is left out.
    static let websiteTypes: [(Int, String)] = [
        (3, "Wikipedia"), (2, "Fan wiki"), (1, "Official site"), (24, "Nintendo"), (13, "Steam"), (17, "GOG"),
        (23, "PlayStation Store"), (22, "Xbox"), (16, "Epic"), (15, "itch.io"),
    ]
}

/// A company's part in one game.
public struct CompanyCredit: Sendable, Equatable {
    public enum Role: String, Sendable, CaseIterable, Comparable {
        case developer, publisher, porting, supporting

        public static func < (a: Role, b: Role) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }
    }

    public let name: String
    /// In the order developer, publisher, porting, supporting. Can be empty.
    public var roles: [Role]

    public init(name: String, roles: [Role]) {
        self.name = name
        self.roles = roles
    }
}

extension IGDBGame {
    public var facts: GameFacts {
        func names(_ field: String) -> [String] { (record[field]?.array ?? []).compactMap { $0["name"]?.string } }
        // IGDB has a main `franchise` and a `franchises` list, and some games fill only one.
        var franchises = names("franchises")
        if let main = record["franchise"]?["name"]?.string, !franchises.contains(main) { franchises.insert(main, at: 0) }
        // IGDB's own page, its `websites` by type, and Giant Bomb from `external_games` (source 3).
        var links: [GameLink] = []
        func add(_ title: String, _ url: String?) {
            guard let url, let u = URL(string: url), !links.contains(where: { $0.title == title }) else { return }
            links.append(GameLink(title: title, url: u))
        }
        let websites = record["websites"]?.array ?? []
        for (type, title) in GameLink.websiteTypes {
            add(title, websites.first { ($0["type"]?.int ?? $0["category"]?.int) == type }?["url"]?.string)
            if title == "Fan wiki" {
                add("IGDB", record["url"]?.string)
                add("Giant Bomb", (record["external_games"]?.array ?? []).first { $0["external_game_source"]?.int == 3 }?["url"]?.string)
            }
        }
        // A company can have several roles on one game, and IGDB can list it more than once.
        var credits: [CompanyCredit] = []
        for involved in record["involved_companies"]?.array ?? [] {
            guard let name = involved["company"]?["name"]?.string else { continue }
            let roles = CompanyCredit.Role.allCases.filter { involved[$0.rawValue] == .bool(true) }
            if let i = credits.firstIndex(where: { $0.name == name }) {
                credits[i].roles += roles.filter { !credits[i].roles.contains($0) }
                credits[i].roles.sort()
            } else {
                credits.append(CompanyCredit(name: name, roles: roles))
            }
        }
        var facts = GameFacts(
            genres: names("genres"), themes: names("themes"), franchises: franchises, series: names("collections"),
            credits: credits,
            releaseYear: record["first_release_date"]?.int.map {
                Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: Date(timeIntervalSince1970: TimeInterval($0))).year!
            },
            links: links,
            playerScore: CommunityScore(record["rating"], count: record["rating_count"]),
            criticScore: CommunityScore(record["aggregated_rating"], count: record["aggregated_rating_count"]),
            screenshots: (record["screenshots"]?.array ?? []).compactMap { $0["image_id"]?.string })
        facts.summary = record["summary"]?.string
        facts.keywords = names("keywords")
        let ttb = record["time_to_beat"]
        let times = TimeToBeat(hastily: ttb?["hastily"]?.int, normally: ttb?["normally"]?.int, completely: ttb?["completely"]?.int)
        if times.hastily != nil || times.normally != nil || times.completely != nil { facts.timeToBeat = times }
        facts.trailer = (record["videos"]?.array ?? [])
            .first { ($0["name"]?.string ?? "").localizedCaseInsensitiveContains("trailer") }?["video_id"]?.string
            .flatMap { URL(string: "https://www.youtube.com/watch?v=\($0)") }
        return facts
    }
}

extension IGDBClient {
    /// A linked Game's facts, from the cache (fetched if it isn't there yet).
    public func facts(igdbGameId: Int64) async throws -> GameFacts {
        try await games(ids: [Int(igdbGameId)])[Int(igdbGameId)]?.facts ?? .none
    }

    /// A screenshot at `screenshot_med` (569 × 320) for a strip of thumbnails, or `screenshot_huge`
    /// (1280 × 720) to look at; cached after the first download.
    public func screenshot(imageID: String, large: Bool = false) async throws -> URL {
        try await image(imageID: imageID, size: large ? "screenshot_huge" : "screenshot_med")
    }
}

/// One release of a game: where and when.
public struct GameRelease: Sendable, Equatable {
    /// e.g. "North America", "Japan".
    public let region: String
    public let year: Int?
}

extension IGDBGame {
    /// IGDB's `release_date_regions`, by id.
    static let regionNames: [Int: String] = [
        1: "Europe", 2: "North America", 3: "Australia", 4: "New Zealand", 5: "Japan", 6: "China", 7: "Asia", 8: "Worldwide",
        9: "Korea", 10: "Brazil",
    ]

    /// Its releases on the IGDB platforms an OpenEmu system maps to, earliest first, one per region.
    public func releases(onSystem system: String) -> [GameRelease] {
        let platforms = Set(openEmuSystemPlatforms[system] ?? [])
        var seen = Set<String>()
        return (record["release_dates"]?.array ?? [])
            .filter { ($0["platform"]?.int).map(platforms.contains) ?? false }
            .compactMap { r -> GameRelease? in
                guard let region = r["release_region"]?.int.flatMap({ Self.regionNames[$0] }) else { return nil }
                return GameRelease(region: region, year: r["y"]?.int)
            }
            .sorted { ($0.year ?? .max) < ($1.year ?? .max) }
            .filter { seen.insert($0.region).inserted }
    }
}
