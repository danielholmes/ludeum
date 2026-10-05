import Foundation

/// An IGDB platform, which is exactly what a Platform is (ADR 0005).
public struct IGDBPlatform: Sendable, Hashable, Codable, Identifiable {
    public let id: Int64
    public let name: String
    public let abbreviation: String?

    public init(id: Int64, name: String, abbreviation: String? = nil) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
    }
}

/// The Platform picker's list: Platforms my Games already use first, then the rest by name,
/// narrowed to those whose name or abbreviation contains `filter`.
public func platformPickerOrder(_ platforms: [IGDBPlatform], used: Set<Int64>, filter: String) -> [IGDBPlatform] {
    let filter = filter.trimmingCharacters(in: .whitespaces)
    let matching = platforms.filter {
        filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter)
            || ($0.abbreviation?.localizedCaseInsensitiveContains(filter) ?? false)
    }
    return matching.sorted {
        let (a, b) = (used.contains($0.id), used.contains($1.id))
        return a != b ? a : $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
}

/// One result of the IGDB search: an IGDB game and the platforms it can be added on.
public struct GameSearchResult: Sendable, Hashable, Identifiable {
    public let igdbGameId: Int64
    public let name: String
    public let year: Int?
    /// IGDB's first release date, for sorting.
    public var releaseDate: Date? = nil
    /// IGDB's `game_type` label when it isn't a main game, e.g. "Mod" or "Remaster".
    public let gameType: String?
    public let coverImageID: String?
    public let chips: [PlatformChip]
    public var id: Int64 { igdbGameId }
}

/// How IGDB search results are ordered. Undated results go last either way.
public enum GameSearchSort: String, CaseIterable, Sendable {
    case name
    case releaseDate

    /// Names A–Z; release dates newest first.
    public var defaultAscending: Bool { self == .name }

    public func sorted(_ results: [GameSearchResult], ascending: Bool) -> [GameSearchResult] {
        switch self {
        case .name:
            let byName = results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return ascending ? byName : byName.reversed()
        case .releaseDate:
            let dated = results.filter { $0.releaseDate != nil }.sorted { a, b in
                ascending ? a.releaseDate! < b.releaseDate! : a.releaseDate! > b.releaseDate!
            }
            return dated + results.filter { $0.releaseDate == nil }
        }
    }
}

/// A platform an IGDB game is on. `game` is set when that IGDB game and platform is
/// already a Game in the journal ("In journal").
public struct PlatformChip: Sendable, Hashable {
    public let platform: IGDBPlatform
    public let game: GameID?
    public var platformName: String { platform.name }
}

/// The one IGDB search: adding Games, linking a hand-made Game, and the Review queue's manual search.
public struct GameSearch: Sendable {
    let igdb: IGDBClient
    let journal: JournalStore

    public init(igdb: IGDBClient, journal: JournalStore) {
        self.igdb = igdb
        self.journal = journal
    }

    /// IGDB games matching `query`, optionally on one platform, best match first. DLC, Expansions,
    /// Seasons, Packs and Updates are left out; Mods are shown and labelled.
    public func search(_ query: String, platform: Int64? = nil) async throws -> [GameSearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let search = IGDBSearch(name: query, platformID: platform.map(Int.init))
        let ids = try await igdb.search([search])[search] ?? []
        let games = try await igdb.games(ids: ids)
        return try ids.compactMap { games[$0] }.filter { !isAddOn($0) }.map(result)
    }

    /// Adds the IGDB game as a Game on `platform`, taking IGDB's name and link. If that IGDB game
    /// and platform is already a Game, that Game is returned instead.
    @discardableResult
    public func add(_ result: GameSearchResult, on platform: IGDBPlatform) throws -> GameID {
        if let existing = try journal.gameID(igdbGameId: result.igdbGameId, platformId: platform.id) { return existing }
        try journal.addPlatform(id: platform.id, name: platform.name)
        return try journal.addGame(platformId: platform.id, name: result.name, igdbGameId: result.igdbGameId, igdbName: result.name)
    }

    /// Links a hand-made Game to the IGDB game. Refused if another Game holds that link
    /// (`igdbLinkTaken`) or the Game already has one (`alreadyLinked`).
    public func link(_ game: GameID, to result: GameSearchResult, replacing: Bool = false, platform: IGDBPlatform? = nil) throws {
        try journal.link(game, igdbGameId: result.igdbGameId, igdbName: result.name, replacing: replacing, platform: platform)
    }

    /// Every IGDB platform, for choosing where a Game goes.
    public func platforms() async throws -> [IGDBPlatform] { try await igdb.platforms() }

    /// The local file of a result's IGDB cover, downloaded once; nil if it has none.
    public func cover(for result: GameSearchResult) async throws -> URL? {
        guard let id = result.coverImageID else { return nil }
        return try await igdb.cover(imageID: id)
    }

    /// The Game holding this IGDB link, to say "Already linked to X".
    public func journalGame(igdbGameId: Int64, platformId: Int64) throws -> Game? {
        try journal.gameID(igdbGameId: igdbGameId, platformId: platformId).map(journal.game)
    }

    /// The result's chips as the Library is now: IGDB's platforms, then Platforms a Game holds this
    /// IGDB link on that IGDB doesn't list (added with "Different platform…").
    public func currentChips(for result: GameSearchResult) throws -> [PlatformChip] {
        let listed = try result.chips.map { chip in
            PlatformChip(platform: chip.platform, game: try journal.gameID(igdbGameId: result.igdbGameId, platformId: chip.platform.id))
        }
        let others = try journal.games(igdbGameId: result.igdbGameId).filter { game in !listed.contains { $0.platform.id == game.platformId } }
        return try listed
            + others.map { game in
                PlatformChip(
                    platform: try journal.platform(game.platformId) ?? IGDBPlatform(id: game.platformId, name: "Platform \(game.platformId)", abbreviation: nil),
                    game: game.id)
            }
    }

    private func result(_ game: IGDBGame) throws -> GameSearchResult {
        let platforms = (game.record["platforms"]?.array ?? []).compactMap { p -> IGDBPlatform? in
            guard let id = p["id"]?.int, let name = p["name"]?.string else { return nil }
            return IGDBPlatform(id: Int64(id), name: name, abbreviation: p["abbreviation"]?.string)
        }
        let chips = try platforms.map {
            PlatformChip(platform: $0, game: try journal.gameID(igdbGameId: Int64(game.id), platformId: $0.id))
        }
        let released = game.record["first_release_date"]?.number.map { Date(timeIntervalSince1970: $0) }
        let year = released.map { Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: $0).year! }
        let type = game.record["game_type"]?.int ?? 0
        return GameSearchResult(
            igdbGameId: Int64(game.id), name: game.name ?? "Game \(game.id)", year: year, releaseDate: released,
            gameType: type == 0 ? nil : gameTypeNames[type] ?? "Other", coverImageID: game.record["cover"]?["image_id"]?.string,
            chips: chips)
    }
}

/// DLC (1), Expansion (2), Season (7), Pack/Addon (13) and Update (14) are never a Game. Mods (5) can be.
private func isAddOn(_ game: IGDBGame) -> Bool { [1, 2, 7, 13, 14].contains(game.record["game_type"]?.int ?? 0) }

private let gameTypeNames = [
    1: "DLC", 2: "Expansion", 3: "Bundle", 4: "Standalone Expansion", 5: "Mod", 6: "Episode", 7: "Season", 8: "Remake",
    9: "Remaster", 10: "Expanded Game", 11: "Port", 12: "Fork", 13: "Pack / Addon", 14: "Update",
]
