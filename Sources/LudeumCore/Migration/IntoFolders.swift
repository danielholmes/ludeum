import Foundation
import GRDB

/// `into-folders`: run once, by hand, with Ludeum closed, to move each loose ROM of a disc Platform (PS1, Sega CD,
/// Saturn, PC Engine CD) into a subfolder named after it, the way PS2's are kept. A ROM keeps its name, so it's the
/// same ROM with the same Match. The exception is a multi-disc Version, which becomes one ROM: its playlist and Discs
/// go into one subfolder named after the playlist, or, with no playlist, after Disc 1 without its Disc
/// ("Fear Effect 2 (Europe)"), which then waits in the Review queue for one. That ROM keeps the Match of its playlist's
/// row, else its first Disc's, renamed when it was a Disc's; the other rows are forgotten. Discs Matched to more than
/// one Game are left loose, and listed. A `.7z` stays loose beside the subfolder, as PS2's do.
///
/// Order: refuse on a journal still waiting for `migrate-openemu`, and without the Data folder; plan and check
/// everything (the dry run stops there); take a `before-into-folders` backup; move the files, logging each
/// old path → new path beside the backup; then rewrite the ROM rows in one transaction, and look each renamed ROM up in
/// libretro again (a failed lookup never fails the run). A failed move stops before that transaction: restore nothing,
/// and the log says what moved. Undo is restoring the backup and moving the logged files back.
public struct IntoFolders {
    /// The Platforms whose ROMs are cue sheets with their tracks, or disc images.
    public static let platforms: [Int64] = [7, 78, 32, 150]

    let journal: LudeumStore
    let folder: LudeumFolder
    let backups: Backups
    let libretro: LibretroThumbnails?

    public init(journal: LudeumStore, folder: LudeumFolder, libretro: LibretroThumbnails?) {
        self.journal = journal
        self.folder = folder
        backups = Backups(folder: folder.backups, clock: journal.clock, timeZone: journal.calendar.timeZone)
        self.libretro = libretro
    }

    /// The dry run: everything the run would do, and anything that stops it. Changes nothing.
    public func plan() throws -> IntoFoldersPlan {
        guard try !journal.needsOpenEmuMigration() else { throw ImportError.openEmuMigrationNeeded }
        try folder.checkData()
        var plan = IntoFoldersPlan()
        for platformId in Self.platforms {
            guard let url = folder.romFolder(platform: platformId), let romFolder = ROMFolder.platform(platformId, url),
                FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
            else { continue }
            try planFolder(romFolder, into: &plan)
        }
        return plan
    }

    private func planFolder(_ romFolder: ROMFolder, into plan: inout IntoFoldersPlan) throws {
        let url = romFolder.url
        let platformId = romFolder.platformId
        let label = url.lastPathComponent
        let names = try FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))
            .filter { !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let files = names.map { url.appending(path: $0, directoryHint: .notDirectory) }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        let subfolders = Set(names).subtracting(files.map(\.lastPathComponent))
        let rows = try journal.db.read { db in
            try Row.fetchAll(db, sql: "SELECT id, folderName, gameId FROM rom WHERE platformId = ?", arguments: [platformId])
        }
        let byName = Dictionary(rows.map { ($0["folderName"] as String, $0) }, uniquingKeysWith: { a, _ in a })
        func ext(_ file: URL) -> String { file.pathExtension.lowercased() }
        func romName(_ file: URL) -> String { file.deletingPathExtension().lastPathComponent }

        // A subfolder to be: its name, its files, and the ROMs it stands for, the one to keep first.
        var folders: [(name: String, files: [URL], roms: [String], needsPlaylist: Bool)] = []
        var claimed = Set<URL>()
        for playlist in files where ext(playlist) == "m3u" {
            var members = [playlist]
            var discs: [String] = []
            for entry in ROMFiles.playlistEntries(playlist) {
                let disc = url.appending(path: entry)
                guard FileManager.default.fileExists(atPath: disc.path(percentEncoded: false)) else {
                    plan.clashes.append("\(label)/\(playlist.lastPathComponent) names \(entry), which isn't there")
                    continue
                }
                members += ROMFiles.files(of: disc)
                discs.append(romName(disc))
            }
            folders.append((romName(playlist), members, [romName(playlist)] + discs, false))
            claimed.formUnion(members)
        }
        // Each other ROM: a cue sheet with its tracks, or an image; a `.7z` stays loose.
        var singles: [String: [URL]] = [:]
        for cue in files where ext(cue) == "cue" && !claimed.contains(cue) {
            let members = ROMFiles.files(of: cue)
            singles[romName(cue), default: []] += members
            claimed.formUnion(members)
        }
        for file in files where !claimed.contains(file) && ext(file) != "7z" {
            guard romFolder.reads(fileName: file.lastPathComponent) else {
                plan.leftLoose.append("\(label)/\(file.lastPathComponent): not a ROM")
                continue
            }
            singles[romName(file), default: []].append(file)
        }
        // Discs with no playlist, of one Game (or, unmatched, one name), make one multi-disc Version.
        let discSets = Dictionary(grouping: singles.keys.filter { ROMName($0).disc != nil }) { name in
            (byName[name]?["gameId"] as GameID?).map { "game \($0)" } ?? "name \(ROMName(name).withoutDisc)"
        }
        for discs in discSets.values {
            let ordered = discs.sorted { ROMName($0).disc! < ROMName($1).disc! }
            guard ordered.count > 1, Set(ordered.map { ROMName($0).disc! }).count == ordered.count else { continue }
            folders.append((ROMName(ordered[0]).withoutDisc, ordered.flatMap { singles[$0]! }, ordered, true))
            for disc in ordered { singles[disc] = nil }
        }
        folders += singles.map { ($0.key, $0.value, [$0.key], false) }

        var taken = Set<String>()
        for (name, members, roms, needsPlaylist) in folders.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            let romRows = roms.compactMap { byName[$0] }
            if Set(romRows.compactMap { $0["gameId"] as GameID? }).count > 1 {
                plan.leftLoose.append("\(label)/\(name): its ROMs are Matched to different Games")
                continue
            }
            if subfolders.contains(name) || !taken.insert(name).inserted || (byName[name] != nil && !roms.contains(name)) {
                plan.clashes.append("\(label)/\(name): already a ROM or folder there")
                continue
            }
            let kept = romRows.first { $0["gameId"] as GameID? != nil } ?? romRows.first
            plan.folders.append(
                IntoFoldersPlan.Folder(
                    platformId: platformId, name: name,
                    moves: members.map { file in
                        let relative = file.standardizedFileURL.pathComponents.dropFirst(url.standardizedFileURL.pathComponents.count)
                        return .init(from: file, to: url.appending(path: name).appending(path: relative.joined(separator: "/")))
                    },
                    keptROM: kept?["id"], renamed: kept.map { $0["folderName"] as String != name } ?? false,
                    forgottenROMs: romRows.filter { $0["id"] as Int64 != kept?["id"] }.map { $0["id"] }, needsPlaylist: needsPlaylist))
        }
    }

    /// Runs it. Throws `blocked` (with the plan) when the dry run found anything that stops it, before anything is
    /// touched.
    @discardableResult
    public func run() async throws -> IntoFoldersResult {
        let plan = try plan()
        guard plan.isRunnable else { throw IntoFoldersError.blocked(plan) }
        let backup = try backups.backUp(journal, operation: .beforeIntoFolders)
        let log = backup.url.deletingPathExtension().appendingPathExtension("moves.log")
        FileManager.default.createFile(atPath: log.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        for move in plan.folders.flatMap(\.moves) {
            do {
                try FileManager.default.createDirectory(at: move.to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: move.from, to: move.to)
            } catch {
                throw IntoFoldersError.moveFailed(file: move.from, log: log, underlying: String(describing: error))
            }
            try handle.write(contentsOf: Data("\(move.from.path(percentEncoded: false))\t\(move.to.path(percentEncoded: false))\n".utf8))
        }

        var scans: [Int64: [FolderROMFile]] = [:]
        for platformId in Set(plan.folders.map(\.platformId)) {
            scans[platformId] = try folder.romFolder(platform: platformId).flatMap { ROMFolder.platform(platformId, $0) }?.scan()
        }
        let scanned = scans
        try await journal.db.write { db in
            for f in plan.folders {
                for rom in f.forgottenROMs { try db.execute(sql: "DELETE FROM rom WHERE id = ?", arguments: [rom]) }
                guard let kept = f.keptROM else { continue }
                if f.renamed {
                    try db.execute(
                        sql: """
                            UPDATE rom SET folderName = ?, name = ?, version = ?, discNumber = NULL, discLabel = NULL,
                                libretroLookedUp = 0
                            WHERE id = ?
                            """, arguments: [f.name, f.name, ROMName(f.name).version, kept])
                }
                try LudeumStore.setFolderROM(db, kept, to: scanned[f.platformId]?.first { $0.name == f.name })
            }
        }
        // Box art: a renamed ROM is looked up in libretro by its new name.
        try? await BoxArtImport(journal: journal, libretro: libretro).lookUp(plan.folders.filter(\.renamed).compactMap(\.keptROM))
        return IntoFoldersResult(plan: plan, backup: backup.url, log: log)
    }
}

/// What `into-folders` would do.
public struct IntoFoldersPlan: Sendable {
    public struct Move: Sendable, Equatable {
        public let from: URL
        public let to: URL
    }

    /// One subfolder to make: a ROM's files, or a multi-disc Version's.
    public struct Folder: Sendable, Equatable {
        public let platformId: Int64
        /// The subfolder's name: its ROM's.
        public let name: String
        public let moves: [Move]
        /// The row that becomes its ROM, if the journal has one.
        public let keptROM: Int64?
        /// The kept row was a Disc's, so its name changes.
        public let renamed: Bool
        /// The other rows of a multi-disc Version, forgotten.
        public let forgottenROMs: [Int64]
        /// Discs with no playlist: the ROM waits in the Review queue for one.
        public let needsPlaylist: Bool
    }

    public var folders: [Folder] = []
    /// Files that stay where they are, and why.
    public var leftLoose: [String] = []
    /// Anything that stops the run.
    public var clashes: [String] = []

    public var isRunnable: Bool { clashes.isEmpty }
}

public struct IntoFoldersResult: Sendable {
    public let plan: IntoFoldersPlan
    public let backup: URL
    /// Each moved file, old path → new path.
    public let log: URL
}

public enum IntoFoldersError: Error {
    case blocked(IntoFoldersPlan)
    case moveFailed(file: URL, log: URL, underlying: String)
}
