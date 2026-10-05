import Foundation
import GRDB

extension JournalStore {
    /// The Game holding this IGDB link, if any.
    public func gameID(igdbGameId: Int64, platformId: Int64) throws -> GameID? {
        try db.read { db in
            try GameID.fetchOne(
                db, sql: "SELECT id FROM game WHERE igdbGameId = ? AND platformId = ?", arguments: [igdbGameId, platformId])
        }
    }

    /// Every Game holding this IGDB game, on any Platform, by id.
    public func games(igdbGameId: Int64) throws -> [Game] {
        try db.read { db in try GameID.fetchAll(db, sql: "SELECT id FROM game WHERE igdbGameId = ? ORDER BY id", arguments: [igdbGameId]) }
            .map(game)
    }

    /// A Platform the journal has recorded.
    public func platform(_ id: Int64) throws -> IGDBPlatform? {
        try db.read { db in
            try Row.fetchOne(db, sql: "SELECT id, name FROM platform WHERE id = ?", arguments: [id]).map {
                IGDBPlatform(id: $0["id"], name: $0["name"])
            }
        }
    }

    /// The Platforms my Games use, listed first in the Platform picker.
    public func usedPlatformIDs() throws -> Set<Int64> {
        try db.read { db in Set(try Int64.fetchAll(db, sql: "SELECT DISTINCT platformId FROM game")) }
    }

    /// A Game with no IGDB link. Name and Platform are required.
    @discardableResult
    public func addGameByHand(name: String, platformId: Int64) throws -> GameID {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw JournalError.nameRequired }
        return try addGame(platformId: platformId, name: name)
    }

    /// Games on `platformId` whose display name, own name or IGDB name agrees with `name` (the
    /// matching normalisation). Adding a Game by hand warns about these but never refuses.
    public func gamesWhoseNamesAgree(with name: String, platformId: Int64) throws -> [Game] {
        let key = nameKey(cleanName(name))
        guard !key.isEmpty else { return [] }
        let ids = try db.read { db in
            try Row.fetchAll(
                db, sql: "SELECT id, name, igdbName, nameOverride FROM game WHERE platformId = ? ORDER BY id", arguments: [platformId]
            )
            .filter { row in
                [row["nameOverride"], row["igdbName"], row["name"]].compactMap { (n: String?) in n }
                    .contains { nameKey(cleanName($0)) == key }
            }
            .map { $0["id"] as GameID }
        }
        return try ids.map(game)
    }

    /// Gives a hand-made Game its IGDB link. Its name then follows IGDB unless overridden.
    /// Links a Game to IGDB. `replacing` changes an existing link, to fix a mistaken one; otherwise a
    /// linked Game is refused. `platform` moves the Game to another Platform too, only while it has no
    /// ROMs. Either way, no two Games share a link.
    public func link(_ id: GameID, igdbGameId: Int64, igdbName: String, replacing: Bool = false, platform: IGDBPlatform? = nil) throws {
        try write(uniqueViolation: .igdbLinkTaken) { db in
            guard let current = try Row.fetchOne(db, sql: "SELECT igdbGameId FROM game WHERE id = ?", arguments: [id]) else {
                throw JournalError.gameNotFound
            }
            if (current["igdbGameId"] as Int64?) != nil, !replacing { throw JournalError.alreadyLinked }
            if let platform {
                if try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM rom WHERE gameId = ?)", arguments: [id])! {
                    throw JournalError.gameHasROMs
                }
                try db.execute(
                    sql: "INSERT INTO platform (id, name) VALUES (?, ?) ON CONFLICT (id) DO NOTHING", arguments: [platform.id, platform.name])
                try db.execute(sql: "UPDATE game SET platformId = ? WHERE id = ?", arguments: [platform.id, id])
            }
            try db.execute(sql: "UPDATE game SET igdbGameId = ?, igdbName = ? WHERE id = ?", arguments: [igdbGameId, igdbName, id])
        }
    }
}
