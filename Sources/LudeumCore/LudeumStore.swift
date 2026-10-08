import Foundation
import GRDB

public typealias GameID = Int64

public enum LudeumError: Error, Equatable {
    case igdbLinkTaken
    case endBeforeStart
    case listNameTaken
    case playerNameTaken
    /// A Game can't be deleted while it has any Copy: its ROMs and hand-recorded Copies are deleted first.
    case gameHasCopies
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
    public let childhood: Bool
    public let intent: Intent?
    /// When the Intent was set; nil for undated Intent (from the first Import).
    public let intentSetAt: Date?
    /// The current Rating: the latest Rating history entry. Nil when unrated.
    public let rating: Rating?
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
    /// Where a backup is taken before every deletion of a Game, List or Playthrough.
    let backups: Backups?

    /// Opens the journal, migrating it as far as it can go: a journal that still has OpenEmu ROMs stays at
    /// `LudeumSchema.lastWithOpenEmu` until `migrate-openemu` has moved them (`needsOpenEmuMigration()`).
    public convenience init(
        directory: URL, clock: TimeSource = SystemTimeSource(), timeZone: TimeZone = .current, backups: Backups? = nil
    ) throws {
        try self.init(directory: directory, clock: clock, timeZone: timeZone, backups: backups, beforeOpenEmuMigration: false)
    }

    /// `beforeOpenEmuMigration` stops at `LudeumSchema.lastWithOpenEmu` whatever the ROMs are, as a journal
    /// with OpenEmu ROMs does.
    init(
        directory: URL, clock: TimeSource = SystemTimeSource(), timeZone: TimeZone = .current, backups: Backups? = nil,
        beforeOpenEmuMigration: Bool
    )
        throws
    {
        self.backups = backups
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var config = Configuration()
        config.foreignKeysEnabled = true
        db = try DatabaseQueue(path: directory.appending(path: "journal.sqlite").path(percentEncoded: false), configuration: config)
        self.clock = clock
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
        let applied = try db.read { try LudeumSchema.migrator.appliedIdentifiers($0) }
        // A journal with data is backed up before a migration changes it; one just made has nothing to lose.
        var backUpFirst = !applied.isEmpty
        if applied.contains(LudeumSchema.withoutOpenEmu) {
            try migrate(upTo: nil, backingUpFirst: &backUpFirst)
        } else {
            try migrate(upTo: LudeumSchema.lastWithOpenEmu, backingUpFirst: &backUpFirst)
        }
        if !beforeOpenEmuMigration { try completeMigrations(backingUpFirst: &backUpFirst) }
    }

    /// Takes the migrations held back while ROMs were OpenEmu's, once none are. Does nothing while some are.
    /// `migrate-openemu` calls it straight after its own backup, so it takes none.
    func completeMigrations() throws {
        var backUpFirst = false
        try completeMigrations(backingUpFirst: &backUpFirst)
    }

    private func completeMigrations(backingUpFirst backUpFirst: inout Bool) throws {
        let hasOpenEmuROMs = try db.read { db in
            try db.columns(in: "rom").contains { $0.name == "openEmuPk" }
                && Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM rom WHERE openEmuPk IS NOT NULL)")!
        }
        if !hasOpenEmuROMs { try migrate(upTo: nil, backingUpFirst: &backUpFirst) }
    }

    /// Migrates the journal up to `target` (nil for every migration). With `backUpFirst`, a journal with a migration
    /// still to take is backed up before it runs, once: `backUpFirst` is cleared once the backup is taken.
    private func migrate(upTo target: String?, backingUpFirst backUpFirst: inout Bool) throws {
        let migrator = LudeumSchema.migrator
        let wanted =
            target.flatMap { t in migrator.migrations.firstIndex(of: t).map { migrator.migrations.prefix(through: $0) } }
            ?? migrator.migrations[...]
        let pending = try db.read { db in try !Set(wanted).isSubset(of: migrator.appliedIdentifiers(db)) }
        if backUpFirst, pending {
            try backups?.backUp(self, operation: .beforeSchemaMigration)
            backUpFirst = false
        }
        if let target { try migrator.migrate(db, upTo: target) } else { try migrator.migrate(db) }
    }

    /// The journal still has OpenEmu ROMs: `migrate-openemu` hasn't moved them into ROM folders yet. Until it has,
    /// Import is refused.
    public func needsOpenEmuMigration() throws -> Bool {
        try db.read { try !LudeumSchema.migrator.hasCompletedMigrations($0) }
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
                        r.rating AS currentRating
                    FROM game g
                    LEFT JOIN ratingEntry r ON r.id = (
                        SELECT id FROM ratingEntry WHERE gameId = g.id \(Self.ratingOrder) LIMIT 1)
                    WHERE g.id = ?
                    """, arguments: [id])
            guard let row else { throw LudeumError.gameNotFound }
            return Game(
                id: row["id"], platformId: row["platformId"], igdbGameId: row["igdbGameId"],
                name: row["displayName"], childhood: row["childhood"],
                intent: (row["intent"] as String?).flatMap(Intent.init(rawValue:)),
                intentSetAt: row["intentSetAt"],
                rating: (row["currentRating"] as Int?).flatMap { Rating(tenths: $0) })
        }
    }
}
