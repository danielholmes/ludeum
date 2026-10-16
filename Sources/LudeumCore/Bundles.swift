import Foundation
import GRDB

extension LudeumStore {
    // MARK: Bundles (ADR 0016)

    /// A Bundle on `platformId`: a row of `game` marked as one, with an IGDB link or none (made by hand).
    @discardableResult
    public func addBundle(platformId: Int64, name: String, igdbGameId: Int64? = nil, igdbName: String? = nil) throws -> GameID {
        try write(uniqueViolation: .igdbLinkTaken) { db in
            try db.execute(
                sql: "INSERT INTO game (platformId, name, igdbGameId, igdbName, bundle) VALUES (?, ?, ?, ?, 1)",
                arguments: [platformId, name, igdbGameId, igdbName])
            return db.lastInsertedRowID
        }
    }

    /// Puts `game` in `bundle`. Adding it again does nothing. Refused for a Game of another Platform, or a Bundle.
    public func addToBundle(_ bundle: GameID, _ game: GameID) throws {
        let (bundle, game) = (try self.game(bundle), try self.game(game))
        guard bundle.isBundle, !game.isBundle, game.platformId == bundle.platformId else { throw LudeumError.cantBeInBundle }
        try db.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO bundleGame (bundleId, gameId) VALUES (?, ?)", arguments: [bundle.id, game.id])
        }
    }

    /// Takes `game` out of `bundle`. Refused while a Playthrough of it was played on one of the Bundle's Copies, until that
    /// Playthrough says another Copy or none.
    public func removeFromBundle(_ bundle: GameID, _ game: GameID) throws {
        try db.write { db in
            let played = try Bool.fetchOne(
                db,
                sql: """
                    SELECT EXISTS (
                        SELECT 1 FROM playthrough WHERE gameId = ?
                            AND (romId IN (SELECT id FROM rom WHERE gameId = ?) OR copyId IN (SELECT id FROM copy WHERE gameId = ?)))
                    """, arguments: [game, bundle, bundle])!
            if played { throw LudeumError.copyPlayedOn }
            try db.execute(sql: "DELETE FROM bundleGame WHERE bundleId = ? AND gameId = ?", arguments: [bundle, game])
        }
    }

    /// The Games `bundle` contains, by name.
    public func bundleGames(_ bundle: GameID) throws -> [Game] {
        try db.read { db in try GameID.fetchAll(db, sql: "SELECT gameId FROM bundleGame WHERE bundleId = ?", arguments: [bundle]) }
            .map(game)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Every Bundle, by name: what the Review queue can Assign a ROM to besides the Library's Games.
    public func bundles() throws -> [Game] {
        try db.read { db in try GameID.fetchAll(db, sql: "SELECT id FROM game WHERE bundle") }.map(game)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The Bundles that contain `game`, as they were made: the first is the one whose Cover it falls back on.
    public func bundles(containing game: GameID) throws -> [Game] {
        try db.read { db in
            try GameID.fetchAll(db, sql: "SELECT bundleId FROM bundleGame WHERE gameId = ? ORDER BY bundleId", arguments: [game])
        }
        .map(self.game)
    }

    /// The ROMs Play can open for `game`: its own while one is present and not Archived, so a Bundle's can't get in its
    /// way, else its own then those of the Bundles that contain it.
    public func romsToPlay(of game: GameID) throws -> [LudeumROM] {
        let own = try roms(of: game)
        if own.contains(where: { !$0.missing && !$0.archived }) { return own }
        return try own + bundles(containing: game).flatMap { try roms(of: $0.id) }
    }
}
