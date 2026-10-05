import Foundation
import GRDB

/// The Library's filters. Nil means "any"; set filters combine.
public struct LibraryFilter: Sendable, Equatable {
    public var platformId: Int64?
    public var rating: RatingFilter?
    /// `.some(nil)` is "no Intent"; `nil` is any.
    public var intent: Intent??
    public var listId: Int64?
    public var outcome: OutcomeFilter?
    public var childhood: Bool?
    /// Only Games with a Playthrough that has no dates (Year in review's footer links here).
    public var undatedPlaythroughs: Bool
    /// An IGDB genre. Not applied by `library(_:sort:ascending:)`: genres live in the cache, so
    /// the caller narrows the rows with `having(genre:in:)`.
    public var genre: String?
    /// An IGDB theme, franchise or series, applied like `genre`.
    public var theme: String?
    public var franchise: String?
    public var series: String?
    /// A company involved in any role.
    public var company: String?
    /// Games with a name (override, IGDB's or their own) containing this, ignoring ASCII case. Empty is no filter.
    public var name = ""

    public init(
        platformId: Int64? = nil, rating: RatingFilter? = nil, intent: Intent?? = nil, listId: Int64? = nil,
        outcome: OutcomeFilter? = nil, childhood: Bool? = nil, undatedPlaythroughs: Bool = false, genre: String? = nil,
        theme: String? = nil, franchise: String? = nil, series: String? = nil, company: String? = nil,
        name: String = ""
    ) {
        self.company = company
        self.name = name
        self.genre = genre
        self.theme = theme
        self.franchise = franchise
        self.series = series
        self.undatedPlaythroughs = undatedPlaythroughs
        self.platformId = platformId
        self.rating = rating
        self.intent = intent
        self.listId = listId
        self.outcome = outcome
        self.childhood = childhood
    }
}

public enum RatingFilter: Sendable, Hashable {
    case unrated
    case atLeast(Rating)
}

public enum OutcomeFilter: String, Sendable, CaseIterable {
    /// A Playthrough in progress.
    case playing
    /// At least one Playthrough with that Outcome.
    case finished, dropped
    /// No Playthroughs at all.
    case notPlayed
}

public enum LibrarySort: String, Sendable, CaseIterable {
    case name, platform, rating
    /// When the Intent was set.
    case intentSet
    /// IGDB's first release year. It lives in the cache, so only `library(_:sort:ascending:facts:)`
    /// applies it; without facts the order is by name.
    case year

    /// The order choosing this sort starts in: A–Z for names and Platforms, oldest first for years, best and newest first otherwise.
    public var defaultAscending: Bool {
        switch self {
        case .name, .platform, .year: true
        case .rating, .intentSet: false
        }
    }
}

/// A Game as the Library lists it.
public struct LibraryRow: Sendable, Equatable, Identifiable {
    public let id: GameID
    public let name: String
    public let platformId: Int64
    public let platformName: String
    public let igdbGameId: Int64?
    public let rating: Rating?
    /// The current Rating was brought over from OpenEmu stars ("≈ imported").
    public let ratingImported: Bool
    public let intent: Intent?
    public let intentSetAt: Date?
    public let childhood: Bool
    /// Playing: a Playthrough in progress.
    public let isPlaying: Bool
    /// The latest start among its in-progress Playthroughs.
    public let playingSince: PartialDate?
    /// The Outcomes of its finished and dropped Playthroughs, without repeats.
    public let outcomes: Set<Outcome>
    /// It has ROMs, and every one is missing.
    public let noROMInOpenEmu: Bool
}

extension JournalStore {
    /// The Library: Games matching `filter`, in `sort` order. Unset values (unrated, no Intent)
    /// sort last either way; ties go by name.
    public func library(_ filter: LibraryFilter, sort: LibrarySort, ascending: Bool) throws -> [LibraryRow] {
        var conditions: [String] = []
        var arguments: [any DatabaseValueConvertible] = []
        if let platformId = filter.platformId {
            let ids = PlatformGroups.ids(shownAs: platformId)
            conditions.append("g.platformId IN (\(ids.map { _ in "?" }.joined(separator: ",")))")
            arguments += ids
        }
        switch filter.rating {
        case .unrated: conditions.append("r.rating IS NULL")
        case .atLeast(let rating):
            conditions.append("r.rating >= ?")
            arguments.append(rating.tenths)
        case nil: break
        }
        switch filter.intent {
        case .some(.some(let intent)):
            conditions.append("g.intent = ?")
            arguments.append(intent.rawValue)
        case .some(.none): conditions.append("g.intent IS NULL")
        case .none: break
        }
        if let listId = filter.listId {
            conditions.append("EXISTS (SELECT 1 FROM listGame l WHERE l.gameId = g.id AND l.listId = ?)")
            arguments.append(listId)
        }
        switch filter.outcome {
        case .playing: conditions.append("EXISTS (SELECT 1 FROM playthrough p WHERE p.gameId = g.id AND p.outcome IS NULL)")
        case .finished, .dropped:
            conditions.append("EXISTS (SELECT 1 FROM playthrough p WHERE p.gameId = g.id AND p.outcome = ?)")
            arguments.append(filter.outcome!.rawValue)
        case .notPlayed: conditions.append("NOT EXISTS (SELECT 1 FROM playthrough p WHERE p.gameId = g.id)")
        case nil: break
        }
        if let childhood = filter.childhood {
            conditions.append("g.childhood = ?")
            arguments.append(childhood)
        }
        let search = filter.name.trimmingCharacters(in: .whitespaces)
        if !search.isEmpty {
            // Every name the Game goes by, so an override doesn't hide IGDB's or the No-Intro one.
            conditions.append("(g.nameOverride LIKE ? ESCAPE '\\' OR g.igdbName LIKE ? ESCAPE '\\' OR g.name LIKE ? ESCAPE '\\')")
            let escaped = search.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            arguments += Array(repeating: "%\(escaped)%", count: 3)
        }
        if filter.undatedPlaythroughs {
            conditions.append("EXISTS (SELECT 1 FROM playthrough p WHERE p.gameId = g.id AND p.start IS NULL AND p.end IS NULL)")
        }
        let direction = ascending ? "ASC" : "DESC"
        let name = "displayName COLLATE NOCASE ASC"
        let order =
            switch sort {
            case .name: "displayName COLLATE NOCASE \(direction)"
            case .platform: "platformName COLLATE NOCASE \(direction), \(name)"
            case .rating: "r.rating IS NULL, r.rating \(direction), \(name)"
            case .intentSet: "g.intentSetAt IS NULL, g.intentSetAt \(direction), \(name)"
            case .year: name
            }
        let sql = """
            SELECT g.id, g.platformId, g.igdbGameId, g.intent, g.intentSetAt, g.childhood,
                COALESCE(g.nameOverride, g.igdbName, g.name) AS displayName,
                \(PlatformGroups.shownNameSQL(platformId: "g.platformId", name: "pl.name")) AS platformName,
                r.rating AS currentRating, COALESCE(r.imported, 0) AS ratingImported,
                EXISTS (SELECT 1 FROM playthrough p WHERE p.gameId = g.id AND p.outcome IS NULL) AS playing,
                (SELECT MAX(start) FROM playthrough p WHERE p.gameId = g.id AND p.outcome IS NULL) AS playingSince,
                (SELECT group_concat(DISTINCT outcome) FROM playthrough p WHERE p.gameId = g.id) AS outcomes,
                EXISTS (SELECT 1 FROM rom WHERE gameId = g.id)
                    AND NOT EXISTS (SELECT 1 FROM rom WHERE gameId = g.id AND NOT missing) AS noROM
            FROM game g
            JOIN platform pl ON pl.id = g.platformId
            LEFT JOIN ratingEntry r ON r.id = (SELECT id FROM ratingEntry WHERE gameId = g.id \(Self.ratingOrder) LIMIT 1)
            \(conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND "))
            ORDER BY \(order)
            """
        return try db.read { db in
            try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments)).map { row in
                LibraryRow(
                    id: row["id"], name: row["displayName"], platformId: row["platformId"], platformName: row["platformName"],
                    igdbGameId: row["igdbGameId"], rating: (row["currentRating"] as Int?).flatMap { Rating(tenths: $0) },
                    ratingImported: row["ratingImported"],
                    intent: (row["intent"] as String?).flatMap(Intent.init(rawValue:)), intentSetAt: row["intentSetAt"],
                    childhood: row["childhood"], isPlaying: row["playing"],
                    playingSince: (row["playingSince"] as String?).flatMap(PartialDate.init),
                    outcomes: Set(((row["outcomes"] as String?) ?? "").split(separator: ",").compactMap { Outcome(rawValue: String($0)) }),
                    noROMInOpenEmu: row["noROM"])
            }
        }
    }
}

/// A Platform I have Games on, for the sidebar.
public struct PlatformCount: Sendable, Equatable {
    public let id: Int64
    public let name: String
    public let games: Int
}

extension JournalStore {
    /// Every Platform with at least one Game, by name, with grouped platforms (DOS and Windows as PC) as one.
    public func platformCounts() throws -> [PlatformCount] {
        try db.read { db in
            let counts = try Row.fetchAll(
                db,
                sql: """
                    SELECT p.id, p.name, COUNT(*) AS games FROM game g JOIN platform p ON p.id = g.platformId
                    GROUP BY p.id ORDER BY p.name COLLATE NOCASE
                    """
            ).map { PlatformCount(id: $0["id"], name: $0["name"], games: $0["games"]) }
            // Grouped platforms show as one.
            let grouped = Dictionary(grouping: counts) { PlatformGroups.shownID($0.id) }
            return grouped.map { id, members in
                PlatformCount(
                    id: id, name: PlatformGroups.groupName(id) ?? members[0].name, games: members.reduce(0) { $0 + $1.games })
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
}
