import Foundation
import GRDB

/// A ROM an Import changed, for the summary.
public struct ImportedROM: Sendable, Equatable {
    public let romName: String
    /// Its Game, if it has one.
    public let game: GameID?
}

/// What an Import changed. An Import that changed nothing shows nothing.
public struct ImportResult: Sendable, Equatable {
    /// ROMs Matched automatically, new or from the Review queue, silently: the checksum and the name agree (ADR 0004).
    public var matched: [ImportedROM] = []
    /// New ROMs waiting in the Review queue.
    public var sentToReview: [ImportedROM] = []
    /// Missing ROMs that came back and rejoined their old Game, silently.
    public var returned: [ImportedROM] = []
    public var goneMissing: [ImportedROM] = []
    /// Whether any Game's Cover may have changed: a ROM's Box art did, or the ROMs a Game takes its Box art from did.
    /// When not, the Covers already shown stand.
    public var coversChanged = false

    /// Whether the summary has anything to say: ROMs sent to review or gone missing.
    public var changedSomething: Bool { !(sentToReview.isEmpty && goneMissing.isEmpty) }
}

public enum ImportError: Error, Equatable {
    /// The journal still has OpenEmu ROMs: `migrate-openemu` has to move them into ROM folders first.
    case openEmuMigrationNeeded
}

/// Reading the ROM folders into the journal: at launch, and by hand. It never changes the folders.
/// Refused until `migrate-openemu` has run.
public final class Import: Sendable {
    let matcher: Matcher
    let igdb: IGDBClient
    let journal: LudeumStore
    let backups: Backups?
    let boxArt: BoxArtImport
    let sevenZip: SevenZip?

    /// Without `libretro`, no ROM is looked up in libretro-thumbnails. Without `sevenZip`, a ROM in an archive has no
    /// checksum, so it's only ever suggested by name.
    public init(
        igdb: IGDBClient, hasheous: HasheousClient, journal: LudeumStore, backups: Backups?, libretro: LibretroThumbnails? = nil,
        sevenZip: SevenZip? = SevenZip.find()
    ) {
        boxArt = BoxArtImport(journal: journal, libretro: libretro)
        matcher = Matcher(igdb: igdb, hasheous: hasheous)
        self.igdb = igdb
        self.journal = journal
        self.backups = backups
        self.sevenZip = sevenZip
    }

    /// Reads the ROM folders and brings the journal up to date. A folder that can't be read is left alone.
    /// `writing` is awaited just before the write step (the backup and the one transaction), so the app can stop
    /// journal edits first; `wrote` just after it, before the Box art step, which never touches what I edit.
    public func run(
        romFolders: [ROMFolder], writing: @Sendable () async -> Void = {}, wrote: @Sendable () async -> Void = {}
    ) async throws -> ImportResult {
        guard try !journal.needsOpenEmuMigration() else { throw ImportError.openEmuMigrationNeeded }
        var plan = ImportPlan()
        var newROMs: [(platformId: Int64, file: FolderROMFile)] = []
        // Unmatched ROMs with no checksum yet: one imported before ROMs had them, or online-only until now.
        var unchecked: [(KnownFolderROM, FolderROMFile)] = []
        let knownInFolders = Dictionary(grouping: try journal.knownFolderROMs(), by: \.platformId)
        for folder in romFolders {
            guard let files = try? folder.scan() else { continue }
            let known = Dictionary(uniqueKeysWithValues: (knownInFolders[folder.platformId] ?? []).map { ($0.name, $0) })
            for file in files {
                if let row = known[file.name] {
                    plan.seen.append((row, file))
                    if row.gameId == nil && !row.hasChecksum { unchecked.append((row, file)) }
                } else {
                    newROMs.append((folder.platformId, file))
                }
            }
            let names = Set(files.map(\.name))
            plan.gone += known.values.filter { !$0.missing && !names.contains($0.name) }.sorted { $0.id < $1.id }
        }

        var newChecksums: [ROMChecksum?] = []
        for rom in newROMs { newChecksums.append(await ROMChecksum.of(rom.file, platformId: rom.platformId, sevenZip: sevenZip)) }
        var rechecks: [(known: KnownFolderROM, checksum: ROMChecksum)] = []
        for (known, file) in unchecked {
            if let checksum = await ROMChecksum.of(file, platformId: known.platformId, sevenZip: sevenZip) {
                rechecks.append((known, checksum))
            }
        }
        try Task.checkCancellation()

        // New ROMs first, then the rechecked ones, keyed by their place in that order.
        let toMatch =
            newROMs.enumerated().map { i, rom in
                ROMToMatch(
                    id: i, name: rom.file.name, md5: newChecksums[i]?.md5, crc: newChecksums[i]?.crc, platforms: [Int(rom.platformId)])
            }
            + rechecks.enumerated().map { i, rom in
                ROMToMatch(
                    id: newROMs.count + i, name: rom.known.name, md5: rom.checksum.md5, crc: rom.checksum.crc,
                    platforms: [Int(rom.known.platformId)])
            }
        let results = try await matcher.match(toMatch)
        let automatic = results.values.compactMap { if case .automatic(let id) = $0 { id } else { nil } }
        let games = try await igdb.games(ids: automatic)  // cached by the Matcher
        func resolved(_ id: Int, _ name: String) -> ResolvedMatch {
            switch results[id] ?? .noSuggestion {
            case .automatic(let game): .automatic(igdbGameId: Int64(game), igdbName: games[game]?.name ?? cleanName(name))
            case .suggestion(let s): .suggestion(s)
            case .noSuggestion: .noSuggestion
            }
        }
        plan.new = newROMs.enumerated().map { i, rom in
            NewFolderROM(platformId: rom.platformId, file: rom.file, checksum: newChecksums[i], match: resolved(i, rom.file.name))
        }
        plan.rechecked = rechecks.enumerated().map { i, rom in
            (rom.known, rom.checksum, resolved(newROMs.count + i, rom.known.name))
        }

        let touchesROMs =
            !plan.new.isEmpty || !plan.gone.isEmpty || !plan.rechecked.isEmpty
            || plan.seen.contains { $0.0.missing || $0.0.archived != $0.1.archived }
        try Task.checkCancellation()
        await writing()
        if touchesROMs { try backups?.backUp(journal, operation: .beforeImport) }
        var result = try journal.applyImport(plan)
        await wrote()
        let boxArtChanged = await boxArt.run()
        // A ROM's file changing counts: which of a Game's ROMs its Box art comes from can follow (a playlist comes first).
        result.coversChanged =
            boxArtChanged || !(result.matched.isEmpty && result.returned.isEmpty && result.goneMissing.isEmpty)
            || plan.seen.contains { known, file in known.fileState.fileName != file.fileName }
        return result
    }
}

/// A ROM the journal already has.
struct KnownFolderROM {
    let id: Int64
    let platformId: Int64
    let name: String
    let gameId: GameID?
    /// Whether it has an MD5 or a CRC32 to be looked up by.
    let hasChecksum: Bool
    /// What the journal last read of its files.
    let fileState: FileState
    var missing: Bool { fileState.missing }
    var archived: Bool { fileState.archived }

    struct FileState: Equatable {
        let missing: Bool
        let archived: Bool
        let fileName: String
        let needsPlaylist: Bool
        let inBothForms: Bool
    }
}

/// A Matcher result with the IGDB name an Automatic Match gives its Game.
enum ResolvedMatch {
    case automatic(igdbGameId: Int64, igdbName: String)
    case suggestion(Suggestion)
    case noSuggestion
}

struct NewFolderROM {
    let platformId: Int64
    let file: FolderROMFile
    let checksum: ROMChecksum?
    let match: ResolvedMatch
}

struct ImportPlan {
    /// Known ROMs still (or again) in their folder.
    var seen: [(KnownFolderROM, FolderROMFile)] = []
    /// Known, present ROMs whose files are all gone.
    var gone: [KnownFolderROM] = []
    /// New ROMs.
    var new: [NewFolderROM] = []
    /// Unmatched ROMs that have a checksum at last, matched again with it.
    var rechecked: [(KnownFolderROM, ROMChecksum, ResolvedMatch)] = []
}

extension LudeumStore {
    func knownFolderROMs() throws -> [KnownFolderROM] {
        try db.read(Self.knownFolderROMs)
    }

    private static func knownFolderROMs(_ db: Database) throws -> [KnownFolderROM] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT id, platformId, folderName, missing, archived, gameId, md5 IS NOT NULL OR crc IS NOT NULL AS hasChecksum,
                    fileName, needsPlaylist, inBothForms
                FROM rom WHERE folderName IS NOT NULL ORDER BY id
                """
        )
        .map {
            KnownFolderROM(
                id: $0["id"], platformId: $0["platformId"], name: $0["folderName"], gameId: $0["gameId"], hasChecksum: $0["hasChecksum"],
                fileState: KnownFolderROM.FileState(
                    missing: $0["missing"], archived: $0["archived"], fileName: $0["fileName"], needsPlaylist: $0["needsPlaylist"],
                    inBothForms: $0["inBothForms"]))
        }
    }

    /// Writes an Import in one transaction: new ROMs, rechecked ones, and returning and missing ones.
    func applyImport(_ plan: ImportPlan) throws -> ImportResult {
        let now = clock.now()
        let day = today()
        return try db.write { db in
            var result = ImportResult()
            try db.execute(sql: "INSERT INTO import (startedAt, isFirst) VALUES (?, 0)", arguments: [now])
            // A ROM whose files were read again while the Import ran (its Archive finished, say) stays as it was read
            // then: the Import's own reading of it is the older one.
            let fileStateNow = Dictionary(uniqueKeysWithValues: try Self.knownFolderROMs(db).map { ($0.id, $0.fileState) })
            // Extracting or archiving is silent; coming back or going missing is in the summary.
            for (known, file) in plan.seen where fileStateNow[known.id] == known.fileState {
                if known.missing { result.returned.append(ImportedROM(romName: known.name, game: known.gameId)) }
                try Self.setFolderROM(db, known.id, to: file)
            }
            for known in plan.gone where fileStateNow[known.id] == known.fileState {
                try Self.setFolderROM(db, known.id, to: nil)
                result.goneMissing.append(ImportedROM(romName: known.name, game: known.gameId))
            }
            for rom in plan.new {
                let file = rom.file
                // Recorded while the Import ran (an Add ROM): it stays as that left it.
                if try Bool.fetchOne(
                    db, sql: "SELECT EXISTS (SELECT 1 FROM rom WHERE platformId = ? AND folderName = ?)",
                    arguments: [rom.platformId, file.name]) == true
                {
                    continue
                }
                let parsed = ROMName(file.name)
                try ROMPlatform.ensureKnown(db, rom.platformId)
                try db.execute(
                    sql: """
                        INSERT INTO rom
                            (folderName, md5, crc, archived, fileName, name, platformId, version, discNumber, discLabel, needsPlaylist,
                             inBothForms, regions)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        file.name, rom.checksum?.md5, rom.checksum?.crc, file.archived, file.fileName, file.name, rom.platformId,
                        parsed.version, parsed.disc, parsed.discLabel, file.needsPlaylist, file.inBothForms,
                        Regions.encode(parsed.regionNames),
                    ])
                let id = db.lastInsertedRowID
                if let game = try Self.apply(db, rom.match, to: id, named: file.name, on: rom.platformId, day: day, now: now) {
                    result.matched.append(ImportedROM(romName: file.name, game: game))
                } else {
                    result.sentToReview.append(ImportedROM(romName: file.name, game: nil))
                }
            }
            for (known, checksum, match) in plan.rechecked {
                // Answered in the Review queue while the Import ran: its answer stands.
                guard try Bool.fetchOne(db, sql: "SELECT gameId IS NULL FROM rom WHERE id = ?", arguments: [known.id]) == true else {
                    continue
                }
                try db.execute(sql: "UPDATE rom SET md5 = ?, crc = ? WHERE id = ?", arguments: [checksum.md5, checksum.crc, known.id])
                if let game = try Self.apply(db, match, to: known.id, named: known.name, on: known.platformId, day: day, now: now) {
                    result.matched.append(ImportedROM(romName: known.name, game: game))
                }
            }
            return result
        }
    }

    /// Matches an unmatched ROM automatically, returning its Game, or leaves it in the Review queue with its suggestion.
    private static func apply(
        _ db: Database, _ match: ResolvedMatch, to rom: Int64, named name: String, on platformId: Int64, day: String, now: Date
    ) throws -> GameID? {
        let suggestion: Suggestion?
        switch match {
        case .automatic(let igdbGameId, let igdbName):
            return try matchToIGDBGame(
                db, rom: rom, romName: name, igdbGameId: igdbGameId, igdbName: igdbName, platformId: platformId, kind: "automatic",
                day: day, now: now)
        case .suggestion(let s): suggestion = s
        case .noSuggestion: suggestion = nil
        }
        try db.execute(
            sql: "UPDATE rom SET suggestedIgdbGameId = ?, suggestionKind = ?, checksumIgdbGameId = ?, namesAgree = ? WHERE id = ?",
            arguments: [
                suggestion?.gameID, suggestion.map { $0.source == .nameSearch ? "name" : "checksum" }, suggestion?.checksumGameID,
                suggestion?.namesAgree, rom,
            ])
        return nil
    }
}

extension LudeumStore {
    /// Re-reads one Game's ROMs: archived, ready, or missing. New files wait for an Import.
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

    /// Reads one ROM's files again from its ROM folder, as `checkROMsAgain` does for a Game's: after an Archive, Unarchive
    /// or Compact, whether or not the ROM is Matched yet.
    public func checkROMAgain(_ rom: Int64, in folder: ROMFolder) throws {
        guard
            let name = try db.read({ db in
                try String.fetchOne(
                    db, sql: "SELECT folderName FROM rom WHERE id = ? AND platformId = ?", arguments: [rom, folder.platformId])
            })
        else { return }
        let file = try folder.rom(named: name)
        try db.write { db in try Self.setFolderROM(db, rom, to: file) }
    }

    /// A ROM's state from its files: nil is missing (keeping whether it was archived).
    static func setFolderROM(_ db: Database, _ id: Int64, to file: FolderROMFile?) throws {
        if let file {
            try db.execute(
                sql: "UPDATE rom SET missing = 0, archived = ?, fileName = ?, needsPlaylist = ?, inBothForms = ? WHERE id = ?",
                arguments: [file.archived, file.fileName, file.needsPlaylist, file.inBothForms, id])
        } else {
            try db.execute(sql: "UPDATE rom SET missing = 1 WHERE id = ?", arguments: [id])
        }
    }
}
