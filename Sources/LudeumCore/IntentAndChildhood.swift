import Foundation
import GRDB

extension LudeumStore {
    /// Sets or (with nil) clears the Intent. A new value records when it was set;
    /// setting the same value again does nothing.
    public func setIntent(_ game: GameID, _ intent: Intent?) throws {
        let now = clock.now()
        try db.write { db in
            try db.execute(
                sql: "UPDATE game SET intent = ?, intentSetAt = ? WHERE id = ? AND intent IS NOT ?",
                arguments: [intent?.rawValue, intent == nil ? nil : now, game, intent?.rawValue])
        }
    }

    /// Intent brought over from OpenEmu, which is undated.
    public func importIntent(_ game: GameID, _ intent: Intent) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE game SET intent = ?, intentSetAt = NULL WHERE id = ?", arguments: [intent.rawValue, game])
        }
    }

    public func setChildhood(_ game: GameID, _ childhood: Bool) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE game SET childhood = ? WHERE id = ?", arguments: [childhood, game])
        }
    }
}
