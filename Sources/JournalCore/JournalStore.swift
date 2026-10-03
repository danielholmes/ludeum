import Foundation
import GRDB

public typealias GameID = Int64

public enum JournalError: Error, Equatable {
    case igdbLinkTaken
    case inProgressNeedsStart
    case endBeforeStart
    case listNameTaken
    case gameHasPresentROMs
    case gameNotFound
}

/// A Game as the journal shows it.
public struct Game: Sendable, Equatable {
    public let id: GameID
    public let platformId: Int64
    public let igdbGameId: Int64?
    /// The display name: the override, else IGDB's name, else the Game's own name.
    public let name: String
    public let childhood: Bool
    public let intent: Intent?
    /// When the Intent was set; nil for undated Intent (from the first Import).
    public let intentSetAt: Date?
    /// The current Rating: the latest Rating history entry. Nil when unrated.
    public let rating: Rating?
    /// Whether the current Rating was imported from OpenEmu stars (approximate).
    public let ratingImported: Bool
}

public enum Intent: String, Sendable {
    case backlog, upNext
}

/// A score from 0.0 to 10.0 in steps of 0.1, held as tenths.
public struct Rating: Hashable, Comparable, Sendable {
    public let tenths: Int

    public init?(tenths: Int) {
        guard (0...100).contains(tenths) else { return nil }
        self.tenths = tenths
    }

    public static func < (lhs: Rating, rhs: Rating) -> Bool { lhs.tenths < rhs.tenths }
}

/// The journal database (`journal.sqlite`): everything that's mine and can't be re-fetched.
public final class JournalStore: Sendable {
    let db: DatabaseQueue
    let clock: TimeSource
    let calendar: Calendar

    public init(directory: URL, clock: TimeSource = SystemTimeSource(), timeZone: TimeZone = .current) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var config = Configuration()
        config.foreignKeysEnabled = true
        db = try DatabaseQueue(path: directory.appending(path: "journal.sqlite").path(percentEncoded: false), configuration: config)
        try JournalSchema.migrator.migrate(db)
        self.clock = clock
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    // MARK: Platforms and Games

    /// Records an IGDB platform, or renames it if it's already known.
    public func addPlatform(id: Int64, name: String) throws {
        try db.write { db in
            try db.execute(
                sql: "INSERT INTO platform (id, name) VALUES (?, ?) ON CONFLICT (id) DO UPDATE SET name = excluded.name",
                arguments: [id, name])
        }
    }

    /// Adds a Game. `name` is a hand-typed or cleaned No-Intro name; a linked Game also has IGDB's name.
    @discardableResult
    public func addGame(platformId: Int64, name: String, igdbGameId: Int64? = nil, igdbName: String? = nil) throws -> GameID {
        try db.write { db in
            do {
                try db.execute(
                    sql: "INSERT INTO game (platformId, name, igdbGameId, igdbName) VALUES (?, ?, ?, ?)",
                    arguments: [platformId, name, igdbGameId, igdbName])
            } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
                throw JournalError.igdbLinkTaken
            }
            return db.lastInsertedRowID
        }
    }

    public func setNameOverride(_ id: GameID, _ name: String?) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE game SET nameOverride = ? WHERE id = ?", arguments: [name, id])
        }
    }

    public func game(_ id: GameID) throws -> Game {
        try db.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT g.*, COALESCE(g.nameOverride, g.igdbName, g.name) AS displayName,
                        r.rating AS currentRating, r.imported AS ratingImported
                    FROM game g
                    LEFT JOIN ratingEntry r ON r.id = (
                        SELECT id FROM ratingEntry WHERE gameId = g.id \(Self.ratingOrder) LIMIT 1)
                    WHERE g.id = ?
                    """, arguments: [id])
            guard let row else { throw JournalError.gameNotFound }
            return Game(
                id: row["id"], platformId: row["platformId"], igdbGameId: row["igdbGameId"],
                name: row["displayName"], childhood: row["childhood"],
                intent: (row["intent"] as String?).flatMap(Intent.init(rawValue:)),
                intentSetAt: row["intentSetAt"],
                rating: (row["currentRating"] as Int?).flatMap { Rating(tenths: $0) },
                ratingImported: row["ratingImported"] ?? false)
        }
    }
}
