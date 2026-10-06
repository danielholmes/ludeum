import Foundation

/// A ROM folder: one IGDB Platform's ROMs, read straight from a folder. The folder alone gives a ROM
/// its Platform. A ROM there is known by its name: a file's without the extension, or a subfolder's. So Unarchiving
/// `Okami (USA).7z` into `Okami (USA)/` is the same ROM changing from archived to ready, and so is Compacting
/// `Tetris (World).gb` into `Tetris (World).7z`. A subfolder is a ROM when it holds the game, at any depth: one
/// playlist (a multi-disc Version), else one cue sheet, else one image, else Discs with no playlist yet. Hidden folders
/// are ignored.
public struct ROMFolder: Sendable, Equatable {
    /// The IGDB platform its ROMs are on.
    public let platformId: Int64
    public let url: URL
    /// What its Emulator opens, most preferred first, ending with its compact extension. Anything else but a `.7z`
    /// is ignored.
    let readyExtensions: [String]
    /// The archive its Emulator opens directly, that its ROMs are Compacted into: nil where it opens none.
    let compactExtension: String?

    /// PS2, played in PCSX2.
    public static func ps2(_ url: URL) -> ROMFolder { platform(ROMPlatform.ps2, url)! }

    /// The ROM folder of a Platform that has one.
    public static func platform(_ id: Int64, _ url: URL) -> ROMFolder? {
        ROMPlatform.all[id].map {
            ROMFolder(
                platformId: id, url: url, readyExtensions: $0.readyExtensions + ($0.compactExtension.map { [$0] } ?? []),
                compactExtension: $0.compactExtension)
        }
    }

    /// How its ROMs are Archived, when they can be.
    var archiving: ROMPlatform.Archiving? { ROMPlatform.all[platformId]?.archiving }

    /// Whether a file with this name, at the top of the folder, is a ROM to it: ready, or a `.7z`.
    func reads(fileName: String) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ext == "7z" || readyExtensions.contains(ext)
    }

    /// Every ROM in the folder, by name. Throws when the folder can't be read (Dropbox not there,
    /// say), so an Import leaves its ROMs alone instead of marking them all missing.
    public func scan() throws -> [FolderROMFile] { try scan(only: nil) }

    /// The ROM `name`, exactly as a scan finds it, or nil when there's none. It looks only at what could be it: the
    /// files and the subfolder of that name, and the folder's cue sheets (their tracks aren't ROMs), so one ROM
    /// doesn't cost a look at every file of every other.
    public func rom(named name: String) throws -> FolderROMFile? { try scan(only: name).first { $0.name == name } }

    private func scan(only: String?) throws -> [FolderROMFile] {
        let items = try FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false)).filter { item in
            guard !item.hasPrefix(".") else { return false }
            guard let only else { return true }
            let name = item as NSString
            return item == only || name.deletingPathExtension == only || name.pathExtension.lowercased() == "cue"
        }
        let files = items.map { url.appending(path: $0, directoryHint: .notDirectory) }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        let folders = items.map { url.appending(path: $0, directoryHint: .isDirectory) }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        // A cue sheet's tracks belong to it.
        let tracks = Set(files.filter { $0.pathExtension.lowercased() == "cue" }.flatMap(Self.cueTracks).map { $0.lowercased() })
        var ready: [String: URL] = [:]
        var archives: [String: URL] = [:]
        var discs: [String: [URL]] = [:]
        var compacted: [String: URL] = [:]
        for file in files where !tracks.contains(file.lastPathComponent.lowercased()) {
            let name = file.deletingPathExtension().lastPathComponent
            let ext = file.pathExtension.lowercased()
            // A `.7z` is the ROM's archive whether or not its Emulator opens it too.
            if ext == "7z" { archives[name] = file }
            // Its Compacted copy is a form of its own even when a loose file is Played over it.
            if ext == compactExtension { compacted[name] = file }
            if let rank = readyExtensions.firstIndex(of: ext) {
                if let current = ready[name], let currentRank = readyExtensions.firstIndex(of: current.pathExtension.lowercased()),
                    currentRank <= rank
                {
                    continue
                }
                ready[name] = file
            }
        }
        // A subfolder holding the game wins over a loose file of the same name.
        for folder in folders {
            guard let game = game(in: folder) else { continue }
            ready[folder.lastPathComponent] = game.file
            discs[folder.lastPathComponent] = game.discsWithoutPlaylist
        }
        return Set(ready.keys).union(archives.keys).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { name in
                FolderROMFile(
                    name: name, ready: ready[name], archive: archives[name],
                    compactedBesideReady: compacted[name].flatMap { $0 == ready[name] || $0 == archives[name] ? nil : $0 },
                    in: url, discsWithoutPlaylist: discs[name] ?? [])
            }
    }

    /// The game in a subfolder, as `game(among:)` finds it.
    private func game(in folder: URL) -> (file: URL, discsWithoutPlaylist: [URL])? {
        let files = ((try? FileManager.default.subpathsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? [])
            .map { folder.appending(path: $0, directoryHint: .notDirectory) }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        return game(among: files)
    }

    /// The game among a subfolder's files: its one playlist, else its one cue sheet, else its one image. Several cue
    /// sheets (or, with none, several images) that are each a different Disc are a game too, opening at Disc 1 until it
    /// has a playlist, where the Platform reads playlists at all. Nil when there's nothing, or several that aren't Discs.
    func game(among files: [URL]) -> (file: URL, discsWithoutPlaylist: [URL])? {
        let images = files.filter { readyExtensions.contains($0.pathExtension.lowercased()) }
        let playlists = images.filter { $0.pathExtension.lowercased() == "m3u" }
        if playlists.count == 1 { return (playlists[0], []) }
        guard playlists.isEmpty else { return nil }
        let cues = images.filter { $0.pathExtension.lowercased() == "cue" }
        let candidates = cues.isEmpty ? images : cues
        if candidates.count == 1 { return (candidates[0], []) }
        let discs = Self.discs(candidates)
        // A playlist is only missing where the Emulator would read one.
        return discs.first.map { ($0, readyExtensions.contains("m3u") ? discs : []) }
    }

    /// The files in Disc order, when there are two or more and each is a different Disc; else none.
    static func discs(_ files: [URL]) -> [URL] {
        let numbered = files.compactMap { file in ROMName(file.deletingPathExtension().lastPathComponent).disc.map { ($0, file) } }
        guard numbered.count > 1, numbered.count == files.count, Set(numbered.map(\.0)).count == numbered.count else { return [] }
        return numbered.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// The subfolder the ROM `name`'s ready file is in, when it's in one. A folder of its name that doesn't hold the game
    /// isn't the ROM's: its loose file is.
    func subfolder(of name: String, holding ready: URL?) -> URL? {
        let subfolder = url.appending(path: name, directoryHint: .isDirectory)
        let inside = subfolder.standardizedFileURL.path(percentEncoded: false)
        guard let ready, ready.standardizedFileURL.path(percentEncoded: false).hasPrefix(inside.hasSuffix("/") ? inside : inside + "/")
        else { return nil }
        return subfolder
    }

    /// The file a Play opens for the ROM `name`, if it isn't archived.
    public func readyFile(named name: String) throws -> URL? {
        try rom(named: name)?.ready
    }

    /// The Discs of the ROM `name`, in Disc order, when its subfolder has no playlist for them; else none.
    public func discsWithoutPlaylist(named name: String) throws -> [URL] {
        try rom(named: name)?.discsWithoutPlaylist ?? []
    }

    /// The file names a cue sheet's `FILE` lines name, without any folder.
    static func cueTracks(_ cue: URL) -> [String] {
        guard let text = try? String(contentsOf: cue, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: "\"")
            guard parts.count >= 2, parts[0].trimmingCharacters(in: .whitespaces).uppercased() == "FILE" else { return nil }
            return String(parts[1].split(whereSeparator: { $0 == "/" || $0 == "\\" }).last ?? parts[1])
        }
    }
}

/// One ROM in a ROM folder: its ready file, its `.7z` archive, or both. Archived when there's no ready file. Where its
/// Emulator opens a `.7z`, a Compacted ROM's `.7z` is both.
public struct FolderROMFile: Sendable, Equatable {
    public let name: String
    public let ready: URL?
    public let archive: URL?
    /// Its Compacted copy, when that's neither its ready file nor its `.7z`: on N64 and Mega Drive, a `.zip` that a loose
    /// file (or a subfolder) is Played over.
    public let compactedBesideReady: URL?
    /// A subfolder's Discs, in Disc order, when it has no playlist for them: its ready file is then Disc 1.
    public let discsWithoutPlaylist: [URL]
    /// The file the journal shows for it, as a path in the ROM folder: the ready one (inside its
    /// subfolder, if it's in one), else the archive.
    let fileName: String

    public init(
        name: String, ready: URL?, archive: URL?, compactedBesideReady: URL? = nil, in root: URL? = nil,
        discsWithoutPlaylist: [URL] = []
    ) {
        self.name = name
        self.ready = ready
        self.archive = archive
        self.compactedBesideReady = compactedBesideReady
        self.discsWithoutPlaylist = discsWithoutPlaylist
        let file = ready ?? archive
        let rootPath = root?.standardizedFileURL.path(percentEncoded: false)
        if let file, let rootPath, file.standardizedFileURL.path(percentEncoded: false).hasPrefix(rootPath) {
            fileName = String(file.standardizedFileURL.path(percentEncoded: false).dropFirst(rootPath.count))
        } else {
            fileName = file?.lastPathComponent ?? name
        }
    }

    public var archived: Bool { ready == nil }
    public var needsPlaylist: Bool { !discsWithoutPlaylist.isEmpty }
    /// Kept in more than one form at once, which a ROM never should be, so it waits in the Review queue: its ready file
    /// beside its `.7z` (Archived, or its Compacted copy) or beside a Compacted `.zip`. Any other loose file of its name
    /// isn't a form of it: it may be part of the ready one, as a playlist's Disc is.
    public var inBothForms: Bool { ready != nil && (compactedBesideReady != nil || (archive != nil && archive != ready)) }

    public static func == (a: Self, b: Self) -> Bool {
        a.name == b.name && a.ready == b.ready && a.archive == b.archive && a.compactedBesideReady == b.compactedBesideReady
            && a.discsWithoutPlaylist == b.discsWithoutPlaylist
    }
}

/// Moving one ROM from its ROM folder into another's: its ready file (with its subfolder, or a cue sheet's tracks)
/// and its `.7z`, each to the same place in the other folder.
struct ROMMove {
    let moves: [(from: URL, to: URL)]

    /// Checks everything before anything moves: the ROM's files are there, the other folder has nothing in their way,
    /// and it reads the ROM's file.
    static func plan(_ name: String, from: ROMFolder, to: ROMFolder) throws -> ROMMove {
        guard let rom = try? from.rom(named: name) else { throw ReviewError.romFilesNotFound }
        if (try? to.rom(named: name)) != nil { throw ReviewError.alreadyInROMFolder }
        var items: [URL]
        if let subfolder = from.subfolder(of: name, holding: rom.ready) {
            items = [subfolder]
        } else if let ready = rom.ready {
            guard to.reads(fileName: ready.lastPathComponent) else { throw ReviewError.siblingWontReadFile }
            items = ROMFiles.files(of: ready)
        } else {
            items = []
        }
        if let archive = rom.archive, !items.contains(archive) { items.append(archive) }
        let base = from.url.standardizedFileURL.path(percentEncoded: false)
        let moves = items.map { item in
            let path = item.standardizedFileURL.path(percentEncoded: false)
            let relative =
                path.hasPrefix(base) ? String(path.dropFirst(base.count)).trimmingPrefix("/").description : item.lastPathComponent
            return (from: item, to: to.url.appending(path: relative))
        }
        if moves.contains(where: { FileManager.default.fileExists(atPath: $0.to.path(percentEncoded: false)) }) {
            throw ReviewError.alreadyInROMFolder
        }
        return ROMMove(moves: moves)
    }

    /// Moves every file; on a failure, moves back the ones already moved.
    func run() throws {
        for (i, move) in moves.enumerated() {
            do {
                try FileManager.default.createDirectory(at: move.to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: move.from, to: move.to)
            } catch {
                ROMMove(moves: Array(moves.prefix(i))).undo()
                throw error
            }
        }
    }

    /// Moves the files back, as far as it can.
    func undo() {
        for move in moves.reversed() { try? FileManager.default.moveItem(at: move.to, to: move.from) }
    }
}
