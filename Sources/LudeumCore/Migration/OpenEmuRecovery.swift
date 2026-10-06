import Foundation
import GRDB

/// `recover-openemu-renamed`: run once, by hand, after `migrate-openemu`, to bring in the OpenEmu ROMs it left missing
/// because their files had been renamed after OpenEmu recorded them. It finds each one's file in OpenEmu's library by
/// name alone and moves it into the ROM's ROM folder, as `migrate-openemu` would have. No journal data is lost.
///
/// The journal no longer knows which OpenEmu ROM each was, so that comes from the `before-migration` Backup (the same
/// ROM ids), then OpenEmu's database gives where it was recorded.
///
/// Order: refuse on a journal still waiting for `migrate-openemu`, while OpenEmu is running, and without the Data folder;
/// plan and check everything (the dry run stops there); take a `before-recovery` Backup; move the files, logging each
/// old path → new path beside it; then re-key each ROM to its file's name in one transaction, to be looked up in libretro
/// again, forgetting the disc ROMs a recovered playlist now loads. Each stays missing until the next Import finds it.
/// A failed move stops before the transaction.
public struct OpenEmuRecovery {
    let journal: LudeumStore
    let library: URL
    let beforeMigration: URL
    let folder: LudeumFolder
    let backups: Backups
    let isOpenEmuRunning: () -> Bool

    /// `beforeMigration` is the Backup `migrate-openemu` took: a journal whose ROMs still have their OpenEmu ids.
    public init(
        journal: LudeumStore, library: URL, beforeMigration: URL, folder: LudeumFolder, isOpenEmuRunning: @escaping () -> Bool
    ) {
        self.journal = journal
        self.library = library
        self.beforeMigration = beforeMigration
        self.folder = folder
        backups = Backups(folder: folder.backups, clock: journal.clock, timeZone: journal.calendar.timeZone)
        self.isOpenEmuRunning = isOpenEmuRunning
    }

    /// The dry run: what would move, and anything that stops it. Changes nothing but the `ROMs/` and `Backups/` folders,
    /// made in the Data folder if they're missing.
    public func plan() throws -> OpenEmuRecoveryPlan {
        guard try !journal.needsOpenEmuMigration() else { throw OpenEmuRecoveryError.notMigrated }
        guard !isOpenEmuRunning() else { throw OpenEmuRecoveryError.openEmuRunning }
        try folder.checkData()
        let openEmuROMs = try Self.openEmuROMs(in: beforeMigration)
        let snapshotFile = FileManager.default.temporaryDirectory.appending(path: "ludeum-recover-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: snapshotFile) }
        try OpenEmuLibrary.snapshot(library: library, to: snapshotFile)
        let snapshot = try OpenEmuLibrary.read(snapshot: snapshotFile, library: library)
        let inOpenEmu = Dictionary(snapshot.roms.map { ($0.pk, $0) }, uniquingKeysWith: { a, _ in a })
        let finder = RenamedFiles(roms: library.appending(path: "roms", directoryHint: .isDirectory), recorded: snapshot.roms)

        let rows = try journal.db.read { db in
            try Row.fetchAll(db, sql: "SELECT id, platformId, folderName, fileName, missing FROM rom ORDER BY id")
        }
        var plan = OpenEmuRecoveryPlan()
        // Each missing OpenEmu ROM still under the name `migrate-openemu` gave it, with the files it could be.
        var found: [(row: Row, label: String, candidates: [URL])] = []
        for row in rows where row["missing"] as Bool {
            let id: Int64 = row["id"]
            let fileName: String = row["fileName"]
            guard let before = openEmuROMs[id], before.fileName == fileName else { continue }
            guard let record = inOpenEmu[before.pk], let file = record.file else {
                plan.unmatched.append("\(fileName): OpenEmu no longer has it")
                continue
            }
            let label = finder.label(file)
            found.append((row, label, record.isPresent ? [] : finder.candidates(for: record)))
        }
        // A file two ROMs could be is neither's.
        var claims: [URL: Int] = [:]
        for candidate in found.flatMap(\.candidates) { claims[candidate, default: 0] += 1 }

        var matched: [(row: Row, label: String, file: URL)] = []
        for (row, label, candidates) in found {
            if candidates.isEmpty {
                plan.unmatched.append(label)
            } else if candidates.count > 1 || claims[candidates[0]]! > 1 {
                plan.ambiguous.append("\(label): \(candidates.map { finder.label($0) }.joined(separator: ", "))")
            } else {
                matched.append((row, label, candidates[0]))
            }
        }

        // A playlist whose discs are in its ROM folder already, moved there as ROMs of their own while it looked missing:
        // it moves alone, to load them, and their own ROMs are forgotten, as `migrate-openemu` forgets a duplicate disc.
        // Their files must have its discs' names and sizes, from metadata alone, or it stays missing.
        var placing: [(row: Row, label: String, file: URL, files: [URL]?)] = []
        for (row, label, file) in matched {
            guard file.pathExtension.lowercased() == "m3u", let romFolder = folder.romFolder(platform: row["platformId"]) else {
                placing.append((row, label, file, nil))
                continue
            }
            let discs = ROMFiles.files(of: file).dropFirst().map { disc in
                (stamp: FileStamp(disc), relative: OpenEmuMoves.relativePath(of: disc, besideMain: file))
            }
            let inFolder = discs.map { FileStamp(romFolder.appending(path: $0.relative)) }
            if inFolder.allSatisfy({ $0 == nil }) {
                // In a subfolder of their own already: they aren't moved in again, and it isn't guessed where it goes.
                if let subfolder = Self.subfolders(of: romFolder).first(where: { subfolder in
                    discs.contains { FileStamp(subfolder.appending(path: $0.relative)) != nil }
                }) {
                    plan.playlistsLeftMissing.append(
                        "\(label): its discs are in \(romFolder.lastPathComponent)/\(subfolder.lastPathComponent) already")
                    continue
                }
                placing.append((row, label, file, nil))
            } else if zip(discs, inFolder).allSatisfy({ $0.stamp != nil && $0.stamp == $1 }) {
                let relatives = Set(discs.map(\.relative))
                for disc in rows where disc["platformId"] == row["platformId"] as Int64 && relatives.contains(disc["fileName"]) {
                    plan.forgottenDiscs.append(.init(romId: disc["id"], name: disc["fileName"], playlist: file.lastPathComponent))
                }
                placing.append((row, label, file, [file]))
            } else {
                plan.playlistsLeftMissing.append("\(label): its discs in \(romFolder.lastPathComponent) differ")
            }
        }

        let rekeyed = Set(placing.map { $0.row["id"] as Int64 } + plan.forgottenDiscs.map(\.romId))
        let taken = Set(
            rows.filter { !rekeyed.contains($0["id"]) }.map { ROMKey(platformId: $0["platformId"], name: $0["folderName"]) })
        var moves = OpenEmuMoves(folder: folder, taken: taken)
        for (row, label, file, files) in placing {
            if let rom = moves.place(
                romId: row["id"], platformId: row["platformId"], label: "\(label) → \(finder.label(file))", main: file,
                fileName: file.lastPathComponent, files: files)
            {
                plan.roms.append(rom)
            }
        }
        plan.unwritableFolders = moves.finish(plan.roms)
        plan.noROMFolder = moves.noROMFolder
        plan.clashes = moves.clashes.sorted()
        plan.unreadableFiles = moves.unreadableFiles
        return plan
    }

    /// Recovers every ROM the plan found. Throws `blocked` (with the plan) when the dry run found anything that stops
    /// it, before anything is touched.
    @discardableResult
    public func run() async throws -> OpenEmuRecoveryResult {
        let plan = try plan()
        guard plan.isRunnable else { throw OpenEmuRecoveryError.blocked(plan) }
        let backup = try backups.backUp(journal, operation: .beforeRecovery)
        let log = backup.url.deletingPathExtension().appendingPathExtension("moves.log")
        try OpenEmuMoves.move(plan.roms, log: log)
        // Still missing, under its real name: the next Import finds its file, and looks it up in libretro again.
        try await journal.db.write { db in
            // A disc a recovered playlist now loads is forgotten, with what hangs off its row; its Game stays.
            for disc in plan.forgottenDiscs { try db.execute(sql: "DELETE FROM rom WHERE id = ?", arguments: [disc.romId]) }
            for rom in plan.roms {
                try db.execute(
                    sql: "UPDATE rom SET folderName = ?, fileName = ?, name = ?, libretroLookedUp = 0 WHERE id = ?",
                    arguments: [rom.folderName, rom.fileName, rom.folderName, rom.romId])
            }
        }
        return OpenEmuRecoveryResult(plan: plan, backup: backup.url, log: log)
    }

    /// Each ROM's OpenEmu id in a `before-migration` Backup, with the file name the journal knew it by then.
    private static func openEmuROMs(in backup: URL) throws -> [Int64: (pk: Int64, fileName: String)] {
        var config = Configuration()
        config.readonly = true
        let db = try DatabaseQueue(path: backup.path(percentEncoded: false), configuration: config)
        defer { try? db.close() }
        return try db.read { db in
            guard try db.columns(in: "rom").contains(where: { $0.name == "openEmuPk" }) else {
                throw OpenEmuRecoveryError.notABeforeMigrationBackup(backup)
            }
            let rows = try Row.fetchAll(db, sql: "SELECT id, openEmuPk, fileName FROM rom WHERE openEmuPk IS NOT NULL")
            return Dictionary(uniqueKeysWithValues: rows.map { ($0["id"], (pk: $0["openEmuPk"], fileName: $0["fileName"])) })
        }
    }

    private static func subfolders(of folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().map { folder.appending(path: $0, directoryHint: .isDirectory) }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    /// The newest `before-migration` Backup in the Data folder.
    public static func beforeMigrationBackup(in folder: LudeumFolder) throws -> URL? {
        try Backups(folder: folder.backups).all().first { $0.operation == .beforeMigration }?.url
    }
}

/// Where a missing OpenEmu ROM's file went, found by name alone: its files may be Dropbox online-only, so none is read
/// but a cue sheet or playlist. A candidate is a file no OpenEmu ROM records.
struct RenamedFiles {
    /// OpenEmu's `roms/` folder.
    let roms: URL
    private let recorded: Set<String>

    init(roms: URL, recorded: [OpenEmuROMRecord]) {
        self.roms = roms
        self.recorded = Set(recorded.compactMap { $0.file.map(Self.path) })
    }

    /// The files `record`'s could be now.
    func candidates(for record: OpenEmuROMRecord) -> [URL] {
        guard let file = record.file else { return [] }
        var stems = Self.unnumbered(file.deletingPathExtension().lastPathComponent)
        // An archive unpacked, or packed again, under the name of the file inside it.
        if let inner = record.archiveFileName, !inner.isEmpty { stems.insert((inner as NSString).deletingPathExtension) }
        var found = files(in: file.deletingLastPathComponent(), named: stems)
        // OpenEmu has kept PS1 games under two system folders: one may have gone into the same subfolder of the other.
        for folder in record.system == "openemu.system.psx" ? samePlayStationFolders(as: file) : [] {
            found += files(in: folder, named: stems)
        }
        // A cue sheet's tracks and a playlist's discs go with it, so aren't other files it could be.
        let belonging = Set(found.flatMap { ROMFiles.files(of: $0).dropFirst() }.map(Self.key))
        return found.filter { !belonging.contains(Self.key($0)) }
    }

    /// A name, and the name without the number OpenEmu adds to a file it copies in beside another of the same name:
    /// "Avenging Spirit (USA, Europe) 2".
    private static func unnumbered(_ name: String) -> Set<String> {
        guard let numbered = name.wholeMatch(of: /(.+) \d+/) else { return [name] }
        return [name, String(numbered.1)]
    }

    /// The files in `folder` whose names, less their extensions, are `stems`, that no OpenEmu ROM records, neither as its
    /// file nor as a recorded cue sheet's track or playlist's disc.
    private func files(in folder: URL, named stems: Set<String>) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        let matching = names.filter { !$0.hasPrefix(".") && stems.contains(($0 as NSString).deletingPathExtension) }.sorted()
            .map { folder.appending(path: $0, directoryHint: .notDirectory) }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true && !recorded.contains(Self.path($0)) }
        guard !matching.isEmpty else { return [] }
        let sheets = names.map { folder.appending(path: $0, directoryHint: .notDirectory) }
            .filter { ["cue", "m3u"].contains($0.pathExtension.lowercased()) && recorded.contains(Self.path($0)) }
        let belonging = Set(sheets.flatMap { ROMFiles.files(of: $0) }.map(Self.key))
        return matching.filter { !belonging.contains(Self.key($0)) }
    }

    private static let playStationFolders = ["Sony PlayStation", "Playstation (PSX)"]

    /// For a file under one of OpenEmu's PlayStation system folders, the same folder under the other one: its subfolder,
    /// by its name or without OpenEmu's number.
    private func samePlayStationFolders(as file: URL) -> [URL] {
        let parts = label(file).split(separator: "/").map(String.init)
        guard parts.count <= 3, let top = parts.first, Self.playStationFolders.contains(top),
            let other = Self.playStationFolders.first(where: { $0 != top })
        else { return [] }
        let otherFolder = roms.appending(path: other, directoryHint: .isDirectory)
        guard parts.count == 3 else { return [otherFolder] }
        return Self.unnumbered(parts[1]).sorted().map { otherFolder.appending(path: $0, directoryHint: .isDirectory) }
    }

    /// A file's path in OpenEmu's `roms/` folder.
    func label(_ file: URL) -> String {
        let base = Self.path(roms)
        let path = Self.path(file)
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)).trimmingPrefix("/").description : path
    }

    private static func path(_ file: URL) -> String { file.standardizedFileURL.path(percentEncoded: false) }

    /// A file's path, to compare with the files a cue sheet or playlist names, which may differ in case.
    private static func key(_ file: URL) -> String { path(file).lowercased() }
}

/// What `recover-openemu-renamed` will do, and what stops it.
public struct OpenEmuRecoveryPlan: Sendable, Equatable {
    /// Each ROM whose file was found, re-keyed by its name, with the files that move.
    public var roms: [OpenEmuMigrationPlan.ROM] = []
    /// No file it could be: it stays missing.
    public var unmatched: [String] = []
    /// More than one file it could be, or a file another ROM could be too: it stays missing.
    public var ambiguous: [String] = []
    /// Each ROM of its own whose files a recovered playlist now loads, in the ROM folder already: forgotten.
    public var forgottenDiscs: [OpenEmuMigrationPlan.DuplicateDisc] = []
    /// A playlist with some disc files in its ROM folder already, but not all with its discs' names and sizes: it
    /// stays missing.
    public var playlistsLeftMissing: [String] = []
    /// A ROM whose Platform has no ROM folder.
    public var noROMFolder: [String] = []
    /// Two ROMs with one name in a Platform's folder, or a file already where one would go. Resolved by hand.
    public var clashes: [String] = []
    /// A ROM whose file its Platform's ROM folder wouldn't read. Converted by hand.
    public var unreadableFiles: [String] = []
    public var unwritableFolders: [URL] = []

    public var isRunnable: Bool { noROMFolder.isEmpty && clashes.isEmpty && unreadableFiles.isEmpty && unwritableFolders.isEmpty }
}

public struct OpenEmuRecoveryResult: Sendable {
    public let plan: OpenEmuRecoveryPlan
    public let backup: URL
    /// Every move, `old path<TAB>new path`, one per line.
    public let log: URL
}

public enum OpenEmuRecoveryError: Error, Equatable {
    /// The journal still has OpenEmu ROMs: `migrate-openemu` comes first.
    case notMigrated
    case openEmuRunning
    /// The Backup given has no OpenEmu ids: it isn't the one `migrate-openemu` took.
    case notABeforeMigrationBackup(URL)
    case blocked(OpenEmuRecoveryPlan)
}
