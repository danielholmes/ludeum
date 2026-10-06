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
    /// New ROMs, all waiting in the Review queue: with no checksum, none is Matched automatically.
    public var sentToReview: [ImportedROM] = []
    /// Missing ROMs that came back and rejoined their old Game, silently.
    public var returned: [ImportedROM] = []
    public var goneMissing: [ImportedROM] = []

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
    let journal: LudeumStore
    let backups: Backups?
    let boxArt: BoxArtImport

    /// Without `libretro`, no ROM is looked up in libretro-thumbnails.
    public init(igdb: IGDBClient, hasheous: HasheousClient, journal: LudeumStore, backups: Backups?, libretro: LibretroThumbnails? = nil) {
        boxArt = BoxArtImport(journal: journal, libretro: libretro)
        matcher = Matcher(igdb: igdb, hasheous: hasheous)
        self.journal = journal
        self.backups = backups
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
        let knownInFolders = Dictionary(grouping: try journal.knownFolderROMs(), by: \.platformId)
        for folder in romFolders {
            guard let files = try? folder.scan() else { continue }
            let known = Dictionary(uniqueKeysWithValues: (knownInFolders[folder.platformId] ?? []).map { ($0.name, $0) })
            for file in files {
                if let row = known[file.name] {
                    plan.seen.append((row, file))
                } else {
                    newROMs.append((folder.platformId, file))
                }
            }
            let names = Set(files.map(\.name))
            plan.gone += known.values.filter { !$0.missing && !names.contains($0.name) }.sorted { $0.id < $1.id }
        }

        // No checksum, so a new ROM is only ever suggested: always the Review queue (ADR 0004).
        let results = try await matcher.match(
            newROMs.enumerated().map { i, rom in
                ROMToMatch(id: i, name: rom.file.name, platforms: [Int(rom.platformId)])
            })
        plan.new = newROMs.enumerated().map { i, rom in (rom.platformId, rom.file, results[i] ?? .noSuggestion) }

        let touchesROMs =
            !plan.new.isEmpty || !plan.gone.isEmpty || plan.seen.contains { $0.0.missing || $0.0.archived != $0.1.archived }
        try Task.checkCancellation()
        await writing()
        if touchesROMs { try backups?.backUp(journal, operation: .beforeImport) }
        let result = try journal.applyImport(plan)
        await wrote()
        await boxArt.run()
        return result
    }
}

/// A ROM the journal already has.
struct KnownFolderROM {
    let id: Int64
    let platformId: Int64
    let name: String
    let missing: Bool
    let archived: Bool
    let gameId: GameID?
}

struct ImportPlan {
    /// Known ROMs still (or again) in their folder.
    var seen: [(KnownFolderROM, FolderROMFile)] = []
    /// Known, present ROMs whose files are all gone.
    var gone: [KnownFolderROM] = []
    /// New ROMs, for the Review queue.
    var new: [(platformId: Int64, file: FolderROMFile, match: MatchResult)] = []
}

extension LudeumStore {
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

    /// Writes an Import in one transaction: new ROMs, and returning and missing ones.
    func applyImport(_ plan: ImportPlan) throws -> ImportResult {
        let now = clock.now()
        return try db.write { db in
            var result = ImportResult()
            try db.execute(sql: "INSERT INTO import (startedAt, isFirst) VALUES (?, 0)", arguments: [now])
            // Extracting or archiving is silent; coming back or going missing is in the summary.
            for (known, file) in plan.seen {
                if known.missing { result.returned.append(ImportedROM(romName: known.name, game: known.gameId)) }
                try Self.setFolderROM(db, known.id, to: file)
            }
            for known in plan.gone {
                try Self.setFolderROM(db, known.id, to: nil)
                result.goneMissing.append(ImportedROM(romName: known.name, game: known.gameId))
            }
            for (platformId, file, match) in plan.new {
                let parsed = ROMName(file.name)
                try ROMPlatform.ensureKnown(db, platformId)
                try db.execute(
                    sql: """
                        INSERT INTO rom (folderName, archived, fileName, name, platformId, version, discNumber, discLabel, needsPlaylist)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        file.name, file.archived, file.fileName, file.name, platformId,
                        parsed.version, parsed.disc, parsed.discLabel, file.needsPlaylist,
                    ])
                if case .suggestion(let s) = match {
                    try db.execute(
                        sql:
                            "UPDATE rom SET suggestedIgdbGameId = ?, suggestionKind = ?, checksumIgdbGameId = ?, namesAgree = ? WHERE id = ?",
                        arguments: [
                            s.gameID, s.source == .nameSearch ? "name" : "checksum", s.checksumGameID, s.namesAgree, db.lastInsertedRowID,
                        ])
                }
                result.sentToReview.append(ImportedROM(romName: file.name, game: nil))
            }
            return result
        }
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
        let file = try folder.scan().first { $0.name == name }
        try db.write { db in try Self.setFolderROM(db, rom, to: file) }
    }

    /// A ROM's state from its files: nil is missing (keeping whether it was archived).
    static func setFolderROM(_ db: Database, _ id: Int64, to file: FolderROMFile?) throws {
        if let file {
            try db.execute(
                sql: "UPDATE rom SET missing = 0, archived = ?, fileName = ?, needsPlaylist = ? WHERE id = ?",
                arguments: [file.archived, file.fileName, file.needsPlaylist, id])
        } else {
            try db.execute(sql: "UPDATE rom SET missing = 1 WHERE id = ?", arguments: [id])
        }
    }
}
