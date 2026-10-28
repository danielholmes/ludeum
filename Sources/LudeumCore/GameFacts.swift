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
    /// What it expands, when it's an Expansion.
    public var expansion: ExpansionOf? = nil
    /// IGDB's Expansions of it, by IGDB id.
    public var expansionIDs: [Int] = []

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

    /// Enough ratings to rank by: fewer than 10 is shown, but sorts with the unrated.
    public var isReliable: Bool { count >= 10 }

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
            releaseYear: IGDBGame.releaseYear(record),
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
        facts.expansion = expansionOf
        facts.expansionIDs = expansionIDs
        return facts
    }
}

extension IGDBClient {
    /// A linked Game's facts, from the cache (fetched if it isn't there yet).
    public func facts(igdbGameId: Int64) async throws -> GameFacts {
        try await cachedGame(id: Int(igdbGameId))?.facts ?? .none
    }

    /// A screenshot at `screenshot_med` (569 × 320, cropped to fill it) for a strip of thumbnails, or the `original`,
    /// uncropped at its own size, to look at; cached after the first download.
    public func screenshot(imageID: String, original: Bool = false) async throws -> URL {
        try await image(imageID: imageID, size: original ? "original" : "screenshot_med")
    }
}

/// How many times bigger to show a screenshot: 1 for one at least 200 pixels each way, else the least whole amount that
/// takes its shorter side to 200, so each of its pixels becomes a square of them.
public func screenshotScale(pixelWidth: Int, pixelHeight: Int) -> Int {
    let shorter = min(pixelWidth, pixelHeight)
    guard shorter > 0, shorter < 200 else { return 1 }
    return (200 + shorter - 1) / shorter
}

/// How a Game's Screenshots are tiled before "+N more": each the shape of its Platform's screen, the shape most of
/// IGDB's are for the Platforms with many (a Game Boy's 10:9, a PlayStation's 4:3; a Nintendo DS one is both screens,
/// one above the other, 2:3), so a tile shows the whole of one; 16:9 for a Platform not listed and when there's none.
public struct ScreenshotShape: Sendable, Equatable {
    /// Each one's width over its height.
    public let aspectRatio: Double
    /// The Platform's screens in each: two for a Nintendo DS, one for every other.
    public let screens: Int

    public static let widescreen = ScreenshotShape(aspectRatio: 16.0 / 9, screens: 1)

    /// The shape of a Platform's Games' Screenshots, by its IGDB id; the widescreen one when it isn't known.
    public static func of(platformId: Int64?) -> ScreenshotShape {
        switch platformId {
        case 33, 22, 35: ScreenshotShape(aspectRatio: 10.0 / 9, screens: 1)  // Game Boy, Game Boy Color, Game Gear: 160 × 144
        case 24: ScreenshotShape(aspectRatio: 3.0 / 2, screens: 1)  // Game Boy Advance: 240 × 160
        case 18, 99: ScreenshotShape(aspectRatio: 16.0 / 15, screens: 1)  // NES, Family Computer: 256 × 240
        case 19, 58: ScreenshotShape(aspectRatio: 8.0 / 7, screens: 1)  // SNES, Super Famicom: 256 × 224
        case 29, 78: ScreenshotShape(aspectRatio: 10.0 / 7, screens: 1)  // Mega Drive, Sega CD: 320 × 224
        case 13, 16: ScreenshotShape(aspectRatio: 16.0 / 10, screens: 1)  // DOS, Amiga: 320 × 200
        // PlayStation, PlayStation 2, Nintendo 64, GameCube, Saturn, Xbox, Master System, PC Engine CD, MSX2: a 4:3 TV.
        case 7, 8, 4, 21, 32, 11, 64, 150, 53: ScreenshotShape(aspectRatio: 4.0 / 3, screens: 1)
        case 20: ScreenshotShape(aspectRatio: 2.0 / 3, screens: 2)  // Nintendo DS: two 256 × 192 screens
        default: .widescreen
        }
    }

    /// Whether IGDB's thumbnails, cropped to 16:9, are this shape; any other is cropped from the original.
    public var fitsThumbnail: Bool { self == .widescreen }

    /// How they're tiled across `width` points with `spacing` between them, filling it: two rows of the biggest that
    /// keep them at most `twoRowsHeight` tall, so a wider panel fits more across, though never more than
    /// `mostAcross`, taller instead (a Game Boy's in the widest Game detail); or, when those would be narrower than
    /// `narrowest` (a Nintendo DS's), one row of as many as bring each screen in a tile nearest `screenArea`.
    public func layout(width: Double, spacing: Double) -> ScreenshotLayout {
        func tileWidth(_ columns: Int) -> Double { (width - Double(columns - 1) * spacing) / Double(columns) }
        var columns = 1
        while tileWidth(columns) >= Self.narrowest {
            if (2 * tileWidth(columns) / aspectRatio + spacing).rounded() <= Self.twoRowsHeight {
                return ScreenshotLayout(columns: min(columns, Self.mostAcross), rows: 2)
            }
            columns += 1
        }
        let targetWidth = (Self.screenArea * Double(screens) * aspectRatio).squareRoot()
        return ScreenshotLayout(columns: max(1, Int(((width + spacing) / (targetWidth + spacing)).rounded())), rows: 1)
    }

    /// The narrowest a tile in two rows goes.
    static let narrowest = 100.0
    static let mostAcross = 4
    /// One row's tiles are about this many square points each screen: a Nintendo DS's four across 600 points.
    static let screenArea = 12_000.0
    /// About as much as the Screenshots get of Game detail at its narrowest.
    public static let narrowPanelWidth = 400.0
    static let twoRowsHeight = 300.0
}

/// Screenshots' tiles: `columns` across, in `rows`.
public struct ScreenshotLayout: Sendable, Equatable {
    public let columns: Int
    public let rows: Int

    /// How many are shown, the last of them "+N more" when there are more.
    public var limit: Int { columns * rows }
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

    /// Its releases on a ROM's Platform (and the Platforms shown with it, so SNES includes Super Famicom),
    /// earliest first, one per region.
    public func releases(onPlatform platform: Int64) -> [GameRelease] {
        let platforms = Set(PlatformGroups.ids(shownAs: PlatformGroups.shownID(platform)).map(Int.init))
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
