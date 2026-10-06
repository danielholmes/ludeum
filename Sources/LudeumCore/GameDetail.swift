import Foundation
import GRDB

/// A ROM as Game detail shows it.
public struct LudeumROM: Sendable, Equatable, Identifiable {
    public let id: Int64
    /// Its name in its Platform's ROM folder: its file's without the extension, or its subfolder's.
    public let folderName: String
    public let platformId: Int64
    public let fileName: String
    /// Its name as shown: from its file name, else the file name.
    public let name: String
    /// The ROM's Version text: stored by Import, else read from its name.
    public let version: String
    public let disc: Int?
    public let missing: Bool
    /// In its ROM folder, but only as a `.7z`: present, but not playable until extracted.
    public let archived: Bool
}

/// What deleting a Game takes with it, for the confirmation.
public struct DeletionSummary: Sendable, Equatable {
    public let ratingEntries: Int
    public let playthroughs: Int
    public let lists: Int
    public let missingROMs: Int
    /// A Game with present ROMs can't be deleted: they're moved out of their ROM folder first.
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

extension LudeumStore {
    /// The name I typed over IGDB's (or the Game's own), if any.
    public func nameOverride(_ game: GameID) throws -> String? {
        try db.read { db in try String.fetchOne(db, sql: "SELECT nameOverride FROM game WHERE id = ?", arguments: [game]) }
    }

    /// The Game's ROMs, present first, then by file name.
    public func roms(of game: GameID) throws -> [LudeumROM] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT r.id, \(Self.folderNameSQL) AS folderName, r.platformId, r.archived, r.fileName,
                        COALESCE(r.name, r.fileName) AS displayName, r.version, r.discNumber, r.missing
                    FROM rom r
                    WHERE r.gameId = ?
                    ORDER BY r.missing, r.fileName COLLATE NOCASE
                    """, arguments: [game]
            ).map { row in
                let fileName: String = row["fileName"]
                let parsed = ROMName((fileName as NSString).deletingPathExtension)
                return LudeumROM(
                    id: row["id"], folderName: row["folderName"], platformId: row["platformId"],
                    fileName: fileName,
                    name: row["displayName"], version: row["version"] ?? parsed.version, disc: row["discNumber"] ?? parsed.disc,
                    missing: row["missing"], archived: row["archived"])
            }
        }
    }

    /// A ROM's folder name. Only an OpenEmu ROM waiting for `migrate-openemu` has none: its OpenEmu file name
    /// stands in, which no ROM folder ROM's name has (they have no extension).
    private static let folderNameSQL = "COALESCE(r.folderName, r.fileName)"

    /// Version suggestions for a Playthrough: the Game's ROMs' Versions, without repeats.
    public func versionSuggestions(for game: GameID) throws -> [String] {
        var seen: [String] = []
        for rom in try roms(of: game) where !rom.version.isEmpty && !seen.contains(rom.version) { seen.append(rom.version) }
        return seen
    }

    /// "Played via" suggestions: its Platform's Emulator for a Game with ROMs, then every value I've used, alphabetically.
    public func playedViaSuggestions(for game: GameID) throws -> [String] {
        let emulator = try roms(of: game).isEmpty ? [] : [Emulator.of(platformId: try self.game(game).platformId)?.name].compactMap { $0 }
        let used = try db.read { db in
            try String.fetchAll(
                db,
                sql:
                    "SELECT DISTINCT playedVia FROM playthrough WHERE playedVia IS NOT NULL AND playedVia != '' ORDER BY playedVia COLLATE NOCASE"
            )
        }
        return emulator + used.filter { !emulator.contains($0) }
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
