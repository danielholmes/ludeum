import Foundation
import GRDB

/// A ROM as Game detail shows it, with its latest Activity.
public struct JournalROM: Sendable, Equatable, Identifiable {
    public let id: Int64
    /// The ROM's `Z_PK` in OpenEmu's library.
    public let openEmuPk: Int64
    public let fileName: String
    /// OpenEmu's name for it, or the file name when unknown.
    public let name: String
    /// The ROM's Version text: stored by Import, else read from its name.
    public let version: String
    public let disc: Int?
    public let missing: Bool
    public let playCount: Int
    public let lastPlayedAt: Date?
    public let playTimeSeconds: Double
}

/// A Game's Activity: play stats summed across its ROMs, from each ROM's latest snapshot.
public struct Activity: Sendable, Equatable {
    public let playCount: Int
    public let lastPlayedAt: Date?
    public let playTimeSeconds: Double
}

/// What deleting a Game takes with it, for the confirmation.
public struct DeletionSummary: Sendable, Equatable {
    public let ratingEntries: Int
    public let playthroughs: Int
    public let lists: Int
    public let missingROMs: Int
    /// A Game with present ROMs can't be deleted: they're removed in OpenEmu first.
    public let presentROMs: Int
    public var canDelete: Bool { presentROMs == 0 }

    public init(ratingEntries: Int, playthroughs: Int, lists: Int, missingROMs: Int, presentROMs: Int) {
        self.ratingEntries = ratingEntries
        self.playthroughs = playthroughs
        self.lists = lists
        self.missingROMs = missingROMs
        self.presentROMs = presentROMs
    }
}

extension JournalStore {
    /// The name I typed over IGDB's (or the Game's own), if any.
    public func nameOverride(_ game: GameID) throws -> String? {
        try db.read { db in try String.fetchOne(db, sql: "SELECT nameOverride FROM game WHERE id = ?", arguments: [game]) }
    }

    /// The Game's ROMs, present first, then by file name.
    public func roms(of game: GameID) throws -> [JournalROM] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT r.id, r.openEmuPk, r.fileName, COALESCE(r.name, r.fileName) AS displayName, r.version, r.discNumber, r.missing,
                        a.playCount, a.lastPlayedAt, a.playTimeSeconds
                    FROM rom r
                    LEFT JOIN activitySnapshot a ON a.romId = r.id
                        AND a.importId = (SELECT MAX(importId) FROM activitySnapshot WHERE romId = r.id)
                    WHERE r.gameId = ?
                    ORDER BY r.missing, r.fileName COLLATE NOCASE
                    """, arguments: [game]
            ).map { row in
                let fileName: String = row["fileName"]
                let parsed = ROMName((fileName as NSString).deletingPathExtension)
                return JournalROM(
                    id: row["id"], openEmuPk: row["openEmuPk"], fileName: fileName, name: row["displayName"], version: row["version"] ?? parsed.version,
                    disc: row["discNumber"] ?? parsed.disc, missing: row["missing"], playCount: row["playCount"] ?? 0,
                    lastPlayedAt: row["lastPlayedAt"], playTimeSeconds: row["playTimeSeconds"] ?? 0)
            }
        }
    }

    public func activity(of game: GameID) throws -> Activity {
        let roms = try roms(of: game)
        return Activity(
            playCount: roms.map(\.playCount).reduce(0, +), lastPlayedAt: roms.compactMap(\.lastPlayedAt).max(),
            playTimeSeconds: roms.map(\.playTimeSeconds).reduce(0, +))
    }

    /// Version suggestions for a Playthrough: the Game's ROMs' Versions, without repeats.
    public func versionSuggestions(for game: GameID) throws -> [String] {
        var seen: [String] = []
        for rom in try roms(of: game) where !rom.version.isEmpty && !seen.contains(rom.version) { seen.append(rom.version) }
        return seen
    }

    /// "Played via" suggestions: OpenEmu for a Game with ROMs, then every value I've used, alphabetically.
    public func playedViaSuggestions(for game: GameID) throws -> [String] {
        let openEmu = try roms(of: game).isEmpty ? [] : ["OpenEmu"]
        return try openEmu
            + db.read { db in
                try String.fetchAll(
                    db,
                    sql:
                        "SELECT DISTINCT playedVia FROM playthrough WHERE playedVia IS NOT NULL AND playedVia != '' ORDER BY playedVia COLLATE NOCASE"
                )
            }
    }

    public func deletionSummary(_ game: GameID) throws -> DeletionSummary {
        try db.read { db in
            func count(_ sql: String) throws -> Int { try Int.fetchOne(db, sql: sql, arguments: [game]) ?? 0 }
            return DeletionSummary(
                ratingEntries: try count("SELECT COUNT(*) FROM ratingEntry WHERE gameId = ?"),
                playthroughs: try count("SELECT COUNT(*) FROM playthrough WHERE gameId = ?"),
                lists: try count("SELECT COUNT(*) FROM listGame WHERE gameId = ?"),
                missingROMs: try count("SELECT COUNT(*) FROM rom WHERE gameId = ? AND missing"),
                presentROMs: try count("SELECT COUNT(*) FROM rom WHERE gameId = ? AND NOT missing"))
        }
    }
}
