import Foundation
import GRDB

// `heldOpenEmuData`: an unmatched ROM's OpenEmu collections and `_Current` start date answer, captured by the
// first Import from OpenEmu and applied when the Review queue resolves the ROM. It is journal data now, not a
// link to OpenEmu.

/// OpenEmu's special collections, which become journal data rather than Lists.
enum SpecialCollection {
    static let backlog = "_TODO"
    static let upNext = "_TODO Next"
    static let current = "_Current"
    static let completed = "_Completed"
    static let childhood = "_Childhood Played"
    static let all: Set<String> = [backlog, upNext, current, completed, childhood]
}

extension LudeumStore {
    /// Applies the OpenEmu data held for a ROM the Review queue resolves: the collections as Intent (undated,
    /// never over Intent it has), Childhood, an in-progress Playthrough from a `_Current` start date, and Lists.
    static func applyOpenEmuData(_ db: Database, game: GameID, collections: Set<String>, start: PartialDate?) throws {
        let intent: Intent? =
            collections.contains(SpecialCollection.upNext) ? .upNext : collections.contains(SpecialCollection.backlog) ? .backlog : nil
        if let intent {
            try db.execute(sql: "UPDATE game SET intent = ? WHERE id = ? AND intent IS NULL", arguments: [intent.rawValue, game])
        }
        if collections.contains(SpecialCollection.childhood) {
            try db.execute(sql: "UPDATE game SET childhood = 1 WHERE id = ?", arguments: [game])
        }
        if collections.contains(SpecialCollection.current), let start,
            try !Bool.fetchOne(
                db, sql: "SELECT EXISTS (SELECT 1 FROM playthrough WHERE gameId = ? AND outcome IS NULL)", arguments: [game])!
        {
            try db.execute(sql: "INSERT INTO playthrough (gameId, start) VALUES (?, ?)", arguments: [game, start.text])
        }
        for name in collections.subtracting(SpecialCollection.all).sorted() {
            try db.execute(sql: "INSERT OR IGNORE INTO list (name) VALUES (?)", arguments: [name])
            try db.execute(
                sql: "INSERT OR IGNORE INTO listGame (listId, gameId) SELECT id, ? FROM list WHERE name = ?", arguments: [game, name])
        }
    }
}
