import Foundation
import GRDB

/// A Player's badge colour: hues spread around the wheel, each dark enough for white initials.
public enum PlayerColour: String, Sendable, CaseIterable {
    case red, orange, amber, lime, green, teal, sky, blue, violet, purple, pink, brown
}

/// A Player's fields, for adding or editing one.
public struct PlayerDraft: Sendable, Hashable {
    public var firstName: String
    public var lastName: String
    public var colour: PlayerColour

    public init(firstName: String, lastName: String, colour: PlayerColour) {
        self.firstName = firstName
        self.lastName = lastName
        self.colour = colour
    }

    /// The badge's text: the first letter of each name.
    public var initials: String { (firstName.prefix(1) + lastName.prefix(1)).uppercased() }

    public var fullName: String { "\(firstName) \(lastName)" }

    /// Both names, trimmed and required.
    func validated() throws -> PlayerDraft {
        var d = self
        d.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        d.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.firstName.isEmpty || d.lastName.isEmpty { throw LudeumError.nameRequired }
        return d
    }
}

/// Someone besides me who took part in a Playthrough.
public struct Player: Sendable, Equatable, Identifiable, Hashable {
    public let id: Int64
    public let draft: PlayerDraft

    public init(id: Int64, _ draft: PlayerDraft) {
        self.id = id
        self.draft = draft
    }
}

extension LudeumStore {
    @discardableResult
    public func addPlayer(_ draft: PlayerDraft) throws -> Int64 {
        let d = try draft.validated()
        return try write(uniqueViolation: .playerNameTaken) { db in
            try db.execute(
                sql: "INSERT INTO player (firstName, lastName, colour) VALUES (?, ?, ?)",
                arguments: [d.firstName, d.lastName, d.colour.rawValue])
            return db.lastInsertedRowID
        }
    }

    public func updatePlayer(_ id: Int64, _ draft: PlayerDraft) throws {
        let d = try draft.validated()
        try write(uniqueViolation: .playerNameTaken) { db in
            try db.execute(
                sql: "UPDATE player SET firstName = ?, lastName = ?, colour = ? WHERE id = ?",
                arguments: [d.firstName, d.lastName, d.colour.rawValue, id])
        }
    }

    /// Deletes the Player, taking them off their Playthroughs.
    public func deletePlayer(_ id: Int64) throws {
        try backups?.backUp(self, operation: .beforeDelete)
        try db.write { db in
            try db.execute(sql: "DELETE FROM player WHERE id = ?", arguments: [id])
        }
    }

    /// How many Playthroughs the Player is on, for confirming a delete.
    public func playthroughCount(with player: Int64) throws -> Int {
        try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM playthroughPlayer WHERE playerId = ?", arguments: [player]) ?? 0
        }
    }

    /// The colour a new Player starts with: the palette's least used, earliest first.
    public func nextPlayerColour() throws -> PlayerColour {
        let used = try players().map(\.draft.colour)
        return PlayerColour.allCases.min { a, b in used.count { $0 == a } < used.count { $0 == b } }!
    }

    /// Every Player, by first then last name.
    public func players() throws -> [Player] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM player ORDER BY firstName COLLATE NOCASE, lastName COLLATE NOCASE")
                .map(Self.player)
        }
    }

    static func player(_ row: Row) -> Player {
        Player(
            id: row["id"],
            PlayerDraft(firstName: row["firstName"], lastName: row["lastName"], colour: PlayerColour(rawValue: row["colour"]) ?? .blue))
    }
}
