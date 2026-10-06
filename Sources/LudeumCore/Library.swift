import Foundation
import GRDB

/// The Library's filters. Nil means "any"; set filters combine.
public struct LibraryFilter: Sendable, Equatable {
    public var platformId: Int64?
    public var rating: RatingFilter?
    /// `.some(nil)` is "no Intent"; `nil` is any.
    public var intent: Intent??
    public var listId: Int64?
    public var player: PlayerFilter?
    public var outcome: OutcomeFilter?
    public var childhood: Bool?
    public var roms: ROMFilter?
    /// An IGDB genre. Not applied by `library(_:sort:ascending:)`: genres live in the cache, so
    /// the caller narrows the rows with `having(genre:in:)`.
    public var genre: String?
    /// An IGDB theme, franchise or series, applied like `genre`.
    public var theme: String?
    public var franchise: String?
    public var series: String?
    /// A company involved in any role.
    public var company: String?
    /// Games with names (override, IGDB's or their own) containing each of its words, ignoring ASCII case. Empty is no filter.
    public var name = ""

    public init(
        platformId: Int64? = nil, rating: RatingFilter? = nil, intent: Intent?? = nil, listId: Int64? = nil,
        player: PlayerFilter? = nil, outcome: OutcomeFilter? = nil, childhood: Bool? = nil, roms: ROMFilter? = nil,
        genre: String? = nil,
        theme: String? = nil, franchise: String? = nil, series: String? = nil, company: String? = nil,
        name: String = ""
    ) {
        self.company = company
        self.name = name
        self.genre = genre
        self.theme = theme
        self.franchise = franchise
        self.series = series
        self.platformId = platformId
        self.rating = rating
        self.intent = intent
        self.listId = listId
        self.player = player
        self.outcome = outcome
        self.childhood = childhood
        self.roms = roms
    }
}

extension LibraryFilter {
    /// The words of the name search. A Game matches when it has every one, in any order and not
    /// necessarily together: "streets rage" finds Streets of Rage.
    public var searchWords: [String] { name.split(whereSeparator: \.isWhitespace).map(String.init) }

    /// These filters within a screen's fixed scope (a Platform, a List, Finished…): whatever the scope
    /// sets wins, and the rest combine with it.
    public func scoped(by scope: LibraryFilter) -> LibraryFilter {
        var f = self
        if let v = scope.platformId { f.platformId = v }
        if let v = scope.rating { f.rating = v }
        if let v = scope.intent { f.intent = v }
        if let v = scope.listId { f.listId = v }
        if let v = scope.player { f.player = v }
        if let v = scope.outcome { f.outcome = v }
        if let v = scope.childhood { f.childhood = v }
        if let v = scope.roms { f.roms = v }
        if let v = scope.genre { f.genre = v }
        if let v = scope.theme { f.theme = v }
        if let v = scope.franchise { f.franchise = v }
        if let v = scope.series { f.series = v }
        if let v = scope.company { f.company = v }
        if !scope.name.isEmpty { f.name = scope.name }
        return f
    }
}

public enum RatingFilter: Sendable, Hashable {
    case unrated
    case atLeast(Rating)
}

/// Games with a Playthrough that includes a Player, or a Solo one.
public enum PlayerFilter: Sendable, Hashable {
    case player(Int64)
    case solo
}

public enum OutcomeFilter: String, Sendable, CaseIterable {
    /// A Playthrough in progress.
    case playing
    /// At least one Playthrough with that Outcome.
    case finished, dropped
    /// No Playthroughs at all.
    case notPlayed
}

/// Games by what their present ROMs let me do. A Game with no present ROM is neither.
public enum ROMFilter: Sendable {
    /// At least one present ROM isn't Archived, so it can be Played.
    case playable
    /// Every present ROM is Archived: nothing to Play until one is Unarchived (or Compacted).
    case archived
}

public enum LibrarySort: String, Sendable, CaseIterable {
    case name, platform, rating
    /// When the Intent was set.
    case intentSet
    /// IGDB's first release year. It lives in the cache, so only `library(_:sort:ascending:facts:)`
    /// applies it; without facts the order is by name.
    case year
    /// IGDB players' average rating, counting only scores with 10 or more ratings. From the cache, like `year`.
    case players
    /// Playing, then Finished, Dropped and never played.
    case played
    case childhood

    /// The order choosing this sort starts in: A–Z for names and Platforms, oldest first for years, best and newest first otherwise.
    public var defaultAscending: Bool {
        switch self {
        case .name, .platform, .year: true
        case .rating, .intentSet, .players, .played, .childhood: false
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
    public let intent: Intent?
    public let intentSetAt: Date?
    public let childhood: Bool
    /// Playing: a Playthrough in progress.
    public let isPlaying: Bool
    /// The latest start among its in-progress Playthroughs.
    public let playingSince: PartialDate?
    /// The Outcomes of its finished and dropped Playthroughs, without repeats.
    public let outcomes: Set<Outcome>
    public let roms: LibraryROMState
    /// IGDB's first release year, when the rows came with IGDB's facts (`withIGDBFacts(_:)`).
    public var releaseYear: Int? = nil
    /// IGDB players' average rating, with the same proviso.
    public var playerScore: CommunityScore? = nil
}

/// What a Library row says about its Game's ROMs.
public enum LibraryROMState: Sendable, Equatable {
    /// A present ROM to Play, and none missing.
    case playable
    /// Present ROMs, every one Archived, and none missing: nothing to Play until one is Unarchived.
    case archived
    /// At least one ROM is missing, whether or not another is present.
    case missing
    /// No ROMs at all: the Game is only in the journal.
    case journalOnly

    init(hasROM: Bool, hasMissingROM: Bool, archived: Bool) {
        self = !hasROM ? .journalOnly : hasMissingROM ? .missing : archived ? .archived : .playable
    }
}

extension LudeumStore {
    /// Game `g` has a present ROM that isn't Archived.
    static let playableSQL = "EXISTS (SELECT 1 FROM rom WHERE gameId = g.id AND NOT missing AND NOT archived)"
    /// Game `g` has present ROMs, and every one is Archived.
    static let archivedSQL = "EXISTS (SELECT 1 FROM rom WHERE gameId = g.id AND NOT missing) AND NOT \(playableSQL)"

    /// The condition, on `game g`, that a Game goes by `word` under any of its names, so an override doesn't hide
    /// IGDB's or the No-Intro one.
    private static func goesBy(_ word: String) -> (sql: String, arguments: [String]) {
        let escaped = word.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return (
            "(g.nameOverride LIKE ? ESCAPE '\\' OR g.igdbName LIKE ? ESCAPE '\\' OR g.name LIKE ? ESCAPE '\\')",
            Array(repeating: "%\(escaped)%", count: 3)
        )
    }

    /// Every Game that goes by `word`, as the Text filter matches a name, whatever else is filtered on.
    func games(goingBy word: String) throws -> Set<GameID> {
        let goesBy = Self.goesBy(word)
        return try db.read { db in
            Set(
                try GameID.fetchAll(db, sql: "SELECT g.id FROM game g WHERE \(goesBy.sql)", arguments: StatementArguments(goesBy.arguments))
            )
        }
    }

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
        switch filter.player {
        case .player(let id):
            conditions.append(
                "EXISTS (SELECT 1 FROM playthrough p JOIN playthroughPlayer pp ON pp.playthroughId = p.id WHERE p.gameId = g.id AND pp.playerId = ?)"
            )
            arguments.append(id)
        case .solo:
            conditions.append(
                "EXISTS (SELECT 1 FROM playthrough p WHERE p.gameId = g.id AND NOT EXISTS (SELECT 1 FROM playthroughPlayer WHERE playthroughId = p.id))"
            )
        case nil: break
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
        switch filter.roms {
        case .playable: conditions.append(Self.playableSQL)
        case .archived: conditions.append("(\(Self.archivedSQL))")
        case nil: break
        }
        for word in filter.searchWords {
            let goesBy = Self.goesBy(word)
            conditions.append(goesBy.sql)
            arguments += goesBy.arguments
        }
        let direction = ascending ? "ASC" : "DESC"
        let name = "displayName COLLATE NOCASE ASC"
        let order =
            switch sort {
            case .name: "displayName COLLATE NOCASE \(direction)"
            case .platform: "platformName COLLATE NOCASE \(direction), \(name)"
            case .rating: "r.rating IS NULL, r.rating \(direction), \(name)"
            case .intentSet: "g.intentSetAt IS NULL, g.intentSetAt \(direction), \(name)"
            case .year, .players: name
            case .played:
                "CASE WHEN playing THEN 3 WHEN outcomes LIKE '%finished%' THEN 2 WHEN outcomes LIKE '%dropped%' THEN 1 ELSE 0 END \(direction), \(name)"
            case .childhood: "g.childhood \(direction), \(name)"
            }
        let sql = """
            SELECT g.id, g.platformId, g.igdbGameId, g.intent, g.intentSetAt, g.childhood,
                COALESCE(g.nameOverride, g.igdbName, g.name) AS displayName,
                \(PlatformGroups.shownNameSQL(platformId: "g.platformId", name: "pl.name")) AS platformName,
                r.rating AS currentRating,
                EXISTS (SELECT 1 FROM playthrough p WHERE p.gameId = g.id AND p.outcome IS NULL) AS playing,
                (SELECT MAX(start) FROM playthrough p WHERE p.gameId = g.id AND p.outcome IS NULL) AS playingSince,
                (SELECT group_concat(DISTINCT outcome) FROM playthrough p WHERE p.gameId = g.id) AS outcomes,
                EXISTS (SELECT 1 FROM rom WHERE gameId = g.id) AS hasROM,
                EXISTS (SELECT 1 FROM rom WHERE gameId = g.id AND missing) AS hasMissingROM,
                \(Self.archivedSQL) AS archived
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
                    intent: (row["intent"] as String?).flatMap(Intent.init(rawValue:)), intentSetAt: row["intentSetAt"],
                    childhood: row["childhood"], isPlaying: row["playing"],
                    playingSince: (row["playingSince"] as String?).flatMap(PartialDate.init),
                    outcomes: Set(((row["outcomes"] as String?) ?? "").split(separator: ",").compactMap { Outcome(rawValue: String($0)) }),
                    roms: LibraryROMState(hasROM: row["hasROM"], hasMissingROM: row["hasMissingROM"], archived: row["archived"]))
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

extension LudeumStore {
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
