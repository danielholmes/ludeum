import Foundation
import GRDB

extension LudeumStore {
    /// Records an OpenEmu ROM Matched by hand to `game`. Real ROM ingest arrives with Import.
    public func recordROM(
        game: GameID, openEmuPk: Int64, md5: String, fileName: String, missing: Bool
    ) throws {
        let now = clock.now()
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO rom (openEmuPk, md5, fileName, platformId, missing, gameId, matchKind, matchedAt)
                    SELECT ?, ?, ?, platformId, ?, id, 'manual', ? FROM game WHERE id = ?
                    """, arguments: [openEmuPk, md5, fileName, missing, now, game])
        }
    }

    /// Hard-deletes a Game with all its journal data and its missing ROMs.
    /// Refused while it has a present ROM: those are removed in OpenEmu first.
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
