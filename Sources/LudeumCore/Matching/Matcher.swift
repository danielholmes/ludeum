import Foundation

/// A ROM as far as matching it is concerned. A ROM folder's ROM has no checksum yet, so it's only ever
/// suggested by name (ADR 0004).
public struct ROMToMatch: Sendable, Hashable {
    /// Its key in the results.
    public let id: Int
    public let name: String
    public let md5: String?
    /// The IGDB platforms it could be on, most likely first.
    public let platforms: [Int]

    public init(id: Int, name: String, md5: String? = nil, platforms: [Int]) {
        self.id = id
        self.name = name
        self.md5 = md5
        self.platforms = platforms
    }
}

public enum MatchResult: Sendable, Hashable, Codable {
    /// The checksum identifies the game *and* the names agree (ADR 0004).
    case automatic(gameID: Int)
    /// For the Review queue to confirm.
    case suggestion(Suggestion)
    /// For the Review queue, to search IGDB by hand.
    case noSuggestion
}

public struct Suggestion: Sendable, Hashable, Codable {
    public enum Source: String, Sendable, Hashable, Codable {
        /// The checksum's own game, whose names disagree.
        case checksum
        /// A related record of the checksum's game, whose name agrees.
        case relatedRecord
        /// IGDB name search on the ROM's platforms.
        case nameSearch
    }

    public let gameID: Int
    public let source: Source
    /// Names agree, so the Review queue can bulk-confirm it.
    public let namesAgree: Bool
    /// For a related-record suggestion, the checksum's own game (shown crossed out).
    public let checksumGameID: Int?

    public init(gameID: Int, source: Source, namesAgree: Bool, checksumGameID: Int? = nil) {
        self.gameID = gameID
        self.source = source
        self.namesAgree = namesAgree
        self.checksumGameID = checksumGameID
    }
}

/// Matches ROMs to IGDB games, from the cache where it can.
public final class Matcher: Sendable {
    let igdb: IGDBClient
    let hasheous: HasheousClient

    public init(igdb: IGDBClient, hasheous: HasheousClient) {
        self.igdb = igdb
        self.hasheous = hasheous
    }

    /// Every ROM's result, keyed by ROM id. `progress` gets (ROMs looked up, total); it can be cancelled.
    public func match(_ roms: [ROMToMatch], progress: @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> [Int: MatchResult] {
        var checksumGame: [Int: Int] = [:]
        var candidates: [Int: [Int]] = [:]
        for (i, rom) in roms.enumerated() {
            try Task.checkCancellation()
            progress(i, roms.count)
            if let game = try await checksumGameID(rom) {
                checksumGame[rom.id] = game
            } else {
                candidates[rom.id] = try await searchCandidates(rom)
            }
        }

        // IGDB records in two batches: checksum games and search candidates, then the checksum games' relatives.
        var games = try await igdb.games(ids: Array(Set(checksumGame.values).union(candidates.values.joined())))
        let relatives = Set(checksumGame.values.flatMap { games[$0].map(relatedIDs) ?? [] }).subtracting(games.keys)
        games.merge(try await igdb.games(ids: Array(relatives))) { a, _ in a }

        var out: [Int: MatchResult] = [:]
        for rom in roms {
            func agree(_ g: IGDBGame) -> Bool { namesAgree(romName: rom.name, game: g) }
            if let id = checksumGame[rom.id] {
                if let game = games[id], agree(game) {
                    out[rom.id] = .automatic(gameID: id)
                } else if let related = games[id].flatMap({ relatedIDs($0).compactMap { games[$0] }.first(where: agree) }) {
                    out[rom.id] = .suggestion(Suggestion(gameID: related.id, source: .relatedRecord, namesAgree: true, checksumGameID: id))
                } else {
                    out[rom.id] = .suggestion(Suggestion(gameID: id, source: .checksum, namesAgree: false))
                }
            } else {
                let eligible = (candidates[rom.id] ?? []).compactMap { games[$0] }.filter(canBeAGame)
                if let g = eligible.first(where: agree) {
                    out[rom.id] = .suggestion(Suggestion(gameID: g.id, source: .nameSearch, namesAgree: true))
                } else if let g = eligible.first {
                    out[rom.id] = .suggestion(Suggestion(gameID: g.id, source: .nameSearch, namesAgree: false))
                } else {
                    out[rom.id] = .noSuggestion
                }
            }
        }
        return out
    }

    /// Hasheous by the ROM's MD5, when it has one.
    private func checksumGameID(_ rom: ROMToMatch) async throws -> Int? {
        guard let md5 = rom.md5, !md5.isEmpty else { return nil }
        return try await hasheous.lookup(md5: md5).match?.igdbGameID
    }

    /// The first non-empty IGDB name search for the ROM's cleaned name, trying each of its platforms.
    private func searchCandidates(_ rom: ROMToMatch) async throws -> [Int] {
        let name = cleanName(rom.name)
        guard !name.isEmpty else { return [] }
        for platform in rom.platforms {
            let search = IGDBSearch(name: name, platformID: platform)
            if let ids = try await igdb.search([search])[search], !ids.isEmpty { return ids }
        }
        return []
    }
}

/// IGDB records a checksum's game is related to, which may be the right Game when it isn't.
private func relatedIDs(_ game: IGDBGame) -> [Int] {
    let single = ["parent_game", "version_parent"].compactMap { game.record[$0]?["id"]?.int ?? game.record[$0]?.int }
    let lists = ["expanded_games", "remasters", "remakes", "ports", "standalone_expansions", "forks"].flatMap { field in
        (game.record[field]?.array ?? []).compactMap { $0["id"]?.int ?? $0.int }
    }
    return single + lists
}

/// DLC (1), Expansion (2), Mod (5), Season (7), Pack/Addon (13) and Update (14) are never suggested.
private func canBeAGame(_ game: IGDBGame) -> Bool {
    ![1, 2, 5, 7, 13, 14].contains(game.record["game_type"]?.int ?? 0)
}
