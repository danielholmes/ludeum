import Foundation
import GRDB

/// How a Playthrough ended. No Outcome means it's still in progress.
public enum Outcome: String, Sendable {
    case finished, dropped
}

/// A Playthrough's fields, for adding or editing one.
public struct PlaythroughDraft: Sendable, Equatable {
    public var start: PartialDate
    public var end: PartialDate?
    public var outcome: Outcome?
    public var notes: String?
    public var version: String?
    public var playedVia: String?

    public init(
        start: PartialDate, end: PartialDate? = nil, outcome: Outcome? = nil,
        notes: String? = nil, version: String? = nil, playedVia: String? = nil
    ) {
        self.start = start
        self.end = end
        self.outcome = outcome
        self.notes = notes
        self.version = version
        self.playedVia = playedVia
    }

    /// The end can't come before the start, though a less precise date that contains the
    /// other is fine (start `2024-03`, end `2024`).
    func validate() throws {
        if let end, end < start, !end.contains(start) { throw LudeumError.endBeforeStart }
    }
}

public struct Playthrough: Sendable, Equatable {
    public let id: Int64
    public let draft: PlaythroughDraft

    public init(id: Int64, _ draft: PlaythroughDraft) {
        self.id = id
        self.draft = draft
    }
}

extension LudeumStore {
    @discardableResult
    public func addPlaythrough(_ game: GameID, _ draft: PlaythroughDraft) throws -> Int64 {
        try draft.validate()
        return try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO playthrough (gameId, start, end, outcome, notes, version, playedVia)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [game] + Self.arguments(draft))
            return db.lastInsertedRowID
        }
    }

    public func updatePlaythrough(_ id: Int64, _ draft: PlaythroughDraft) throws {
        try draft.validate()
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE playthrough SET start = ?, end = ?, outcome = ?, notes = ?, version = ?, playedVia = ?
                    WHERE id = ?
                    """,
                arguments: Self.arguments(draft) + [id])
        }
    }

    public func deletePlaythrough(_ id: Int64) throws {
        try backups?.backUp(self, operation: .beforeDelete)
        try db.write { db in
            try db.execute(sql: "DELETE FROM playthrough WHERE id = ?", arguments: [id])
        }
    }

    /// A Game's Playthroughs, by start date, then as added.
    public func playthroughs(_ game: GameID) throws -> [Playthrough] {
        try db.read { db in
            try Row.fetchAll(
                db, sql: "SELECT * FROM playthrough WHERE gameId = ? ORDER BY start, id", arguments: [game]
            ).map { row in
                Playthrough(
                    id: row["id"],
                    PlaythroughDraft(
                        start: PartialDate(row["start"])!,
                        end: (row["end"] as String?).flatMap(PartialDate.init),
                        outcome: (row["outcome"] as String?).flatMap(Outcome.init(rawValue:)),
                        notes: row["notes"], version: row["version"], playedVia: row["playedVia"]))
            }
        }
    }

    private static func arguments(_ d: PlaythroughDraft) -> StatementArguments {
        [d.start.text, d.end?.text, d.outcome?.rawValue, d.notes, d.version, d.playedVia]
    }
}
