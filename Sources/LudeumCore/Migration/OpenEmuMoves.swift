import Foundation

/// A ROM's name in its Platform's ROM folder, where it's unique.
struct ROMKey: Hashable {
    let platformId: Int64
    let name: String
}

/// A file's name and size, from its metadata alone: OpenEmu's files may be Dropbox online-only, and reading them would
/// download them.
struct FileStamp: Hashable {
    let name: String
    let size: Int

    init?(_ file: URL) {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        name = file.lastPathComponent
        self.size = size
    }
}

/// Moving OpenEmu ROMs' files into their Platforms' ROM folders, shared by `migrate-openemu` and `recover-openemu-renamed`.
/// Each ROM is planned and checked as it's placed, and nothing moves until `move(_:log:)`.
struct OpenEmuMoves {
    let folder: LudeumFolder
    /// The names the journal's other ROMs have: a ROM placed under one clashes.
    let taken: Set<ROMKey>
    private var keys: [ROMKey: [String]] = [:]
    private var destinations: [URL: URL] = [:]
    private(set) var noROMFolder: [String] = []
    private(set) var clashes: [String] = []
    private(set) var unreadableFiles: [String] = []

    init(folder: LudeumFolder, taken: Set<ROMKey>) {
        self.folder = folder
        self.taken = taken
    }

    /// Places a ROM in its Platform's ROM folder, named after `main`, its file; one with no file stays missing, named
    /// after `fileName`. `files` move with it, each to the same place relative to `main`'s folder: by default `main`
    /// with a cue sheet's tracks or a playlist's discs. `inSubfolder` puts them in a subfolder named after it, as
    /// `into-folders` keeps a disc Platform's ROMs. Nil when its Platform has no ROM folder.
    mutating func place(
        romId: Int64, platformId: Int64, label: String, main: URL?, fileName storedFileName: String, files: [URL]? = nil,
        inSubfolder: Bool = false
    ) -> OpenEmuMigrationPlan.ROM? {
        guard let romFolder = folder.romFolder(platform: platformId) else {
            noROMFolder.append("\(label): Platform \(platformId) has no ROM folder")
            return nil
        }
        let fileName = main?.lastPathComponent ?? storedFileName
        let name = (fileName as NSString).deletingPathExtension
        let key = ROMKey(platformId: platformId, name: name)
        keys[key, default: []].append(label)
        if taken.contains(key) { clashes.append("\(romFolder.lastPathComponent)/\(name): already a ROM there") }
        if main != nil, ROMFolder.platform(platformId, romFolder)?.reads(fileName: fileName) != true {
            let ext = (fileName as NSString).pathExtension.lowercased()
            unreadableFiles.append("\(romFolder.lastPathComponent)/\(fileName): its ROM folder doesn't read .\(ext) files")
        }
        let subfolder = inSubfolder && main != nil
        if subfolder, FileManager.default.fileExists(atPath: romFolder.appending(path: name).path(percentEncoded: false)) {
            clashes.append("\(romFolder.lastPathComponent)/\(name): already a ROM or folder there")
        }

        var moves: [OpenEmuMigrationPlan.Move] = []
        var shownFileName = fileName
        if let main {
            if subfolder { shownFileName = "\(name)/\(main.lastPathComponent)" }
            for file in files ?? ROMFiles.files(of: main) {
                let to =
                    subfolder
                    ? IntoFolders.destination(of: file, from: main.deletingLastPathComponent(), rom: name, in: romFolder)
                    : romFolder.appending(path: Self.relativePath(of: file, from: main.deletingLastPathComponent()))
                let relative = Self.relativePath(of: to, from: romFolder)
                if let other = destinations[to], other != file {
                    clashes.append("\(romFolder.lastPathComponent)/\(relative): two ROMs' files")
                } else if destinations[to] == nil {
                    destinations[to] = file
                    if FileManager.default.fileExists(atPath: to.path(percentEncoded: false)) {
                        clashes.append("\(romFolder.lastPathComponent)/\(relative): a file is already there")
                    }
                    moves.append(.init(from: file, to: to))
                }
            }
        }
        return .init(
            romId: romId, platformId: platformId, folderName: name, fileName: shownFileName, missing: main == nil, moves: moves)
    }

    /// A file's path from `folder`, else just its name: where one of a ROM's files goes, from its main file's folder.
    static func relativePath(of file: URL, from folder: URL) -> String {
        let base = folder.standardizedFileURL.path(percentEncoded: false)
        let path = file.standardizedFileURL.path(percentEncoded: false)
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)).trimmingPrefix("/").description : file.lastPathComponent
    }

    /// Once every ROM is placed: two ROMs with one name join the clashes, and returns the ROM folders the moves can't
    /// be written into.
    mutating func finish(_ moves: [OpenEmuMigrationPlan.Move]) -> [URL] {
        for (key, labels) in keys where labels.count > 1 {
            clashes.append("\(key.name) on Platform \(key.platformId): \(labels.joined(separator: ", "))")
        }
        let folders = Set(moves.map { $0.to.deletingLastPathComponent() })
        return folders.filter { !Self.canWrite(into: $0) }.sorted { $0.path < $1.path }
    }

    /// Moves every file, logging each `old path<TAB>new path` to `log` as it goes. A failed move stops there
    /// (`moveFailed`), with the log saying what moved.
    static func move(_ moves: [OpenEmuMigrationPlan.Move], log: URL) throws {
        FileManager.default.createFile(atPath: log.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        for move in moves {
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
