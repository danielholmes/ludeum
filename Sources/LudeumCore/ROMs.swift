import Foundation
import GRDB

extension LudeumStore {
    /// Records a ROM in its Game's Platform's ROM folder, Matched by hand to `game`. It's known by its file
    /// name without the extension, and its Regions are read from the name. New ROMs otherwise arrive with an Import.
    public func recordROM(game: GameID, fileName: String, missing: Bool) throws {
        let now = clock.now()
        let name = (fileName as NSString).deletingPathExtension
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO rom (folderName, fileName, name, regions, platformId, missing, gameId, matchKind, matchedAt)
                    SELECT ?, ?, ?, ?, platformId, ?, id, 'manual', ? FROM game WHERE id = ?
                    """, arguments: [name, fileName, name, Regions.encode(ROMName(name).regionNames), missing, now, game])
        }
    }

    /// The Game the ROM is Matched to; nil once it's gone from the journal.
    public func game(ofROM rom: Int64) throws -> GameID? {
        try db.read { db in try GameID.fetchOne(db, sql: "SELECT gameId FROM rom WHERE id = ?", arguments: [rom]) }
    }

    /// Hard-deletes a Game with all its journal data. Refused while it has any Copy, a ROM (present or missing) or a
    /// hand-recorded one: those are deleted first, so only a plain journal entry can go.
    public func deleteGame(_ game: GameID) throws {
        // Refuse before backing up, so a refused deletion leaves no backup behind.
        if try db.read({ try hasCopies($0, game) }) { throw LudeumError.gameHasCopies }
        try backups?.backUp(self, operation: .beforeDelete)
        try db.write { db in
            if try hasCopies(db, game) { throw LudeumError.gameHasCopies }
            try db.execute(sql: "DELETE FROM game WHERE id = ?", arguments: [game])
        }
    }

    /// Deletes a ROM, Matched or not: a present one's files go to the Trash first (its subfolder whole, with any `.7z` or
    /// Compacted copy), and a missing one just leaves the journal, with its Copy details either way. If its file comes
    /// back, the next Import records it afresh. Refused, with nothing sent to the Trash, when it's present but its files
    /// aren't in its ROM folder; if sending them fails part-way, the journal sees what's left, and the ROM goes only if
    /// all of it reached the Trash. Refused, with nothing sent to the Trash, while a Playthrough was played on it.
    public func deleteROM(
        _ rom: Int64, romFolders: [ROMFolder],
        moveToTrash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) throws {
        guard
            let row = try db.read({ db in
                try Self.checkNotPlayedOn(db, roms: [rom])
                return try Row.fetchOne(db, sql: "SELECT folderName, missing, platformId FROM rom WHERE id = ?", arguments: [rom])
            })
        else { return }
        let delete = { try self.db.write { db in try db.execute(sql: "DELETE FROM rom WHERE id = ?", arguments: [rom]) } }
        if row["missing"] { return try delete() }
        guard let folder = romFolders.first(where: { $0.platformId == row["platformId"] }) else { throw ReviewError.noROMFolder }
        guard let file = try folder.rom(named: row["folderName"]) else { throw ReviewError.romFilesNotFound }
        try backups?.backUp(self, operation: .beforeDelete)
        do {
            for trashed in try folder.trashItems(of: file) { try moveToTrash(trashed) }
        } catch {
            // Whatever reached the Trash before the failure, the journal sees what's left; all of it there, it's deleted.
            try? checkROMAgain(rom, in: folder)
            try? db.write { db in try db.execute(sql: "DELETE FROM rom WHERE id = ? AND missing", arguments: [rom]) }
            throw error
        }
        try delete()
    }

    /// Deletes every missing ROM of the Game at once, as `deleteROM(_:romFolders:)` does each; its present ROMs stay.
    /// Refused, deleting none, while a Playthrough was played on any of them.
    public func deleteMissingROMs(of game: GameID) throws {
        try db.write { db in
            try Self.checkNotPlayedOn(db, roms: try Self.missingROMs(db, of: game))
            try db.execute(sql: "DELETE FROM rom WHERE gameId = ? AND missing", arguments: [game])
        }
    }

    /// The Game's missing ROMs, but `except`.
    static func missingROMs(_ db: Database, of game: GameID, except: Int64? = nil) throws -> [Int64] {
        try Int64.fetchAll(
            db, sql: "SELECT id FROM rom WHERE gameId = ? AND missing AND id IS NOT ?", arguments: [game, except])
    }

    private func hasCopies(_ db: Database, _ game: GameID) throws -> Bool {
        try Bool.fetchOne(
            db, sql: "SELECT EXISTS (SELECT 1 FROM rom WHERE gameId = ?) OR EXISTS (SELECT 1 FROM copy WHERE gameId = ?)",
            arguments: [game, game])!
    }
}
