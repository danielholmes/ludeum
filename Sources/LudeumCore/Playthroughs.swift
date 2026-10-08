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
    /// The Copy it was played on: one of its Game's ROMs or hand-recorded Copies. While it's set, that Copy can't be
    /// deleted or leave the Game.
    public var copy: CopyID?
    /// The ids of who besides me took part; read back in name order. None is Solo.
    public var players: [Int64]

    public init(
        start: PartialDate, end: PartialDate? = nil, outcome: Outcome? = nil, notes: String? = nil, copy: CopyID? = nil,
        players: [Int64] = []
    ) {
        self.start = start
        self.end = end
        self.outcome = outcome
        self.notes = notes
        self.copy = copy
        self.players = players
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
            try Self.checkCopy(db, draft.copy, of: game)
            try db.execute(
                sql: """
                    INSERT INTO playthrough (gameId, start, end, outcome, notes, romId, copyId)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [game] + Self.arguments(draft))
            let id = db.lastInsertedRowID
            try Self.setPlayers(db, id, draft.players)
            return id
        }
    }

    public func updatePlaythrough(_ id: Int64, _ draft: PlaythroughDraft) throws {
        try draft.validate()
        try db.write { db in
            if let game = try GameID.fetchOne(db, sql: "SELECT gameId FROM playthrough WHERE id = ?", arguments: [id]) {
                try Self.checkCopy(db, draft.copy, of: game)
            }
            try db.execute(
                sql: """
                    UPDATE playthrough SET start = ?, end = ?, outcome = ?, notes = ?, romId = ?, copyId = ?
                    WHERE id = ?
                    """,
                arguments: Self.arguments(draft) + [id])
            try Self.setPlayers(db, id, draft.players)
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
            try Self.playthroughs(db, where: "gameId = ?", [game]).map(\.1)
        }
    }

    /// Playthroughs with their Games, by start date, then as added.
    static func playthroughs(
        _ db: Database, where condition: String = "1", _ arguments: StatementArguments = []
    ) throws -> [(GameID, Playthrough)] {
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM playthrough WHERE \(condition) ORDER BY start, id", arguments: arguments)
        var players: [Int64: [Int64]] = [:]
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT playthroughId, playerId FROM playthroughPlayer JOIN player ON player.id = playerId
                WHERE playthroughId IN (SELECT id FROM playthrough WHERE \(condition))
                ORDER BY firstName COLLATE NOCASE, lastName COLLATE NOCASE
                """, arguments: arguments)
        {
            players[row["playthroughId"], default: []].append(row["playerId"])
        }
        return rows.map { row in
            (
                row["gameId"],
                Playthrough(
                    id: row["id"],
                    PlaythroughDraft(
                        start: PartialDate(row["start"])!,
                        end: (row["end"] as String?).flatMap(PartialDate.init),
                        outcome: (row["outcome"] as String?).flatMap(Outcome.init(rawValue:)),
                        notes: row["notes"],
                        copy: (row["romId"] as Int64?).map(CopyID.rom) ?? (row["copyId"] as Int64?).map(CopyID.copy),
                        players: players[row["id"]] ?? []))
            )
        }
    }

    private static func setPlayers(_ db: Database, _ playthrough: Int64, _ players: [Int64]) throws {
        try db.execute(sql: "DELETE FROM playthroughPlayer WHERE playthroughId = ?", arguments: [playthrough])
        for player in Set(players) {
            try db.execute(
                sql: "INSERT INTO playthroughPlayer (playthroughId, playerId) VALUES (?, ?)", arguments: [playthrough, player])
        }
    }

    private static func arguments(_ d: PlaythroughDraft) -> StatementArguments {
        [d.start.text, d.end?.text, d.outcome?.rawValue, d.notes, d.copy?.romId, d.copy?.copyId]
    }

    /// A Playthrough's Copy has to be one of its own Game's.
    private static func checkCopy(_ db: Database, _ copy: CopyID?, of game: GameID) throws {
        guard let copy else { return }
        let owner =
            switch copy {
            case .rom(let id): try GameID.fetchOne(db, sql: "SELECT gameId FROM rom WHERE id = ?", arguments: [id])
            case .copy(let id): try GameID.fetchOne(db, sql: "SELECT gameId FROM copy WHERE id = ?", arguments: [id])
            }
        guard owner == game else { throw LudeumError.copyNotOfGame }
    }

    /// Refuses, changing nothing, when a Playthrough was played on any of these Copies: they can't be deleted, or leave
    /// their Game, until each such Playthrough says another Copy or none.
    static func checkNotPlayedOn(_ db: Database, roms: [Int64] = [], copies: [Int64] = []) throws {
        guard !roms.isEmpty || !copies.isEmpty else { return }
        let played = try Bool.fetchOne(
            db,
            sql: """
                SELECT EXISTS (
                    SELECT 1 FROM playthrough WHERE romId IN (\(databaseQuestionMarks(count: max(roms.count, 1))))
                        OR copyId IN (\(databaseQuestionMarks(count: max(copies.count, 1)))))
                """,
            arguments: StatementArguments((roms.isEmpty ? [-1] : roms) + (copies.isEmpty ? [-1] : copies)))!
        if played { throw LudeumError.copyPlayedOn }
    }
}
