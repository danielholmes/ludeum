import Foundation
import GRDB

/// A List: a group of Games I put together by hand, for a reason of my own that nothing about the Games says (ADR 0039).
/// `GameList` in code, as `List` is SwiftUI's.
public struct GameList: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let name: String
    /// How many Games are in it.
    public let games: Int

    public init(id: Int64, name: String, games: Int) {
        self.id = id
        self.name = name
        self.games = games
    }
}

extension LudeumStore {
    /// Every List, by name.
    public func lists() throws -> [GameList] {
        try db.read { db in try Self.lists(db, where: "1", []) }
    }

    /// The Lists a Game is in, by name.
    public func lists(containing game: GameID) throws -> [GameList] {
        try db.read { db in
            try Self.lists(db, where: "EXISTS (SELECT 1 FROM listGame WHERE listId = l.id AND gameId = ?)", [game])
        }
    }

    private static func lists(_ db: Database, where condition: String, _ arguments: StatementArguments) throws -> [GameList] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT l.id, l.name, (SELECT COUNT(*) FROM listGame WHERE listId = l.id) AS games
                FROM list l WHERE \(condition) ORDER BY l.name COLLATE NOCASE
                """,
            arguments: arguments
        ).map { GameList(id: $0["id"], name: $0["name"], games: $0["games"]) }
    }

    /// A new, empty List. Its name is trimmed, and no two Lists share one, ignoring case.
    @discardableResult
    public func createList(named name: String) throws -> GameList {
        let name = try Self.validListName(name)
        return try write(uniqueViolation: .listNameTaken) { db in
            try db.execute(sql: "INSERT INTO list (name) VALUES (?)", arguments: [name])
            return GameList(id: db.lastInsertedRowID, name: name, games: 0)
        }
    }

    /// Gives a List a new name, under the same rules as a new List's.
    public func renameList(_ id: Int64, to name: String) throws {
        let name = try Self.validListName(name)
        try write(uniqueViolation: .listNameTaken) { db in
            try db.execute(sql: "UPDATE list SET name = ? WHERE id = ?", arguments: [name, id])
        }
    }

    private static func validListName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LudeumError.nameRequired }
        return name
    }

    /// Deletes a List. Its Games stay.
    public func deleteList(_ id: Int64) throws {
        try backups?.backUp(self, operation: .beforeDelete)
        try db.write { db in try db.execute(sql: "DELETE FROM list WHERE id = ?", arguments: [id]) }
    }

    /// Puts a Game in a List, where it may be already. A Bundle isn't a Game, and a List could never show one (ADR 0016).
    public func addGame(_ game: GameID, toList list: Int64) throws {
        try db.write { db in
            guard let isBundle = try Bool.fetchOne(db, sql: "SELECT bundle FROM game WHERE id = ?", arguments: [game]) else {
                throw LudeumError.gameNotFound
            }
            guard !isBundle else { throw LudeumError.cantBeInList }
            try db.execute(sql: "INSERT OR IGNORE INTO listGame (listId, gameId) VALUES (?, ?)", arguments: [list, game])
        }
    }

    /// Takes a Game out of a List.
    public func removeGame(_ game: GameID, fromList list: Int64) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM listGame WHERE listId = ? AND gameId = ?", arguments: [list, game])
        }
    }
}
