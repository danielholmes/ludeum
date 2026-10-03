import Foundation
import GRDB

/// An unmatched ROM in the Review queue, with its stored suggestion.
public struct ReviewItem: Sendable, Equatable, Identifiable {
    public let romId: Int64
    /// OpenEmu's name for the ROM.
    public let romName: String
    /// e.g. "openemu.system.snes", for its Platform.
    public let systemId: String
    public let missing: Bool
    public let suggestedIgdbGameId: Int64?
    /// Where the suggestion came from: the checksum (or a related record of it), or a name search.
    public let suggestionKind: SuggestionKind?
    /// For a related-record suggestion, the checksum's own game, shown crossed out.
    public let checksumIgdbGameId: Int64?
    public let namesAgree: Bool
    public var id: Int64 { romId }

    public enum SuggestionKind: String, Sendable {
        case checksum, name
    }
}

/// A Game with two or more present ROMs that aren't Discs of one Version.
public struct DuplicateVersionsGame: Sendable, Equatable, Identifiable {
    public let game: Game
    /// Its present ROMs.
    public let roms: [JournalROM]
    public var id: GameID { game.id }
}

/// Everything waiting in the Review queue, by kind.
public struct ReviewQueueItems: Sendable, Equatable {
    /// Name and related-record suggestions whose names agree: bulk-confirmable.
    public var namesAgree: [ReviewItem] = []
    public var checksumSuggestions: [ReviewItem] = []
    public var nameSuggestions: [ReviewItem] = []
    public var noSuggestion: [ReviewItem] = []
    public var duplicateVersions: [DuplicateVersionsGame] = []

    public init() {}

    /// The sidebar badge.
    public var count: Int {
        namesAgree.count + checksumSuggestions.count + nameSuggestions.count + noSuggestion.count + duplicateVersions.count
    }
}

extension JournalStore {
    public func reviewQueue() throws -> ReviewQueueItems {
        var items = ReviewQueueItems()
        let rows = try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM rom WHERE gameId IS NULL ORDER BY fileName COLLATE NOCASE, id")
        }
        for row in rows {
            let item = ReviewItem(
                romId: row["id"], romName: row["fileName"], systemId: row["systemId"], missing: row["missing"],
                suggestedIgdbGameId: row["suggestedIgdbGameId"],
                suggestionKind: (row["suggestionKind"] as String?).flatMap(ReviewItem.SuggestionKind.init(rawValue:)),
                checksumIgdbGameId: row["checksumIgdbGameId"], namesAgree: row["namesAgree"] ?? false)
            switch (item.suggestedIgdbGameId, item.suggestionKind, item.namesAgree) {
            case (nil, _, _): items.noSuggestion.append(item)
            case (_, _, true): items.namesAgree.append(item)
            case (_, .checksum, _): items.checksumSuggestions.append(item)
            default: items.nameSuggestions.append(item)
            }
        }
        let games = try db.read { db in
            try GameID.fetchAll(db, sql: "SELECT DISTINCT gameId FROM rom WHERE gameId IS NOT NULL AND NOT missing")
        }
        for game in games {
            let roms = try roms(of: game)
            if hasDuplicateVersions(roms.map(gameROM)) {
                items.duplicateVersions.append(DuplicateVersionsGame(game: try self.game(game), roms: roms.filter { !$0.missing }))
            }
        }
        items.duplicateVersions.sort { $0.game.name.localizedStandardCompare($1.game.name) == .orderedAscending }
        return items
    }

    /// Whether Matching this ROM to the Game would give it Duplicate Versions. It warns, never blocks.
    public func wouldHaveDuplicateVersions(_ game: GameID, adding rom: Int64) throws -> Bool {
        guard
            let item = try db.read({ db in try Row.fetchOne(db, sql: "SELECT fileName, missing FROM rom WHERE id = ?", arguments: [rom]) })
        else { return false }
        let added = GameROM(id: Int(rom), name: item["fileName"], isPlaylist: isPlaylist(item["fileName"]), isPresent: !item["missing"])
        return hasDuplicateVersions(try roms(of: game).map(gameROM) + [added])
    }

    /// Assign to Game…: Matches the ROM to an existing Game by hand.
    public func assign(_ item: ReviewItem, to game: GameID) throws {
        try db.write { db in try Self.match(db, rom: item.romId, to: game, kind: "manual", day: today(), now: clock.now()) }
    }

    /// Make by hand…: a new Game with no IGDB link, Matched to the ROM.
    @discardableResult
    public func makeByHand(_ item: ReviewItem, name: String, platform: IGDBPlatform) throws -> GameID {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw JournalError.nameRequired }
        return try db.write { db in
            try db.execute(
                sql: "INSERT INTO platform (id, name) VALUES (?, ?) ON CONFLICT (id) DO NOTHING", arguments: [platform.id, platform.name])
            try db.execute(sql: "INSERT INTO game (platformId, name) VALUES (?, ?)", arguments: [platform.id, name])
            let game = db.lastInsertedRowID
            try Self.match(db, rom: item.romId, to: game, kind: "manual", day: today(), now: clock.now())
            return game
        }
    }

    /// Matches the ROM to the Game with that IGDB link on that Platform, creating the Game if needed.
    func match(_ item: ReviewItem, igdbGameId: Int64, igdbName: String, platform: IGDBPlatform, kind: String) throws -> GameID {
        try db.write { db in
            try db.execute(
                sql: "INSERT INTO platform (id, name) VALUES (?, ?) ON CONFLICT (id) DO NOTHING", arguments: [platform.id, platform.name])
            let game: GameID
            if let existing = try GameID.fetchOne(
                db, sql: "SELECT id FROM game WHERE igdbGameId = ? AND platformId = ?", arguments: [igdbGameId, platform.id])
            {
                game = existing
            } else {
                try db.execute(
                    sql: "INSERT INTO game (platformId, name, igdbGameId, igdbName) VALUES (?, ?, ?, ?)",
                    arguments: [platform.id, cleanName(item.romName), igdbGameId, igdbName])
                game = db.lastInsertedRowID
            }
            try Self.match(db, rom: item.romId, to: game, kind: kind, day: today(), now: clock.now())
            return game
        }
    }

    /// Sets the ROM's Match, clears its suggestion, and applies the OpenEmu data held for it.
    static func match(_ db: Database, rom: Int64, to game: GameID, kind: String, day: String, now: Date) throws {
        try db.execute(
            sql: """
                UPDATE rom SET gameId = ?, matchKind = ?, matchedAt = ?,
                    suggestedIgdbGameId = NULL, suggestionKind = NULL, checksumIgdbGameId = NULL, namesAgree = NULL
                WHERE id = ? AND gameId IS NULL
                """, arguments: [game, kind, now, rom])
        guard db.changesCount == 1 else { throw ReviewError.alreadyMatched }
        if let held = try Row.fetchOne(db, sql: "SELECT * FROM heldOpenEmuData WHERE romId = ?", arguments: [rom]) {
            let collections = (try? JSONDecoder().decode([String].self, from: Data((held["collections"] as String).utf8))) ?? []
            try applyOpenEmuData(
                db, game: game, stars: held["stars"] ?? 0, collections: Set(collections),
                start: (held["currentStart"] as String?).flatMap(PartialDate.init), day: day)
            try db.execute(sql: "DELETE FROM heldOpenEmuData WHERE romId = ?", arguments: [rom])
        }
    }
}

public enum ReviewError: Error, Equatable {
    /// The item was answered already (e.g. twice from the UI).
    case alreadyMatched
    /// IGDB doesn't know the suggested game any more.
    case suggestionGone
}

private func gameROM(_ rom: JournalROM) -> GameROM {
    GameROM(id: Int(rom.id), name: rom.fileName, isPlaylist: isPlaylist(rom.fileName), isPresent: !rom.missing)
}

private func isPlaylist(_ fileName: String) -> Bool { (fileName as NSString).pathExtension.lowercased() == "m3u" }

/// Answering Review queue items with IGDB: confirming suggestions and choosing search results.
public struct ReviewQueue: Sendable {
    let journal: JournalStore
    let igdb: IGDBClient

    public init(journal: JournalStore, igdb: IGDBClient) {
        self.journal = journal
        self.igdb = igdb
    }

    /// Confirm: Matches the ROM to its suggestion, on the Platform its system maps to.
    @discardableResult
    public func confirm(_ item: ReviewItem) async throws -> GameID {
        guard let suggested = item.suggestedIgdbGameId else { throw ReviewError.suggestionGone }
        guard let record = try await igdb.games(ids: [Int(suggested)])[Int(suggested)] else { throw ReviewError.suggestionGone }
        let platformId = gamePlatform(system: item.systemId, game: record)
        let platform = try await platform(platformId)
        return try journal.match(
            item, igdbGameId: suggested, igdbName: record.name ?? cleanName(item.romName), platform: platform, kind: "confirmed")
    }

    /// Whether confirming would give an existing Game Duplicate Versions. It warns, never blocks.
    public func confirmWouldGiveDuplicateVersions(_ item: ReviewItem) async throws -> Bool {
        guard let suggested = item.suggestedIgdbGameId, let record = try await igdb.games(ids: [Int(suggested)])[Int(suggested)],
            let game = try journal.gameID(igdbGameId: suggested, platformId: gamePlatform(system: item.systemId, game: record))
        else { return false }
        return try journal.wouldHaveDuplicateVersions(game, adding: item.romId)
    }

    /// Confirm all: every item whose names agree, skipping any answered meanwhile. Returns how many it confirmed.
    public func confirmAll() async throws -> Int {
        let items = try journal.reviewQueue().namesAgree
        _ = try await igdb.games(ids: items.compactMap(\.suggestedIgdbGameId).map(Int.init))  // one batch, then cached
        var confirmed = 0
        for item in items {
            do {
                try await confirm(item)
                confirmed += 1
            } catch ReviewError.alreadyMatched {
                // Answered on its own meanwhile.
            }
        }
        return confirmed
    }

    /// A result from Search IGDB…: a manual Match.
    @discardableResult
    public func choose(_ item: ReviewItem, igdbGameId: Int64, name: String, platform: IGDBPlatform) async throws -> GameID {
        try journal.match(item, igdbGameId: igdbGameId, igdbName: name, platform: platform, kind: "manual")
    }

    private func platform(_ id: Int64) async throws -> IGDBPlatform {
        if let known = try journal.platform(id) { return known }
        return try await igdb.platforms().first { $0.id == id } ?? IGDBPlatform(id: id, name: "Platform \(id)")
    }
}
