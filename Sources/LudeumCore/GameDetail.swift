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
    /// Its Serials, once read off its Discs (ADR 0021): each Disc's in Disc order, nil for one with none.
    public var serials: Serials = .notRead
    /// The Disc a multi-disc ROM last started on, by its number; nil before its first Play (ADR 0026).
    public var lastDisc: Int?

    /// The subfolder it's kept in, named after it, when it's a ROM folder subfolder ROM; nil for a loose file
    /// or an archive.
    public var subfolder: String? { fileName.hasPrefix(folderName + "/") ? folderName : nil }
}

/// What deleting a Game takes with it, for the confirmation.
public struct DeletionSummary: Sendable, Equatable {
    public let ratingEntries: Int
    public let playthroughs: Int
    /// A Game with any Copy can't be deleted: its ROMs, present or missing, and its hand-recorded Copies are deleted first.
    public let roms: Int
    public let copies: Int
    /// Its Attachments, whose files go to the Trash with it.
    public let attachments: Int
    /// The Bundles containing it: a Game in one can't be deleted until it leaves.
    public let containingBundles: Int
    public var canDelete: Bool { roms == 0 && copies == 0 && containingBundles == 0 }

    public init(ratingEntries: Int, playthroughs: Int, roms: Int, copies: Int, attachments: Int, containingBundles: Int) {
        self.containingBundles = containingBundles
        self.ratingEntries = ratingEntries
        self.playthroughs = playthroughs
        self.roms = roms
        self.copies = copies
        self.attachments = attachments
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

    /// Every ROM of a Platform, Matched or not, present first, then by file name.
    public func roms(onPlatform platformId: Int64) throws -> [LudeumROM] {
        try roms(where: "r.platformId = ?", arguments: [platformId])
    }

    func roms(where condition: String, arguments: StatementArguments) throws -> [LudeumROM] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT r.id, r.folderName, r.platformId, r.archived, r.fileName,
                        COALESCE(r.name, r.fileName) AS displayName, r.version, r.discNumber, r.missing,
                        r.needsPlaylist, r.regions, r.acquiredOn, r.acquiredFrom, r.price, r.currency, r.notes, r.serials,
                        r.serialsLookedUp, r.lastDisc
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
                    details: Self.details(row), serials: Serials(row), lastDisc: row["lastDisc"])
            }
        }
    }

    /// Remembers the Disc a multi-disc ROM's Play started on, to start on next time: the one journal change a Play makes.
    /// Whether it's a different one from before.
    @discardableResult
    public func setLastDisc(_ start: Play.DiscStart) throws -> Bool {
        try db.write { db in
            try db.execute(
                sql: "UPDATE rom SET lastDisc = ? WHERE id = ? AND lastDisc IS NOT ?", arguments: [start.disc, start.rom, start.disc])
            return db.changesCount > 0
        }
    }

    public func deletionSummary(_ game: GameID) throws -> DeletionSummary {
        try db.read { db in
            func count(_ sql: String) throws -> Int { try Int.fetchOne(db, sql: sql, arguments: [game]) ?? 0 }
            return DeletionSummary(
                ratingEntries: try count("SELECT COUNT(*) FROM ratingEntry WHERE gameId = ?"),
                playthroughs: try count("SELECT COUNT(*) FROM playthrough WHERE gameId = ?"),
                roms: try count("SELECT COUNT(*) FROM rom WHERE gameId = ?"),
                copies: try count("SELECT COUNT(*) FROM copy WHERE gameId = ?"),
                attachments: try count("SELECT COUNT(*) FROM attachment WHERE gameId = ?"),
                containingBundles: try count("SELECT COUNT(*) FROM bundleGame WHERE gameId = ?"))
        }
    }
}
