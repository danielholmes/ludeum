import Foundation
import GRDB

/// One entry in a Game's Rating history. A nil `rating` records clearing back to unrated.
public struct RatingEntry: Sendable, Equatable {
    public let id: Int64
    /// The local day it was set, `YYYY-MM-DD`.
    public let day: String
    public let rating: Rating?
}

extension LudeumStore {
    /// The newest entry first, so the first entry is the current Rating.
    static let ratingOrder = "ORDER BY day DESC"

    /// Sets or (with nil) clears the Rating. One entry per local day: a second change that day
    /// replaces the day's entry, and re-entering the current value does nothing.
    public func setRating(_ game: GameID, _ rating: Rating?) throws {
        let day = today()
        try db.write { db in
            let current = try Row.fetchOne(
                db, sql: "SELECT rating FROM ratingEntry WHERE gameId = ? \(Self.ratingOrder) LIMIT 1", arguments: [game])
            let currentTenths: Int? = current?["rating"]  // nil when unrated or no history yet
            if currentTenths == rating?.tenths { return }  // the same value again is no change
            try db.execute(
                sql: """
                    INSERT INTO ratingEntry (gameId, day, rating) VALUES (?, ?, ?)
                    ON CONFLICT (gameId, day) DO UPDATE SET rating = excluded.rating
                    """, arguments: [game, day, rating?.tenths])
        }
    }

    public func ratingHistory(_ game: GameID) throws -> [RatingEntry] {
        try db.read { db in
            try Row.fetchAll(
                db, sql: "SELECT * FROM ratingEntry WHERE gameId = ? \(Self.ratingOrder)", arguments: [game]
            ).map {
                RatingEntry(
                    id: $0["id"], day: $0["day"], rating: ($0["rating"] as Int?).flatMap { Rating(tenths: $0) })
            }
        }
    }

    /// Deletes an entry. Deleting the latest makes the previous one the Rating.
    public func deleteRatingEntry(_ id: Int64) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM ratingEntry WHERE id = ?", arguments: [id])
        }
    }

    /// Today's local date as `YYYY-MM-DD`.
    func today() -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: clock.now())
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
