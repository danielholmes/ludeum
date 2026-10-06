import Foundation
import GRDB

/// One pick in a Face-off, so it can be undone: a Battle, or a skipped pair.
public enum FaceOffPick: Sendable, Equatable {
    case battle(Int64)
    case skip(Int64)
}

extension LudeumStore {
    /// Every rated Game, as a Face-off sees it.
    public func faceOffGames() throws -> [FaceOffGame] {
        try db.read { try faceOffGames($0) }
    }

    /// Records a Battle between the pair shown: `.a` when the left one won, `.b` the right, or About the same.
    @discardableResult
    public func recordBattle(_ pair: FaceOffPair, _ result: BattleResult) throws -> FaceOffPick {
        try db.write { db in
            try db.execute(
                sql: "INSERT INTO battle (gameAId, gameBId, result, day) VALUES (?, ?, ?, ?)",
                arguments: [pair.left.id, pair.right.id, result.rawValue, today()])
            return .battle(db.lastInsertedRowID)
        }
    }

    /// Skips the pair shown. No Battle is recorded: the pair stays away for the day, and its Games are offered less.
    @discardableResult
    public func skip(_ pair: FaceOffPair) throws -> FaceOffPick {
        try db.write { db in
            try db.execute(
                sql: "INSERT INTO battleSkip (gameAId, gameBId, day) VALUES (?, ?, ?)",
                arguments: [pair.left.id, pair.right.id, today()])
            return .skip(db.lastInsertedRowID)
        }
    }

    /// Takes back a pick made by mistake.
    public func undo(_ pick: FaceOffPick) throws {
        try db.write { db in
            switch pick {
            case .battle(let id): try db.execute(sql: "DELETE FROM battle WHERE id = ?", arguments: [id])
            case .skip(let id): try db.execute(sql: "DELETE FROM battleSkip WHERE id = ?", arguments: [id])
            }
        }
    }

    /// Stands by a Game's Rating: its Disagreement is set aside until it fights another Battle.
    public func keepRating(_ game: GameID) throws {
        try db.write { db in
            let latest =
                try Int64.fetchOne(db, sql: "SELECT MAX(id) FROM battle WHERE ? IN (gameAId, gameBId)", arguments: [game]) ?? 0
            try db.execute(
                sql: """
                    INSERT INTO keptRating (gameId, afterBattleId) VALUES (?, ?)
                    ON CONFLICT (gameId) DO UPDATE SET afterBattleId = excluded.afterBattleId
                    """, arguments: [game, latest])
        }
    }

    /// The Disagreements, biggest gap first.
    public func disagreements() throws -> [Disagreement] {
        let (games, battles, _, kept) = try faceOffState()
        return FaceOffModel.disagreements(games: games, battles: battles, today: dayNumber(today()), kept: kept)
    }

    /// The next pair to Battle, or nil when every pair is kept away today.
    public func nextFaceOffPair(using rng: inout some RandomNumberGenerator) throws -> FaceOffPair? {
        let (games, battles, skips, _) = try faceOffState()
        return FaceOffModel.nextPair(games: games, battles: battles, skips: skips, today: dayNumber(today()), using: &rng)
    }

    /// How many Battles I've fought today.
    public func battlesToday() throws -> Int {
        try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM battle WHERE day = ?", arguments: [today()])! }
    }

    private func faceOffGames(_ db: Database) throws -> [FaceOffGame] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT g.id, COALESCE(g.nameOverride, g.igdbName, g.name) AS name, p.name AS platformName,
                    (SELECT rating FROM ratingEntry WHERE gameId = g.id \(Self.ratingOrder) LIMIT 1) AS rating
                FROM game g JOIN platform p ON p.id = g.platformId
                ORDER BY g.id
                """
        ).compactMap { row in
            (row["rating"] as Int?).flatMap(Rating.init(tenths:)).map {
                FaceOffGame(id: row["id"], name: row["name"], platformName: row["platformName"], rating: $0)
            }
        }
    }

    private func faceOffState() throws -> ([FaceOffGame], [FaceOffBattle], [FaceOffSkip], [GameID: Int64]) {
        try db.read { db in
            let battles = try Row.fetchAll(db, sql: "SELECT * FROM battle ORDER BY id").map { row in
                FaceOffBattle(
                    id: row["id"], a: row["gameAId"], b: row["gameBId"], result: BattleResult(rawValue: row["result"])!,
                    day: dayNumber(row["day"]))
            }
            let skips = try Row.fetchAll(db, sql: "SELECT * FROM battleSkip ORDER BY id").map { row in
                FaceOffSkip(a: row["gameAId"], b: row["gameBId"], day: dayNumber(row["day"]))
            }
            let kept = try Row.fetchAll(db, sql: "SELECT * FROM keptRating").reduce(into: [GameID: Int64]()) {
                $0[$1["gameId"]] = $1["afterBattleId"]
            }
            return (try faceOffGames(db), battles, skips, kept)
        }
    }

    /// A local day (`YYYY-MM-DD`) as days since 1970-01-01, so days can be subtracted.
    func dayNumber(_ day: String) -> Int {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
        return Int(date.timeIntervalSince1970 / 86400)
    }
}
