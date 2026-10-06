import Foundation
import GRDB

/// `migrate-openemu`: run once, by hand, to move every OpenEmu ROM the journal has into its Platform's
/// ROM folder, so the journal no longer needs OpenEmu (ADR 0009). No journal data is lost. A duplicate disc (a disc
/// added to OpenEmu again on its own, whose files a playlist ROM on its Platform already has) isn't moved: its files
/// stay in OpenEmu's library and its row is forgotten in the transaction below, while its Game stays.
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
    let support: URL
    let folder: LudeumFolder
    let backups: Backups
    let isOpenEmuRunning: () -> Bool
    let libretro: LibretroThumbnails?

    /// OpenEmu's Application Support folder, where it keeps each core's battery saves wherever its library is.
    public static var standardSupport: URL {
        URL(filePath: ("~/Library/Application Support/OpenEmu" as NSString).expandingTildeInPath, directoryHint: .isDirectory)
    }

    /// `support` is OpenEmu's Application Support folder, whose battery saves are archived (a symlink is followed).
    /// `folder`'s Data folder gets the ROM folders, the backup and the battery-save archive.
    public init(
        journal: LudeumStore, library: URL, support: URL, folder: LudeumFolder, isOpenEmuRunning: @escaping () -> Bool,
        libretro: LibretroThumbnails?
    ) {
        self.journal = journal
        self.library = library
        self.support = support
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
                    ROMKey(platformId: $0["platformId"], name: $0["folderName"])
                })
        }

        // By its Game's Platform; an unmatched ROM keeps the one it was given, its system's most likely.
        func platform(_ row: Row) -> Int64 { row["gamePlatformId"] ?? row["platformId"] }
        func present(_ record: OpenEmuROMRecord?) -> URL? { record.flatMap { $0.isPresent ? $0.file : nil } }
        // Each playlist ROM's disc files (its cue sheets and their tracks), by Platform.
        var playlists: [Int64: [(label: String, discs: Set<FileStamp>)]] = [:]
        for row in rows {
            guard let main = present(inOpenEmu[row["openEmuPk"]]), main.pathExtension.lowercased() == "m3u" else { continue }
            let discs = ROMFiles.files(of: main).dropFirst().compactMap(FileStamp.init)
            playlists[platform(row), default: []].append((main.lastPathComponent, Set(discs)))
        }

        var plan = OpenEmuMigrationPlan()
        var moves = OpenEmuMoves(folder: folder, taken: taken)
        for row in rows {
            let pk: Int64 = row["openEmuPk"]
            let storedFileName: String = row["fileName"]
            let record = inOpenEmu[pk]
            let platformId = platform(row)
            let label = record?.file?.lastPathComponent ?? storedFileName
            // A disc added to OpenEmu again on its own, beside its playlist: left there, and forgotten.
            if let main = present(record), main.pathExtension.lowercased() != "m3u" {
                let stamps = ROMFiles.files(of: main).map(FileStamp.init)
                if !stamps.isEmpty, !stamps.contains(nil),
                    let playlist = playlists[platformId]?.first(where: { $0.discs.isSuperset(of: stamps.compactMap { $0 }) })
                {
                    plan.duplicateDiscs.append(.init(romId: row["id"], name: label, playlist: playlist.label))
                    continue
                }
            }
            if let record, let candidates = openEmuSystemPlatforms[record.system], !candidates.contains(Int(platformId)) {
                plan.platformMismatches.append("\(label): \(record.system) can't hold a Game on Platform \(platformId)")
                continue
            }
            // With no system to check its Platform against, it's listed rather than passed over.
            if record == nil { plan.goneFromOpenEmu.append("\(label): Platform \(platformId)") }
            if let rom = moves.place(
                romId: row["id"], platformId: platformId, label: label, main: present(record), fileName: storedFileName)
            {
                plan.roms.append(rom)
            }
        }
        plan.unwritableFolders = moves.finish(plan.roms)
        plan.noROMFolder = moves.noROMFolder
        plan.clashes = moves.clashes
        plan.unreadableFiles = moves.unreadableFiles
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

        try OpenEmuMoves.move(plan.roms, log: log)

        // Each ROM is to be looked up in libretro again by its new name: one whose lookup doesn't run below waits
        // for the next Import.
        try await journal.db.write { db in
            // A duplicate disc is forgotten, with what hangs off its row (held OpenEmu data); its Game stays.
            for duplicate in plan.duplicateDiscs {
                try db.execute(sql: "DELETE FROM rom WHERE id = ?", arguments: [duplicate.romId])
            }
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

    /// OpenEmu keeps each core's battery saves in `<Core>/Battery Saves/` in its Application Support folder, wherever
    /// its library is. A symlinked one is followed, so the archive gets the real files.
    private func batterySaveFolders() -> [URL] {
        let support = support.resolvingSymlinksInPath()
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

    /// A ROM whose every file has the name and size of one of a playlist ROM's disc files (a cue sheet or its tracks)
    /// on its Platform: a disc added to OpenEmu again on its own.
    public struct DuplicateDisc: Sendable, Equatable {
        public let romId: Int64
        public let name: String
        /// The playlist ROM whose disc it duplicates.
        public let playlist: String
    }

    public var roms: [ROM] = []
    /// Its files are left in OpenEmu's library, and its journal row is forgotten; its Game stays.
    public var duplicateDiscs: [DuplicateDisc] = []
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
