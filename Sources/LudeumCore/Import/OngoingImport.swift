import Foundation
import GRDB

/// A ROM an Import changed, for the summary.
public struct ImportedROM: Sendable, Equatable {
    public let romName: String
    /// Its Game, if it has one.
    public let game: GameID?
}

/// What an ongoing Import changed. An Import that changed nothing shows nothing.
public struct OngoingImportResult: Sendable, Equatable {
    /// New ROMs Matched automatically (added silently, but listed in the summary).
    public var matched: [ImportedROM] = []
    /// New ROMs waiting in the Review queue.
    public var sentToReview: [ImportedROM] = []
    /// Missing ROMs that came back and rejoined their old Game, silently.
    public var returned: [ImportedROM] = []
    public var goneMissing: [ImportedROM] = []

    /// Whether the summary has anything to say: ROMs added, matched, sent to review or gone missing.
    public var changedSomething: Bool { !(matched.isEmpty && sentToReview.isEmpty && goneMissing.isEmpty) }
}

/// An Import after the first: at launch, when OpenEmu quits, and by hand.
public final class OngoingImport: Sendable {
    let igdb: IGDBClient
    let matcher: Matcher
    let journal: LudeumStore
    let backups: Backups?
    let snapshotFile: URL
    let boxArt: BoxArtImport

    /// Without `libretro`, no ROM is looked up in libretro-thumbnails (OpenEmu's Box art is still cached).
    public init(
        igdb: IGDBClient, hasheous: HasheousClient, journal: LudeumStore, backups: Backups?, snapshotFile: URL,
        libretro: LibretroThumbnails? = nil
    ) {
        self.igdb = igdb
        boxArt = BoxArtImport(journal: journal, libretro: libretro)
        matcher = Matcher(igdb: igdb, hasheous: hasheous)
        self.journal = journal
        self.backups = backups
        self.snapshotFile = snapshotFile
    }

    /// Reads OpenEmu and the ROM folders and brings the journal up to date. Refused before the first Import, and when
    /// the library was rebuilt or replaced (a new store UUID). `writing` is awaited just before the
    /// write step (the backup and the one transaction), so the app can stop journal edits first;
    /// `wrote` just after it, before the Box art step, which never touches what I edit.
    public func run(
        library: URL, romFolders: [ROMFolder] = [], progress: @escaping @Sendable (ImportPhase, Double) -> Void = { _, _ in },
        writing: @Sendable () async -> Void = {}, wrote: @Sendable () async -> Void = {}
    ) async throws
        -> OngoingImportResult
    {
        guard try journal.firstImportDone() else { throw ImportError.firstImportNeeded }
        progress(.snapshot, 0)
        try OpenEmuLibrary.snapshot(library: library, to: snapshotFile)
        let snapshot = try OpenEmuLibrary.read(snapshot: snapshotFile, library: library)
        guard try journal.openEmuStoreUUID() == snapshot.storeUUID else { throw ImportError.libraryReplaced }

        // Which snapshot ROMs the journal already knows: by Z_PK, else (for one re-added in OpenEmu) by MD5.
        let known = try journal.knownROMs()
        let byPK = Dictionary(known.map { ($0.openEmuPk, $0) }, uniquingKeysWith: { a, _ in a })
        // Rows OpenEmu no longer has under the same Z_PK and MD5 can be claimed by MD5.
        let snapshotKeys = Set(snapshot.roms.map { "\($0.pk):\($0.md5)" })
        var byMD5 = Dictionary(grouping: known.filter { !snapshotKeys.contains("\($0.openEmuPk):\($0.md5)") }, by: \.md5)
        var plan = OngoingImportPlan()
        var newROMs: [OpenEmuROMRecord] = []
        for rom in snapshot.roms {
            if let row = byPK[rom.pk], row.md5 == rom.md5 {
                plan.seen.append((row, rom))
            } else if let row = byMD5[rom.md5]?.popLast() {
                plan.seen.append((row, rom))
            } else if ROMPlatform.defaultPlatform(system: rom.system) != nil {
                // A ROM on a system with no Platform has nowhere to go, so it isn't imported.
                newROMs.append(rom)
            }
        }
        let seenIDs = Set(plan.seen.map(\.0.id))
        plan.gone = known.filter { !$0.missing && !seenIDs.contains($0.id) }

        // ROM folders: known ROMs by name; one that can't be read is left alone.
        var newFolderROMs: [(platformId: Int64, file: FolderROMFile)] = []
        let knownInFolders = Dictionary(grouping: try journal.knownFolderROMs(), by: \.platformId)
        for folder in romFolders {
            guard let files = try? folder.scan() else { continue }
            let known = Dictionary(uniqueKeysWithValues: (knownInFolders[folder.platformId] ?? []).map { ($0.name, $0) })
            for file in files {
                if let row = known[file.name] {
                    plan.folderSeen.append((row, file))
                } else {
                    newFolderROMs.append((folder.platformId, file))
                }
            }
            let names = Set(files.map(\.name))
            plan.folderGone += known.values.filter { !$0.missing && !names.contains($0.name) }.sorted { $0.id < $1.id }
        }

        progress(.lookups, 0)
        let openEmuLookups = newROMs.count
        let lookups = openEmuLookups + newFolderROMs.count
        let results = try await matcher.match(newROMs.map(\.matcherROM)) { done, _ in
            progress(.lookups, lookups == 0 ? 1 : Double(done) / Double(lookups))
        }
        // No checksum, so a folder ROM is only ever suggested: always the Review queue (ADR 0004).
        let folderResults = try await matcher.match(
            newFolderROMs.enumerated().map { i, rom in
                OpenEmuROM(id: i, name: rom.file.name, openVGDBTitle: nil, system: "", md5: "", file: nil, platforms: [Int(rom.platformId)])
            }
        ) { done, _ in
            progress(.lookups, Double(openEmuLookups + done) / Double(max(lookups, 1)))
        }
        plan.folderNew = newFolderROMs.enumerated().map { i, rom in (rom.platformId, rom.file, folderResults[i] ?? .noSuggestion) }
        progress(.matching, 0)
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

        let touchesROMs =
            !newROMs.isEmpty || !plan.gone.isEmpty || plan.seen.contains { $0.0.missing || $0.0.openEmuPk != $0.1.pk }
            || !plan.folderNew.isEmpty || !plan.folderGone.isEmpty
            || plan.folderSeen.contains { $0.0.missing || $0.0.archived != $0.1.archived }
        try Task.checkCancellation()
        progress(.review, 1)
        await writing()
        if touchesROMs { try backups?.backUp(journal, operation: .beforeImport) }
        let result = try journal.applyOngoingImport(plan)
        await wrote()
        await boxArt.run()
        return result
    }
}

/// A ROM folder's ROM the journal already has.
struct KnownFolderROM {
    let id: Int64
    let platformId: Int64
    let name: String
    let missing: Bool
    let archived: Bool
    let gameId: GameID?
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
    /// Known ROM folder ROMs still (or again) in their folder.
    var folderSeen: [(KnownFolderROM, FolderROMFile)] = []
    /// Known, present ROM folder ROMs whose files are all gone.
    var folderGone: [KnownFolderROM] = []
    /// New ROM folder ROMs, for the Review queue.
    var folderNew: [(platformId: Int64, file: FolderROMFile, match: MatchResult)] = []
}

extension LudeumStore {
    func openEmuStoreUUID() throws -> String? {
        try db.read { db in try String.fetchOne(db, sql: "SELECT storeUUID FROM openEmuLibrary WHERE id = 1") }
    }

    func knownFolderROMs() throws -> [KnownFolderROM] {
        try db.read { db in
            try Row.fetchAll(
                db, sql: "SELECT id, platformId, folderName, missing, archived, gameId FROM rom WHERE folderName IS NOT NULL ORDER BY id"
            )
            .map {
                KnownFolderROM(
                    id: $0["id"], platformId: $0["platformId"], name: $0["folderName"], missing: $0["missing"], archived: $0["archived"],
                    gameId: $0["gameId"])
            }
        }
    }

    func knownROMs() throws -> [KnownROM] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql:
                    "SELECT id, openEmuPk, md5, COALESCE(name, fileName) AS displayName, missing, gameId FROM rom WHERE openEmuPk IS NOT NULL ORDER BY id"
            ).map {
                KnownROM(
                    id: $0["id"], openEmuPk: $0["openEmuPk"], md5: $0["md5"], fileName: $0["displayName"], missing: $0["missing"],
                    gameId: $0["gameId"])
            }
        }
    }

    /// Writes an ongoing Import in one transaction: new ROMs, returning and missing ROMs.
    func applyOngoingImport(_ plan: OngoingImportPlan) throws -> OngoingImportResult {
        let now = clock.now()
        return try db.write { db in
            var result = OngoingImportResult()
            try db.execute(sql: "INSERT INTO import (startedAt, isFirst) VALUES (?, 0)", arguments: [now])

            func insertROM(_ rom: OpenEmuROMRecord, game: GameID?, platformId: Int64) throws -> Int64 {
                let parsed = ROMName(rom.name)
                try ROMPlatform.ensureKnown(db, platformId)
                try db.execute(
                    sql: """
                        INSERT INTO rom (openEmuPk, md5, fileName, name, platformId, missing, version, discNumber, discLabel, gameId, matchKind, matchedAt)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        rom.pk, rom.md5, rom.file?.lastPathComponent ?? rom.name, rom.name, platformId, !rom.isPresent, parsed.version,
                        parsed.disc,
                        parsed.discLabel, game, game == nil ? nil : "automatic", game == nil ? nil : now,
                    ])
                return db.lastInsertedRowID
            }

            for (known, rom) in plan.seen {
                // A missing ROM that comes back rejoins its old Game with its old Match, silently.
                if known.missing && rom.isPresent {
                    result.returned.append(ImportedROM(romName: known.fileName, game: known.gameId))
                }
                try db.execute(
                    sql: "UPDATE rom SET openEmuPk = ?, md5 = ?, missing = ? WHERE id = ?",
                    arguments: [rom.pk, rom.md5, !rom.isPresent, known.id])
                if !known.missing && !rom.isPresent { result.goneMissing.append(ImportedROM(romName: known.fileName, game: known.gameId)) }
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
                _ = try insertROM(m.rom, game: game, platformId: m.platformId)
                result.matched.append(ImportedROM(romName: m.rom.name, game: game))
            }
            func suggest(_ match: MatchResult, rom id: Int64) throws {
                guard case .suggestion(let s) = match else { return }
                try db.execute(
                    sql: "UPDATE rom SET suggestedIgdbGameId = ?, suggestionKind = ?, checksumIgdbGameId = ?, namesAgree = ? WHERE id = ?",
                    arguments: [s.gameID, s.source == .nameSearch ? "name" : "checksum", s.checksumGameID, s.namesAgree, id])
            }
            for (rom, match) in plan.unmatched {
                try suggest(match, rom: try insertROM(rom, game: nil, platformId: ROMPlatform.defaultPlatform(system: rom.system)!))
                result.sentToReview.append(ImportedROM(romName: rom.name, game: nil))
            }
            // ROM folders: extracting or archiving is silent; coming back or going missing is as for OpenEmu's.
            for (known, file) in plan.folderSeen {
                if known.missing { result.returned.append(ImportedROM(romName: known.name, game: known.gameId)) }
                try Self.setFolderROM(db, known.id, to: file)
            }
            for known in plan.folderGone {
                try Self.setFolderROM(db, known.id, to: nil)
                result.goneMissing.append(ImportedROM(romName: known.name, game: known.gameId))
            }
            for (platformId, file, match) in plan.folderNew {
                let parsed = ROMName(file.name)
                try ROMPlatform.ensureKnown(db, platformId)
                try db.execute(
                    sql: """
                        INSERT INTO rom (folderName, archived, fileName, name, platformId, version, discNumber, discLabel)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        file.name, file.archived, file.fileName, file.name, platformId,
                        parsed.version, parsed.disc, parsed.discLabel,
                    ])
                try suggest(match, rom: db.lastInsertedRowID)
                result.sentToReview.append(ImportedROM(romName: file.name, game: nil))
            }
            return result
        }
    }
}

extension LudeumStore {
    /// Re-reads one Game's ROM folder ROMs: archived, ready, or missing. New files wait for an Import.
    /// Throws when a folder can't be read, rather than marking its ROMs missing.
    public func checkROMsAgain(_ game: GameID, in folders: [ROMFolder]) throws {
        let roms = try db.read { db in
            try Row.fetchAll(
                db, sql: "SELECT id, platformId, folderName FROM rom WHERE gameId = ? AND folderName IS NOT NULL", arguments: [game])
        }
        var scans: [Int64: [FolderROMFile]] = [:]
        for folder in folders where roms.contains(where: { $0["platformId"] == folder.platformId }) {
            scans[folder.platformId] = try folder.scan()
        }
        try db.write { db in
            for row in roms {
                guard let files = scans[row["platformId"]] else { continue }
                let name: String = row["folderName"]
                try Self.setFolderROM(db, row["id"], to: files.first { $0.name == name })
            }
        }
    }

    /// A ROM folder ROM's state from its files: nil is missing (keeping whether it was archived).
    static func setFolderROM(_ db: Database, _ id: Int64, to file: FolderROMFile?) throws {
        if let file {
            try db.execute(
                sql: "UPDATE rom SET missing = 0, archived = ?, fileName = ? WHERE id = ?",
                arguments: [file.archived, file.fileName, id])
        } else {
            try db.execute(sql: "UPDATE rom SET missing = 1 WHERE id = ?", arguments: [id])
        }
    }
}
