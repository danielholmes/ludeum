import Foundation
import GRDB

/// A ROM an Import changed, for the summary.
public struct ImportedROM: Sendable, Equatable {
    public let romName: String
    /// Its Game, if it has one.
    public let game: GameID?
}

/// What an ongoing Import changed. Activity alone doesn't count: an Import that changed nothing
/// else shows nothing.
public struct OngoingImportResult: Sendable, Equatable {
    /// New ROMs Matched automatically (added silently, but listed in the summary).
    public var matched: [ImportedROM] = []
    /// New ROMs waiting in the Review queue.
    public var sentToReview: [ImportedROM] = []
    /// ROMs that came back and rejoined their old Game.
    public var returned: [ImportedROM] = []
    public var goneMissing: [ImportedROM] = []

    public var changedSomething: Bool { !(matched.isEmpty && sentToReview.isEmpty && returned.isEmpty && goneMissing.isEmpty) }
}

/// An Import after the first: at launch, when OpenEmu quits, and by hand.
public final class OngoingImport: Sendable {
    let igdb: IGDBClient
    let matcher: Matcher
    let journal: JournalStore
    let backups: Backups?
    let snapshotFile: URL

    public init(igdb: IGDBClient, hasheous: HasheousClient, journal: JournalStore, backups: Backups?, snapshotFile: URL) {
        self.igdb = igdb
        matcher = Matcher(igdb: igdb, hasheous: hasheous)
        self.journal = journal
        self.backups = backups
        self.snapshotFile = snapshotFile
    }

    /// Reads OpenEmu and brings the journal up to date. Refused before the first Import, and when
    /// the library was rebuilt or replaced (a new store UUID).
    public func run(library: URL) async throws -> OngoingImportResult {
        guard try journal.firstImportDone() else { throw ImportError.firstImportNeeded }
        try OpenEmuLibrary.snapshot(library: library, to: snapshotFile)
        let snapshot = try OpenEmuLibrary.read(snapshot: snapshotFile, library: library)
        guard try journal.openEmuStoreUUID() == snapshot.storeUUID else { throw ImportError.libraryReplaced }

        // Which snapshot ROMs the journal already knows: by Z_PK, else (for one re-added in OpenEmu) by MD5.
        let known = try journal.knownROMs()
        let byPK = Dictionary(known.map { ($0.openEmuPk, $0) }, uniquingKeysWith: { a, _ in a })
        let snapshotPKs = Set(snapshot.roms.map(\.pk))
        var byMD5 = Dictionary(grouping: known.filter { !snapshotPKs.contains($0.openEmuPk) }, by: \.md5)
        var plan = OngoingImportPlan()
        var newROMs: [OpenEmuROMRecord] = []
        for rom in snapshot.roms {
            if let row = byPK[rom.pk] {
                plan.seen.append((row, rom))
            } else if let row = byMD5[rom.md5]?.popLast() {
                plan.seen.append((row, rom))
            } else {
                newROMs.append(rom)
            }
        }
        let seenIDs = Set(plan.seen.map(\.0.id))
        plan.gone = known.filter { !$0.missing && !seenIDs.contains($0.id) }

        let results = try await matcher.match(newROMs.map(\.matcherROM))
        let automatic = results.values.compactMap { if case .automatic(let id) = $0 { id } else { nil } }
        let records = try await igdb.games(ids: Array(Set(automatic)))
        let platformNames = automatic.isEmpty ? [:] : Dictionary(uniqueKeysWithValues: try await igdb.platforms().map { ($0.id, $0.name) })
        for rom in newROMs {
            let result = results[Int(rom.pk)] ?? .noSuggestion
            if case .automatic(let id) = result {
                let platform = gamePlatform(system: rom.system, game: records[id])
                plan.matched.append(
                    .init(
                        rom: rom, igdbGameId: Int64(id), igdbName: records[id]?.name ?? cleanName(rom.name), platformId: platform,
                        platformName: platformNames[platform] ?? "Platform \(platform)"))
            } else {
                plan.unmatched.append((rom, result))
            }
        }

        let touchesROMs = !newROMs.isEmpty || !plan.gone.isEmpty || plan.seen.contains { $0.0.missing || $0.0.openEmuPk != $0.1.pk }
        if touchesROMs { try backups?.backUp(journal, operation: .beforeImport) }
        return try journal.applyOngoingImport(plan)
    }
}

/// A ROM row the journal already has.
struct KnownROM {
    let id: Int64
    let openEmuPk: Int64
    let md5: String
    let fileName: String
    let missing: Bool
    let gameId: GameID?
}

struct OngoingImportPlan {
    struct Matched {
        let rom: OpenEmuROMRecord
        let igdbGameId: Int64
        let igdbName: String
        let platformId: Int64
        let platformName: String
    }

    /// Known ROMs still (or again) in OpenEmu, with their snapshot record.
    var seen: [(KnownROM, OpenEmuROMRecord)] = []
    /// Known, present ROMs no longer in OpenEmu.
    var gone: [KnownROM] = []
    var matched: [Matched] = []
    var unmatched: [(OpenEmuROMRecord, MatchResult)] = []
}

extension JournalStore {
    func openEmuStoreUUID() throws -> String? {
        try db.read { db in try String.fetchOne(db, sql: "SELECT storeUUID FROM openEmuLibrary WHERE id = 1") }
    }

    func knownROMs() throws -> [KnownROM] {
        try db.read { db in
            try Row.fetchAll(
                db, sql: "SELECT id, openEmuPk, md5, COALESCE(name, fileName) AS displayName, missing, gameId FROM rom ORDER BY id"
            ).map {
                KnownROM(
                    id: $0["id"], openEmuPk: $0["openEmuPk"], md5: $0["md5"], fileName: $0["displayName"], missing: $0["missing"],
                    gameId: $0["gameId"])
            }
        }
    }

    /// Writes an ongoing Import in one transaction: new ROMs, returning and missing ROMs, and
    /// Activity snapshot rows for ROMs that are new or whose Activity changed.
    func applyOngoingImport(_ plan: OngoingImportPlan) throws -> OngoingImportResult {
        let now = clock.now()
        return try db.write { db in
            var result = OngoingImportResult()
            try db.execute(sql: "INSERT INTO import (startedAt, isFirst) VALUES (?, 0)", arguments: [now])
            let importId = db.lastInsertedRowID

            func snapshotIfChanged(_ romId: Int64, _ rom: OpenEmuROMRecord) throws {
                guard rom.isPresent else { return }
                let last = try Row.fetchOne(
                    db,
                    sql:
                        "SELECT playCount, lastPlayedAt, playTimeSeconds FROM activitySnapshot WHERE romId = ? ORDER BY importId DESC LIMIT 1",
                    arguments: [romId])
                if let last, last["playCount"] as Int == rom.playCount, last["lastPlayedAt"] as Date? == rom.lastPlayedAt,
                    last["playTimeSeconds"] as Double == rom.playTimeSeconds
                {
                    return
                }
                try db.execute(
                    sql: "INSERT INTO activitySnapshot (importId, romId, playCount, lastPlayedAt, playTimeSeconds) VALUES (?, ?, ?, ?, ?)",
                    arguments: [importId, romId, rom.playCount, rom.lastPlayedAt, rom.playTimeSeconds])
            }

            func insertROM(_ rom: OpenEmuROMRecord, game: GameID?) throws -> Int64 {
                let parsed = ROMName(rom.name)
                try db.execute(
                    sql: """
                        INSERT INTO rom (openEmuPk, md5, fileName, name, systemId, missing, version, discNumber, discLabel, gameId, matchKind, matchedAt)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        rom.pk, rom.md5, rom.file?.lastPathComponent ?? rom.name, rom.name, rom.system, !rom.isPresent, parsed.version,
                        parsed.disc,
                        parsed.discLabel, game, game == nil ? nil : "automatic", game == nil ? nil : now,
                    ])
                let id = db.lastInsertedRowID
                try snapshotIfChanged(id, rom)
                return id
            }

            for (known, rom) in plan.seen {
                // A ROM that comes back rejoins its old Game with its old Match.
                if known.missing && rom.isPresent || known.openEmuPk != rom.pk {
                    result.returned.append(ImportedROM(romName: known.fileName, game: known.gameId))
                }
                try db.execute(
                    sql: "UPDATE rom SET openEmuPk = ?, md5 = ?, missing = ? WHERE id = ?",
                    arguments: [rom.pk, rom.md5, !rom.isPresent, known.id])
                if !known.missing && !rom.isPresent { result.goneMissing.append(ImportedROM(romName: known.fileName, game: known.gameId)) }
                try snapshotIfChanged(known.id, rom)
            }
            for known in plan.gone {
                try db.execute(sql: "UPDATE rom SET missing = 1 WHERE id = ?", arguments: [known.id])
                result.goneMissing.append(ImportedROM(romName: known.fileName, game: known.gameId))
            }
            for m in plan.matched {
                try db.execute(
                    sql: "INSERT INTO platform (id, name) VALUES (?, ?) ON CONFLICT (id) DO NOTHING",
                    arguments: [m.platformId, m.platformName])
                var game = try GameID.fetchOne(
                    db, sql: "SELECT id FROM game WHERE igdbGameId = ? AND platformId = ?", arguments: [m.igdbGameId, m.platformId])
                if game == nil {
                    try db.execute(
                        sql: "INSERT INTO game (platformId, name, igdbGameId, igdbName) VALUES (?, ?, ?, ?)",
                        arguments: [m.platformId, cleanName(m.rom.name), m.igdbGameId, m.igdbName])
                    game = db.lastInsertedRowID
                }
                _ = try insertROM(m.rom, game: game)
                result.matched.append(ImportedROM(romName: m.rom.name, game: game))
            }
            for (rom, match) in plan.unmatched {
                let id = try insertROM(rom, game: nil)
                if case .suggestion(let s) = match {
                    try db.execute(
                        sql:
                            "UPDATE rom SET suggestedIgdbGameId = ?, suggestionKind = ?, checksumIgdbGameId = ?, namesAgree = ? WHERE id = ?",
                        arguments: [s.gameID, s.source == .nameSearch ? "name" : "checksum", s.checksumGameID, s.namesAgree, id])
                }
                result.sentToReview.append(ImportedROM(romName: rom.name, game: nil))
            }
            return result
        }
    }
}
