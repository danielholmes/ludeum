import Foundation
import GRDB

/// A Game's RetroAchievements time (ADR 0030): the time of the set for its Platform, found by its ROMs' checksums at
/// Hasheous, else by its IGDB link at Wikidata. Nothing is kept in the journal: each answer is in the cache, so it's
/// worked out again whenever it's shown, and Matching a ROM or changing the IGDB link changes it with no step to rerun.
public struct RetroAchievementsTimes: Sendable {
    let journal: LudeumStore
    let retroAchievements: RetroAchievementsClient
    let hasheous: HasheousClient?
    let igdb: IGDBClient?
    let wikidata: WikidataClient?

    public init(
        journal: LudeumStore, retroAchievements: RetroAchievementsClient, hasheous: HasheousClient?, igdb: IGDBClient?,
        wikidata: WikidataClient?
    ) {
        self.journal = journal
        self.retroAchievements = retroAchievements
        self.hasheous = hasheous
        self.igdb = igdb
        self.wikidata = wikidata
    }

    /// The Game's RetroAchievements time, nil when it has none: a Bundle, a Platform RetroAchievements has no sets for, no
    /// set found on its Platform, or one too few players have beaten or mastered. The set comes from the first of its
    /// ROMs whose checksum Hasheous ties to a set on the Platform, as that's the dump I have; only when none does is it
    /// the set Wikidata gives the Game's IGDB game on the Platform. Throws when a service can't be reached, and nothing
    /// is kept of the failure: it's asked again the next time.
    public func time(of id: GameID) async throws -> RetroAchievementsTime? {
        let game = try journal.game(id)
        guard !game.isBundle, let console = RetroAchievementsClient.consoles[game.platformId] else { return nil }
        if let hasheous {
            var seen: Set<Int> = []
            for rom in try journal.romChecksums(of: id) {
                guard let set = try await hasheous.lookup(md5: rom.md5, crc: rom.crc)?.match?.retroAchievementsGameID,
                    seen.insert(set).inserted
                else { continue }
                if let progression = try await retroAchievements.progression(gameID: set), progression.consoleID == console {
                    return progression.time
                }
            }
        }
        guard let igdb, let wikidata, let link = game.igdbGameId,
            let slug = try await igdb.cachedGame(id: Int(link))?.record["slug"]?.string
        else { return nil }
        for set in try await wikidata.retroAchievementsIDs(igdbSlug: slug) {
            if let progression = try await retroAchievements.progression(gameID: set), progression.consoleID == console {
                return progression.time
            }
        }
        return nil
    }
}

extension LudeumStore {
    /// The checksums of a Game's ROMs that have one, oldest ROM first.
    func romChecksums(of game: GameID) throws -> [(md5: String?, crc: String?)] {
        try db.read { db in
            try Row.fetchAll(
                db, sql: "SELECT md5, crc FROM rom WHERE gameId = ? AND (md5 IS NOT NULL OR crc IS NOT NULL) ORDER BY id",
                arguments: [game]
            ).map { (md5: $0["md5"], crc: $0["crc"]) }
        }
    }
}
