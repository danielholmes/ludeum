import Foundation
import GRDB

/// What an Expansion's IGDB record says it expands: its Base game, or nil when IGDB doesn't say.
public struct ExpansionOf: Sendable, Equatable {
    public let baseGame: IGDBNamed?

    public init(baseGame: IGDBNamed?) { self.baseGame = baseGame }
}

/// The line under an Expansion's name: "Expansion of" its Base game, which is my Game on the same Platform
/// (by my name) when there is one, else IGDB's name unlinked; with no name when IGDB doesn't say.
public struct BaseGameLine: Sendable, Equatable {
    public let name: String?
    public let game: GameID?

    public init(name: String?, game: GameID?) {
        self.name = name
        self.game = game
    }
}

extension IGDBGame {
    /// An Expansion (2) or Standalone Expansion (4): a Game linked to it is an Expansion.
    public var isExpansion: Bool { [2, 4].contains(record["game_type"]?.int ?? 0) }

    /// Its Base game, from IGDB's `parent_game`, when it's an Expansion.
    var expansionOf: ExpansionOf? {
        guard isExpansion else { return nil }
        let base = record["parent_game"]
        return ExpansionOf(baseGame: base?["id"]?.int.map { IGDBNamed(id: $0, name: base?["name"]?.string ?? "Game \($0)") })
    }

    /// IGDB's Expansions of it, Standalone Expansions after the others.
    var expansionIDs: [Int] {
        ["expansions", "standalone_expansions"].flatMap { field in
            (record[field]?.array ?? []).compactMap { $0["id"]?.int ?? $0.int }
        }
    }
}

extension LudeumStore {
    /// What `game` is an Expansion of, as its `facts` say; nil when it isn't one.
    public func baseGame(of game: Game, facts: GameFacts) throws -> BaseGameLine? {
        guard let expansion = facts.expansion else { return nil }
        guard let base = expansion.baseGame else { return BaseGameLine(name: nil, game: nil) }
        if let id = try gameID(igdbGameId: Int64(base.id), platformId: game.platformId) {
            return BaseGameLine(name: try self.game(id).name, game: id)
        }
        return BaseGameLine(name: base.name, game: nil)
    }

    /// The Games on `game`'s Platform that are its Expansions, as its `facts` say, by name.
    public func expansions(of game: Game, facts: GameFacts) throws -> [Game] {
        try facts.expansionIDs.compactMap { try gameID(igdbGameId: Int64($0), platformId: game.platformId) }.map(self.game)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
