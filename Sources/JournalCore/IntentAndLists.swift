import Foundation
import GRDB

/// A List: a named, unordered group of Games that I curate.
public struct GameList: Sendable, Equatable {
    public let id: Int64
    public let name: String
}

extension JournalStore {
    // MARK: Intent and Childhood

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

    // MARK: Lists

    @discardableResult
    public func createList(_ name: String) throws -> Int64 {
        try writeListName { db in
            try db.execute(sql: "INSERT INTO list (name) VALUES (?)", arguments: [name])
            return db.lastInsertedRowID
        }
    }

    public func renameList(_ list: Int64, _ name: String) throws {
        try writeListName { db in
            try db.execute(sql: "UPDATE list SET name = ? WHERE id = ?", arguments: [name, list])
        }
    }

    /// Deletes the List. Its Games are untouched.
    public func deleteList(_ list: Int64) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM list WHERE id = ?", arguments: [list])
        }
    }

    public func addToList(_ list: Int64, _ game: GameID) throws {
        try db.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO listGame (listId, gameId) VALUES (?, ?)", arguments: [list, game])
        }
    }

    public func removeFromList(_ list: Int64, _ game: GameID) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM listGame WHERE listId = ? AND gameId = ?", arguments: [list, game])
        }
    }

    /// Every List by name, or only those holding `game`.
    public func lists(containing game: GameID? = nil) throws -> [GameList] {
        try db.read { db in
            let sql =
                game == nil
                ? "SELECT id, name FROM list ORDER BY name"
                : "SELECT id, name FROM list JOIN listGame ON listId = id WHERE gameId = ? ORDER BY name"
            return try Row.fetchAll(db, sql: sql, arguments: game.map { [$0] } ?? []).map {
                GameList(id: $0["id"], name: $0["name"])
            }
        }
    }

    public func games(in list: Int64) throws -> [GameID] {
        try db.read { db in
            try GameID.fetchAll(db, sql: "SELECT gameId FROM listGame WHERE listId = ? ORDER BY gameId", arguments: [list])
        }
    }

    private func writeListName<T>(_ body: (Database) throws -> T) throws -> T {
        do {
            return try db.write(body)
        } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
            throw JournalError.listNameTaken
        }
    }
}
