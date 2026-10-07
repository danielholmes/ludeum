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
    /// Its subfolder holds its Discs but no playlist, so Play can't open them all.
    public var needsPlaylist = false
    /// What it says as a Copy: its Regions, and where, when and for how much it was acquired.
    public var details = CopyDetails()

    /// The subfolder it's kept in, named after it, when it's a ROM folder subfolder ROM; nil for a loose file
    /// or an archive.
    public var subfolder: String? { fileName.hasPrefix(folderName + "/") ? folderName : nil }
}

/// What deleting a Game takes with it, for the confirmation.
public struct DeletionSummary: Sendable, Equatable {
    public let ratingEntries: Int
    public let playthroughs: Int
    public let lists: Int
    /// A Game with any Copy can't be deleted: its ROMs, present or missing, and its hand-recorded Copies are deleted first.
    public let roms: Int
    public let copies: Int
    public var canDelete: Bool { roms == 0 && copies == 0 }

    public init(ratingEntries: Int, playthroughs: Int, lists: Int, roms: Int, copies: Int) {
        self.ratingEntries = ratingEntries
        self.playthroughs = playthroughs
        self.lists = lists
        self.roms = roms
        self.copies = copies
    }
}

extension LudeumStore {
    /// The name I typed over IGDB's (or the Game's own), if any.
    public func nameOverride(_ game: GameID) throws -> String? {
        try db.read { db in try String.fetchOne(db, sql: "SELECT nameOverride FROM game WHERE id = ?", arguments: [game]) }
    }

    /// The Game's ROMs, present first, then by file name.
    public func roms(of game: GameID) throws -> [LudeumROM] {
        try roms(where: "r.gameId = ?", arguments: [game])
    }

    /// A ROM, Matched or not, e.g. an unmatched one to Play from the Review queue.
    public func rom(_ id: Int64) throws -> LudeumROM? {
        try roms(where: "r.id = ?", arguments: [id]).first
    }

    private func roms(where condition: String, arguments: StatementArguments) throws -> [LudeumROM] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT r.id, \(Self.folderNameSQL) AS folderName, r.platformId, r.archived, r.fileName,
                        COALESCE(r.name, r.fileName) AS displayName, r.version, r.discNumber, r.missing,
                        \(try Self.hasNeedsPlaylist(db) ? "r.needsPlaylist" : "0") AS needsPlaylist,
                        \(try Self.hasCopyDetails(db) ? "r.regions, r.acquiredOn, r.acquiredFrom, r.price, r.currency" : "NULL AS regions, NULL AS acquiredOn, NULL AS acquiredFrom, NULL AS price, NULL AS currency")
                    FROM rom r
                    WHERE \(condition)
                    ORDER BY r.missing, r.fileName COLLATE NOCASE
                    """, arguments: arguments
            ).map { row in
                let fileName: String = row["fileName"]
                let parsed = ROMName((fileName as NSString).deletingPathExtension)
                return LudeumROM(
                    id: row["id"], folderName: row["folderName"], platformId: row["platformId"],
                    fileName: fileName,
                    name: row["displayName"], version: row["version"] ?? parsed.version, disc: row["discNumber"] ?? parsed.disc,
                    missing: row["missing"], archived: row["archived"], needsPlaylist: row["needsPlaylist"],
                    details: Self.details(row))
            }
        }
    }

    /// Whether the journal has `rom.needsPlaylist`: one waiting for `migrate-openemu` is held before it, with no ROM
    /// that could need a playlist.
    static func hasNeedsPlaylist(_ db: Database) throws -> Bool {
        try db.columns(in: "rom").contains { $0.name == "needsPlaylist" }
    }

    /// Whether the journal's ROMs have Copy details (`v22`), which one waiting for `migrate-openemu` doesn't yet.
    static func hasCopyDetails(_ db: Database) throws -> Bool {
        try db.columns(in: "rom").contains { $0.name == "regions" }
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
                roms: try count("SELECT COUNT(*) FROM rom WHERE gameId = ?"),
                copies: try count("SELECT COUNT(*) FROM copy WHERE gameId = ?"))
        }
    }
}
