import Foundation
import GRDB

/// `migrate-openemu`: run once, by hand, to move every OpenEmu ROM the journal has into its Platform's
/// ROM folder, so the journal no longer needs OpenEmu (ADR 0009). No journal data is lost.
///
/// Order: refuse on a journal already migrated, while OpenEmu is running, and without the Data folder; plan and check
/// everything (the dry run stops there); take a `before-migration` backup; copy OpenEmu's battery saves, unchanged, into
/// `OpenEmu Battery Saves archive/` in the Data folder; move the files into the Data folder's ROM folders, logging each
/// old path → new path beside the backup; then rewrite the ROM rows in one
/// transaction, after which the journal drops OpenEmu's columns and link tables; last, delete OpenEmu's cached Box art and look each
/// moved ROM up in libretro again (a miss keeps its old Box art; a failed lookup never fails the migration).
/// A failed move stops before that transaction: restore nothing, and the log says what moved. Undo is restoring the backup and moving the logged files back.
public struct OpenEmuMigration {
    let journal: LudeumStore
    let library: URL
    let folder: LudeumFolder
    let backups: Backups
    let isOpenEmuRunning: () -> Bool
    let libretro: LibretroThumbnails?

    /// `folder`'s Data folder gets the ROM folders, the backup and the battery-save archive.
    public init(
        journal: LudeumStore, library: URL, folder: LudeumFolder, isOpenEmuRunning: @escaping () -> Bool,
        libretro: LibretroThumbnails?
    ) {
        self.journal = journal
        self.library = library
        self.folder = folder
        backups = Backups(folder: folder.backups, clock: journal.clock, timeZone: journal.calendar.timeZone)
        self.isOpenEmuRunning = isOpenEmuRunning
        self.libretro = libretro
    }

    /// The dry run: everything the migration would do, and anything that stops it. Changes nothing but the `ROMs/` and
    /// `Backups/` folders, made in the Data folder if they're missing. Throws `DataFolderMissing` without it.
    public func plan() throws -> OpenEmuMigrationPlan {
        guard try journal.needsOpenEmuMigration() else { throw OpenEmuMigrationError.alreadyMigrated }
        guard !isOpenEmuRunning() else { throw OpenEmuMigrationError.openEmuRunning }
        try folder.checkData()
        let snapshotFile = FileManager.default.temporaryDirectory.appending(path: "ludeum-migrate-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: snapshotFile) }
        try OpenEmuLibrary.snapshot(library: library, to: snapshotFile)
        let snapshot = try OpenEmuLibrary.read(snapshot: snapshotFile, library: library)
        let inOpenEmu = Dictionary(snapshot.roms.map { ($0.pk, $0) }, uniquingKeysWith: { a, _ in a })

        let rows = try journal.db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT r.id, r.openEmuPk, r.fileName, r.platformId, g.platformId AS gamePlatformId
                    FROM rom r LEFT JOIN game g ON g.id = r.gameId WHERE r.openEmuPk IS NOT NULL ORDER BY r.id
                    """)
        }
        let taken = try journal.db.read { db in
            Set(
                try Row.fetchAll(db, sql: "SELECT platformId, folderName FROM rom WHERE folderName IS NOT NULL").map {
                    Key(platformId: $0["platformId"], name: $0["folderName"])
                })
        }

        var plan = OpenEmuMigrationPlan()
        var keys: [Key: [String]] = [:]
        var destinations: [URL: URL] = [:]
        for row in rows {
            let pk: Int64 = row["openEmuPk"]
            let storedFileName: String = row["fileName"]
            let record = inOpenEmu[pk]
            // By its Game's Platform; an unmatched ROM keeps the one it was given, its system's most likely.
            let platformId: Int64 = row["gamePlatformId"] ?? row["platformId"]
            let label = record?.file?.lastPathComponent ?? storedFileName
            if let record, let candidates = openEmuSystemPlatforms[record.system], !candidates.contains(Int(platformId)) {
                plan.platformMismatches.append("\(label): \(record.system) can't hold a Game on Platform \(platformId)")
                continue
            }
            // With no system to check its Platform against, it's listed rather than passed over.
            if record == nil { plan.goneFromOpenEmu.append("\(label): Platform \(platformId)") }
            guard let folder = self.folder.romFolder(platform: platformId) else {
                plan.noROMFolder.append("\(label): Platform \(platformId) has no ROM folder")
                continue
            }
            let main = record.flatMap { $0.isPresent ? $0.file : nil }
            let fileName = main?.lastPathComponent ?? storedFileName
            let name = (fileName as NSString).deletingPathExtension
            let key = Key(platformId: platformId, name: name)
            keys[key, default: []].append(label)
            if taken.contains(key) { plan.clashes.append("\(folder.lastPathComponent)/\(name): already a ROM there") }
            if main != nil, ROMFolder.platform(platformId, folder)?.reads(fileName: fileName) != true {
                let ext = (fileName as NSString).pathExtension.lowercased()
                plan.unreadableFiles.append("\(folder.lastPathComponent)/\(fileName): its ROM folder doesn't read .\(ext) files")
            }

            var files: [OpenEmuMigrationPlan.Move] = []
            if let main {
                let base = main.deletingLastPathComponent().standardizedFileURL.path(percentEncoded: false)
                for file in ROMFiles.files(of: main) {
                    let path = file.standardizedFileURL.path(percentEncoded: false)
                    let relative =
                        path.hasPrefix(base) ? String(path.dropFirst(base.count)).trimmingPrefix("/").description : file.lastPathComponent
                    let to = folder.appending(path: relative)
                    if let other = destinations[to], other != file {
                        plan.clashes.append("\(folder.lastPathComponent)/\(relative): two ROMs' files")
                    } else if destinations[to] == nil {
                        destinations[to] = file
                        if FileManager.default.fileExists(atPath: to.path(percentEncoded: false)) {
                            plan.clashes.append("\(folder.lastPathComponent)/\(relative): a file is already there")
                        }
                        files.append(.init(from: file, to: to))
                    }
                }
            }
            plan.roms.append(
                .init(romId: row["id"], platformId: platformId, folderName: name, fileName: fileName, missing: main == nil, moves: files))
        }
        for (key, labels) in keys where labels.count > 1 {
            plan.clashes.append("\(key.name) on Platform \(key.platformId): \(labels.joined(separator: ", "))")
        }
        let folders = Set(plan.roms.flatMap { $0.moves.map { $0.to.deletingLastPathComponent() } })
        plan.unwritableFolders = folders.filter { !Self.canWrite(into: $0) }.sorted { $0.path < $1.path }
        let known = Set(rows.map { $0["openEmuPk"] as Int64 })
        plan.leftInOpenEmu = snapshot.roms.filter { !known.contains($0.pk) && $0.isPresent }.compactMap(\.file)
        plan.batterySaves = batterySaveFolders()
        // A run that failed part-way left one: moved aside by hand, so an older copy is never mixed in or replaced.
        if FileManager.default.fileExists(atPath: folder.batterySaveArchive.path(percentEncoded: false)) {
            plan.clashes.append("\(folder.batterySaveArchive.lastPathComponent): already in the Data folder")
        }
        plan.clashes.sort()
        return plan
    }

    /// Runs the migration. Throws `blocked` (with the plan) when the dry run found anything that stops it,
    /// before anything is touched.
    @discardableResult
    public func run() async throws -> OpenEmuMigrationResult {
        let plan = try plan()
        guard plan.isRunnable else { throw OpenEmuMigrationError.blocked(plan) }
        let backup = try backups.backUp(journal, operation: .beforeMigration)
        let log = backup.url.deletingPathExtension().appendingPathExtension("moves.log")
        let archive = folder.batterySaveArchive
        try archiveBatterySaves(plan.batterySaves, into: archive)

        FileManager.default.createFile(atPath: log.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        for rom in plan.roms {
            for move in rom.moves {
                do {
                    try FileManager.default.createDirectory(at: move.to.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.moveItem(at: move.from, to: move.to)
                } catch {
                    throw OpenEmuMigrationError.moveFailed(file: move.from, log: log, underlying: String(describing: error))
                }
                try handle.write(
                    contentsOf: Data("\(move.from.path(percentEncoded: false))\t\(move.to.path(percentEncoded: false))\n".utf8))
            }
        }

        // Each ROM is to be looked up in libretro again by its new name: one whose lookup doesn't run below waits
        // for the next Import.
        try await journal.db.write { db in
            for rom in plan.roms {
                try ROMPlatform.ensureKnown(db, rom.platformId)
                try db.execute(
                    sql: """
                        UPDATE rom SET openEmuPk = NULL, platformId = ?, folderName = ?, fileName = ?, name = ?, missing = ?,
                            libretroLookedUp = 0
                        WHERE id = ?
                        """,
                    arguments: [rom.platformId, rom.folderName, rom.fileName, rom.folderName, rom.missing, rom.romId])
            }
        }
        // No ROM is OpenEmu's now, so the journal takes the migrations it held back: OpenEmu's columns and tables go.
        try journal.completeMigrations()
        // Box art: OpenEmu's cached copies go, and libretro is looked up again by the new names.
        libretro?.cache.removeOpenEmuBoxArt()
        try? await BoxArtImport(journal: journal, libretro: libretro).lookUp(plan.roms.map(\.romId))
        return OpenEmuMigrationResult(plan: plan, backup: backup.url, log: log, batterySaveArchive: archive)
    }

    // MARK: Battery saves

    /// OpenEmu keeps each core's battery saves in `<Core>/Battery Saves/` beside its library.
    private func batterySaveFolders() -> [URL] {
        let support = library.deletingLastPathComponent()
        let cores = (try? FileManager.default.contentsOfDirectory(at: support, includingPropertiesForKeys: nil)) ?? []
        return cores.map { $0.appending(path: "Battery Saves", directoryHint: .isDirectory) }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.path < $1.path }
    }

    /// Copies each core's saves unchanged, keeping OpenEmu's `<Core>/Battery Saves/` layout.
    private func archiveBatterySaves(_ folders: [URL], into archive: URL) throws {
        for folder in folders {
            let core = folder.deletingLastPathComponent().lastPathComponent
            let to = archive.appending(path: core, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: to, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: folder, to: to.appending(path: "Battery Saves", directoryHint: .isDirectory))
        }
    }

    // MARK: Checks

    private struct Key: Hashable {
        let platformId: Int64
        let name: String
    }

    /// The folder, or the nearest one above it that exists, can be written to.
    private static func canWrite(into folder: URL) -> Bool {
        var dir = folder
        while !FileManager.default.fileExists(atPath: dir.path(percentEncoded: false)) {
            let parent = dir.deletingLastPathComponent()
            if parent == dir { return false }
            dir = parent
        }
        return FileManager.default.isWritableFile(atPath: dir.path(percentEncoded: false))
    }
}

/// What `migrate-openemu` will do, and what stops it.
public struct OpenEmuMigrationPlan: Sendable, Equatable {
    public struct Move: Sendable, Equatable {
        public let from: URL
        public let to: URL
    }

    public struct ROM: Sendable, Equatable {
        public let romId: Int64
        public let platformId: Int64
        /// Its name in its ROM folder: the file's without the extension.
        public let folderName: String
        public let fileName: String
        /// No file to move: it stays missing, keyed by OpenEmu's file name, and reconnects if the file appears.
        public let missing: Bool
        public let moves: [Move]
    }

    public var roms: [ROM] = []
    /// A Game whose Platform its ROM's OpenEmu system can't hold: fix the Game first.
    public var platformMismatches: [String] = []
    /// A journal ROM whose row OpenEmu no longer has: its Platform can't be checked against a system, and it
    /// stays missing, re-keyed by the file name the journal knew. Listed for a look; it doesn't stop the migration.
    public var goneFromOpenEmu: [String] = []
    /// A ROM whose Platform has no ROM folder.
    public var noROMFolder: [String] = []
    /// Two ROMs with one name in a Platform's folder, or a file already where one would go. Resolved by hand.
    public var clashes: [String] = []
    /// A ROM whose file its Platform's ROM folder wouldn't read, so it would go missing once moved. Converted by hand.
    public var unreadableFiles: [String] = []
    public var unwritableFolders: [URL] = []
    /// OpenEmu ROM files with no journal entry: listed, and left where they are.
    public var leftInOpenEmu: [URL] = []
    /// Each core's battery saves folder, copied unchanged into the archive.
    public var batterySaves: [URL] = []

    public var isRunnable: Bool {
        platformMismatches.isEmpty && noROMFolder.isEmpty && clashes.isEmpty && unreadableFiles.isEmpty && unwritableFolders.isEmpty
    }
}

public struct OpenEmuMigrationResult: Sendable {
    public let plan: OpenEmuMigrationPlan
    public let backup: URL
    /// Every move, `old path<TAB>new path`, one per line.
    public let log: URL
    public let batterySaveArchive: URL
}

public enum OpenEmuMigrationError: Error, Equatable {
    /// The journal has no OpenEmu ROMs left: it was migrated already.
    case alreadyMigrated
    case openEmuRunning
    case blocked(OpenEmuMigrationPlan)
    /// Nothing in the journal changed; the log lists what moved before it failed.
    case moveFailed(file: URL, log: URL, underlying: String)
}
