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

    public init(
        platformId: Int64? = nil, rating: RatingFilter? = nil, intent: Intent?? = nil, listId: Int64? = nil,
        outcome: OutcomeFilter? = nil, childhood: Bool? = nil
    ) {
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
            conditions.append("g.platformId = ?")
            arguments.append(platformId)
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
        let direction = ascending ? "ASC" : "DESC"
        let name = "displayName COLLATE NOCASE ASC"
        let order =
            switch sort {
            case .name: "displayName COLLATE NOCASE \(direction)"
            case .platform: "platformName COLLATE NOCASE \(direction), \(name)"
            case .rating: "r.rating IS NULL, r.rating \(direction), \(name)"
            case .intentSet: "g.intentSetAt IS NULL, g.intentSetAt \(direction), \(name)"
            }
        let sql = """
            SELECT g.id, g.platformId, g.igdbGameId, g.intent, g.intentSetAt, g.childhood,
                COALESCE(g.nameOverride, g.igdbName, g.name) AS displayName, pl.name AS platformName,
                r.rating AS currentRating,
                EXISTS (SELECT 1 FROM playthrough p WHERE p.gameId = g.id AND p.outcome IS NULL) AS playing,
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
                    intent: (row["intent"] as String?).flatMap(Intent.init(rawValue:)), intentSetAt: row["intentSetAt"],
                    childhood: row["childhood"], isPlaying: row["playing"],
                    outcomes: Set(((row["outcomes"] as String?) ?? "").split(separator: ",").compactMap { Outcome(rawValue: String($0)) }),
                    noROMInOpenEmu: row["noROM"])
            }
        }
    }
}
