import Foundation
import GRDB

/// Everything the first Import writes, worked out before the one transaction that writes it.
struct FirstImportPlan {
    struct PlannedGame {
        let igdbGameId: Int64
        let platformId: Int64
        let platformName: String
        let igdbName: String
        /// The cleaned No-Intro name.
        let name: String
        /// By `Z_PK`; the lowest wins where only one can.
        let roms: [OpenEmuROMRecord]
    }

    let storeUUID: String
    var games: [PlannedGame] = []
    var unmatched: [(OpenEmuROMRecord, MatchResult)] = []
    var startAnswers: [Int64: StartAnswer] = [:]

    init(storeUUID: String) { self.storeUUID = storeUUID }
}

extension LudeumStore {
    /// Whether the first Import has been committed.
    public func firstImportDone() throws -> Bool {
        try db.read { db in try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM import WHERE isFirst)")! }
    }

    /// Writes the first Import in one transaction: Games and their ROMs, OpenEmu's collections as
    /// Intent, Playthroughs, Childhood and Lists,
    /// unmatched ROMs with their suggestions and held data.
    func commitFirstImport(_ plan: FirstImportPlan) throws {
        let now = clock.now()
        try db.write { db in
            try db.execute(sql: "INSERT INTO import (startedAt, isFirst) VALUES (?, 1)", arguments: [now])
            try db.execute(
                sql:
                    "INSERT INTO openEmuLibrary (id, storeUUID) VALUES (1, ?) ON CONFLICT (id) DO UPDATE SET storeUUID = excluded.storeUUID",
                arguments: [plan.storeUUID])

            func insertROM(_ rom: OpenEmuROMRecord, game: GameID?) throws -> Int64 {
                let parsed = ROMName(rom.name)
                try db.execute(
                    sql: """
                        INSERT INTO rom (openEmuPk, md5, fileName, name, systemId, missing, version, discNumber, discLabel,
                            gameId, matchKind, matchedAt)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        rom.pk, rom.md5, rom.file?.lastPathComponent ?? rom.name, rom.name, rom.system, !rom.isPresent, parsed.version,
                        parsed.disc, parsed.discLabel, game, game == nil ? nil : "automatic", game == nil ? nil : now,
                    ])
                return db.lastInsertedRowID
            }

            for planned in plan.games {
                try db.execute(
                    sql: "INSERT INTO platform (id, name) VALUES (?, ?) ON CONFLICT (id) DO NOTHING",
                    arguments: [planned.platformId, planned.platformName])
                let existing = try GameID.fetchOne(
                    db, sql: "SELECT id FROM game WHERE igdbGameId = ? AND platformId = ?",
                    arguments: [planned.igdbGameId, planned.platformId])
                let game: GameID
                if let existing {
                    game = existing
                } else {
                    try db.execute(
                        sql: "INSERT INTO game (platformId, name, igdbGameId, igdbName) VALUES (?, ?, ?, ?)",
                        arguments: [planned.platformId, planned.name, planned.igdbGameId, planned.igdbName])
                    game = db.lastInsertedRowID
                }
                for rom in planned.roms { _ = try insertROM(rom, game: game) }

                // OpenEmu data, merged across the Game's ROMs. One in-progress Playthrough per Game, from
                // its lowest `Z_PK` ROM answered "Started on…".
                let start = planned.roms.lazy.compactMap { rom -> PartialDate? in
                    guard rom.collections.contains(SpecialCollection.current), case .started(let s) = plan.startAnswers[rom.pk] else {
                        return nil
                    }
                    return s
                }.first
                try Self.applyOpenEmuData(
                    db, game: game, collections: Set(planned.roms.flatMap(\.collections)),
                    start: start)
            }

            for (rom, match) in plan.unmatched {
                let romId = try insertROM(rom, game: nil)
                if case .suggestion(let s) = match {
                    try db.execute(
                        sql: """
                            UPDATE rom SET suggestedIgdbGameId = ?, suggestionKind = ?, checksumIgdbGameId = ?, namesAgree = ?
                            WHERE id = ?
                            """,
                        arguments: [s.gameID, s.source == .nameSearch ? "name" : "checksum", s.checksumGameID, s.namesAgree, romId])
                }
                let start: String? =
                    switch plan.startAnswers[rom.pk] {
                    case .started(let date): date.text
                    case .notPlaying: "notPlaying"
                    case nil: nil
                    }
                let collections = String(decoding: try JSONEncoder().encode(rom.collections.sorted()), as: UTF8.self)
                try db.execute(
                    sql: "INSERT INTO heldOpenEmuData (romId, collections, currentStart) VALUES (?, ?, ?)",
                    arguments: [romId, collections, start])
            }
        }
    }
}

extension LudeumStore {
    /// Applies a Game's OpenEmu data, from the first Import or a resolved Review queue item: the
    /// collections as Intent (undated, never over Intent it has), Childhood, an in-progress
    /// Playthrough from a `_Current` start date, and Lists.
    static func applyOpenEmuData(_ db: Database, game: GameID, collections: Set<String>, start: PartialDate?) throws {
        let intent: Intent? =
            collections.contains(SpecialCollection.upNext) ? .upNext : collections.contains(SpecialCollection.backlog) ? .backlog : nil
        if let intent {
            try db.execute(sql: "UPDATE game SET intent = ? WHERE id = ? AND intent IS NULL", arguments: [intent.rawValue, game])
        }
        if collections.contains(SpecialCollection.childhood) {
            try db.execute(sql: "UPDATE game SET childhood = 1 WHERE id = ?", arguments: [game])
        }
        if collections.contains(SpecialCollection.current), let start,
            try !Bool.fetchOne(
                db, sql: "SELECT EXISTS (SELECT 1 FROM playthrough WHERE gameId = ? AND outcome IS NULL)", arguments: [game])!
        {
            try db.execute(sql: "INSERT INTO playthrough (gameId, start) VALUES (?, ?)", arguments: [game, start.text])
        }
        for name in collections.subtracting(SpecialCollection.all).sorted() {
            try db.execute(sql: "INSERT OR IGNORE INTO list (name) VALUES (?)", arguments: [name])
            try db.execute(
                sql: "INSERT OR IGNORE INTO listGame (listId, gameId) SELECT id, ? FROM list WHERE name = ?", arguments: [game, name])
        }
    }
}

/// A Game's Platform for a ROM: the first of its OpenEmu system's IGDB platforms the IGDB game is on,
/// else the system's most likely one (`openemu.system.gb` covers Game Boy and Game Boy Color).
func gamePlatform(system: String, game: IGDBGame?) -> Int64 {
    let candidates = openEmuSystemPlatforms[system] ?? []
    let listed = Set((game?.record["platforms"]?.array ?? []).compactMap { $0["id"]?.int ?? $0.int })
    return Int64(candidates.first(where: listed.contains) ?? candidates.first ?? 0)
}
