import Foundation
import GRDB

extension JournalStore {
    /// Records an OpenEmu ROM Matched by hand to `game`. Real ROM ingest arrives with Import.
    public func recordROM(
        game: GameID, openEmuPk: Int64, md5: String, fileName: String, systemId: String, missing: Bool
    ) throws {
        let now = clock.now()
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO rom (openEmuPk, md5, fileName, systemId, missing, gameId, matchKind, matchedAt)
                    VALUES (?, ?, ?, ?, ?, ?, 'manual', ?)
                    """, arguments: [openEmuPk, md5, fileName, systemId, missing, game, now])
        }
    }

    /// Hard-deletes a Game with all its journal data and its missing ROMs.
    /// Refused while it has a present ROM: those are removed in OpenEmu first.
    public func deleteGame(_ game: GameID) throws {
        try db.write { db in
            let present = try Bool.fetchOne(
                db, sql: "SELECT EXISTS (SELECT 1 FROM rom WHERE gameId = ? AND NOT missing)", arguments: [game])!
            if present { throw JournalError.gameHasPresentROMs }
            try db.execute(sql: "DELETE FROM game WHERE id = ?", arguments: [game])
        }
    }
}
