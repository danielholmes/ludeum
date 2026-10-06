import Foundation
import GRDB

extension LudeumStore {
    /// Records a ROM in its Game's Platform's ROM folder, Matched by hand to `game`. It's known by its file
    /// name without the extension. New ROMs otherwise arrive with an Import.
    public func recordROM(game: GameID, fileName: String, missing: Bool) throws {
        let now = clock.now()
        let name = (fileName as NSString).deletingPathExtension
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO rom (folderName, fileName, name, platformId, missing, gameId, matchKind, matchedAt)
                    SELECT ?, ?, ?, platformId, ?, id, 'manual', ? FROM game WHERE id = ?
                    """, arguments: [name, fileName, name, missing, now, game])
        }
    }

    /// Hard-deletes a Game with all its journal data and its missing ROMs.
    /// Refused while it has a present ROM: those are moved out of their ROM folder first.
    public func deleteGame(_ game: GameID) throws {
        // Refuse before backing up, so a refused deletion leaves no backup behind.
        if try db.read({ try hasPresentROMs($0, game) }) { throw LudeumError.gameHasPresentROMs }
        try backups?.backUp(self, operation: .beforeDelete)
        try db.write { db in
            if try hasPresentROMs(db, game) { throw LudeumError.gameHasPresentROMs }
            try db.execute(sql: "DELETE FROM game WHERE id = ?", arguments: [game])
        }
    }

    private func hasPresentROMs(_ db: Database, _ game: GameID) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM rom WHERE gameId = ? AND NOT missing)", arguments: [game])!
    }
}
