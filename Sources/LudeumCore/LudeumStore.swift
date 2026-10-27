import Foundation
import GRDB

public typealias GameID = Int64

public enum LudeumError: Error, Equatable {
    case igdbLinkTaken
    case endBeforeStart
    case playerNameTaken
    /// A Game can't be deleted while it has any Copy: its ROMs and hand-recorded Copies are deleted first.
    case gameHasCopies
    /// A Game can't be deleted while a Bundle contains it: it leaves the Bundle first.
    case gameInBundle
    /// Only a Game on a Bundle's Platform can be in it: not a Game of another Platform, nor a Bundle.
    case cantBeInBundle
    /// A Copy can't be Gone before it was acquired.
    case goneBeforeAcquired
    case gameNotFound
    case nameRequired
    /// A Game's IGDB link is changed only on purpose (`replacing`), and never removed.
    case alreadyLinked
    /// A Game's Platform changes only while it has no ROMs: they say what it's played on.
    case gameHasROMs
    /// MesenCE takes 0–10 frames of run-ahead.
    case runAheadOutOfRange
    /// DuckStation's CD read speedup is 1–6 times, or 0 for as fast as it can.
    case cdReadSpeedupOutOfRange
    /// DuckStation's CD seek speedup is 1–6 times, or 0 for as fast as it can.
    case cdSeekSpeedupOutOfRange
    /// A Copy a Playthrough was played on can't be deleted, or leave its Game, until the Playthrough says otherwise.
    case copyPlayedOn
    /// A Playthrough's Copy is one of its own Game's.
    case copyNotOfGame
}

/// A Game as the journal shows it.
public struct Game: Sendable, Equatable {
    public let id: GameID
    public let platformId: Int64
    public let igdbGameId: Int64?
    /// The display name: the override, else IGDB's name, else the Game's own name.
    public let name: String
    /// What I want to see first on its page; nil when there's none.
    public let highlightNote: String?
    public let childhood: Bool
    public let intent: Intent?
    /// When the Intent was set; nil for undated Intent (from the first Import).
    public let intentSetAt: Date?
    /// The current Rating: the latest Rating history entry. Nil when unrated.
    public let rating: Rating?
    /// A Bundle (ADR 0016): it contains Games, and has no Rating, Intent, Childhood or Playthroughs.
    public let isBundle: Bool
}

public enum Intent: String, Sendable, CaseIterable {
    case backlog, upNext, wantToBuy
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
public final class LudeumStore: Sendable {
    let db: DatabaseQueue
    let clock: TimeSource
    let calendar: Calendar
    /// Where a backup is taken before every deletion of a Game or Playthrough.
    let backups: Backups?

    /// Opens the journal, taking every migration it hasn't. A journal with data is backed up first; one just made has
    /// nothing to lose. One that still has OpenEmu ROMs is refused (`LudeumSchema.OpenEmuROMsRemain`).
    public init(
        directory: URL, clock: TimeSource = SystemTimeSource(), timeZone: TimeZone = .current, backups: Backups? = nil
    ) throws {
        self.backups = backups
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var config = Configuration()
        config.foreignKeysEnabled = true
        db = try DatabaseQueue(path: directory.appending(path: "journal.sqlite").path(percentEncoded: false), configuration: config)
        self.clock = clock
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
        let migrator = LudeumSchema.migrator
        let (applied, completed) = try db.read { db in
            (try migrator.appliedIdentifiers(db), try migrator.hasCompletedMigrations(db))
        }
        if !applied.isEmpty, !completed { try backups?.backUp(self, operation: .beforeSchemaMigration) }
        try migrator.migrate(db)
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
        try write(uniqueViolation: .igdbLinkTaken) { db in
            try db.execute(
                sql: "INSERT INTO game (platformId, name, igdbGameId, igdbName) VALUES (?, ?, ?, ?)",
                arguments: [platformId, name, igdbGameId, igdbName])
            return db.lastInsertedRowID
        }
    }

    /// A write whose UNIQUE constraint failure means `error`.
    func write<T>(uniqueViolation error: LudeumError, _ body: (Database) throws -> T) throws -> T {
        do {
            return try db.write(body)
        } catch let dbError as DatabaseError where dbError.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
            throw error
        }
    }

    public func setNameOverride(_ id: GameID, _ name: String?) throws {
        try db.write { db in try db.execute(sql: "UPDATE game SET nameOverride = ? WHERE id = ?", arguments: [name, id]) }
    }

    /// Trimmed; a blank one clears it.
    public func setHighlightNote(_ id: GameID, _ note: String?) throws {
        let note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        try db.write { db in
            try db.execute(
                sql: "UPDATE game SET highlightNote = ? WHERE id = ?", arguments: [note?.isEmpty == false ? note : nil, id])
        }
    }

    public func game(_ id: GameID) throws -> Game {
        try db.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT g.*, COALESCE(g.nameOverride, g.igdbName, g.name) AS displayName,
                        r.rating AS currentRating
                    FROM game g
                    LEFT JOIN ratingEntry r ON r.id = (
                        SELECT id FROM ratingEntry WHERE gameId = g.id \(Self.ratingOrder) LIMIT 1)
                    WHERE g.id = ?
                    """, arguments: [id])
            guard let row else { throw LudeumError.gameNotFound }
            return Game(
                id: row["id"], platformId: row["platformId"], igdbGameId: row["igdbGameId"],
                name: row["displayName"], highlightNote: row["highlightNote"], childhood: row["childhood"],
                intent: (row["intent"] as String?).flatMap(Intent.init(rawValue:)),
                intentSetAt: row["intentSetAt"],
                rating: (row["currentRating"] as Int?).flatMap { Rating(tenths: $0) },
                isBundle: (row["bundle"] as Bool?) ?? false)
        }
    }
}
