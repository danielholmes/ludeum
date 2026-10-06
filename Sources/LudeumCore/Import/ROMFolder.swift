import Foundation

/// A ROM folder: one IGDB Platform's ROMs, read straight from a folder. The folder alone gives a ROM
/// its Platform. A ROM there is known by its name: a file's without the extension, or a subfolder's. So Unarchiving
/// `Okami (USA).7z` into `Okami (USA)/` is the same ROM changing from archived to ready. A subfolder
/// is a ROM when it holds the game: one cue sheet, or one image, at any depth. Hidden folders are ignored.
public struct ROMFolder: Sendable, Equatable {
    /// The IGDB platform its ROMs are on.
    public let platformId: Int64
    public let url: URL
    /// What its Emulator opens, most preferred first. Anything else but a `.7z` is ignored.
    let readyExtensions: [String]

    /// PS2, played in PCSX2.
    public static func ps2(_ url: URL) -> ROMFolder { platform(ROMPlatform.ps2, url)! }

    /// The ROM folder of a Platform that has one.
    public static func platform(_ id: Int64, _ url: URL) -> ROMFolder? {
        ROMPlatform.all[id].map { ROMFolder(platformId: id, url: url, readyExtensions: $0.readyExtensions) }
    }

    /// Every ROM in the folder, by name. Throws when the folder can't be read (Dropbox not there,
    /// say), so an Import leaves its ROMs alone instead of marking them all missing.
    public func scan() throws -> [FolderROMFile] {
        let items = try FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false)).filter { !$0.hasPrefix(".") }
        let files = items.map { url.appending(path: $0, directoryHint: .notDirectory) }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        let folders = items.map { url.appending(path: $0, directoryHint: .isDirectory) }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        // A cue sheet's tracks belong to it.
        let tracks = Set(files.filter { $0.pathExtension.lowercased() == "cue" }.flatMap(Self.cueTracks).map { $0.lowercased() })
        var ready: [String: URL] = [:]
        var archives: [String: URL] = [:]
        for file in files where !tracks.contains(file.lastPathComponent.lowercased()) {
            let name = file.deletingPathExtension().lastPathComponent
            let ext = file.pathExtension.lowercased()
            if ext == "7z" {
                archives[name] = file
            } else if let rank = readyExtensions.firstIndex(of: ext) {
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
            if let game = gameFile(in: folder) { ready[folder.lastPathComponent] = game }
        }
        return Set(ready.keys).union(archives.keys).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { FolderROMFile(name: $0, ready: ready[$0], archive: archives[$0], in: url) }
    }

    /// The game in a subfolder: its one cue sheet, else its one image. Nil when there's neither, or more than one.
    private func gameFile(in folder: URL) -> URL? {
        let files = ((try? FileManager.default.subpathsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? [])
            .map { folder.appending(path: $0, directoryHint: .notDirectory) }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        let images = files.filter { readyExtensions.contains($0.pathExtension.lowercased()) }
        let cues = images.filter { $0.pathExtension.lowercased() == "cue" }
        if cues.count == 1 { return cues[0] }
        return cues.isEmpty && images.count == 1 ? images[0] : nil
    }

    /// The file a Play opens for the ROM `name`, if it isn't archived.
    public func readyFile(named name: String) throws -> URL? {
        try scan().first { $0.name == name }?.ready
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

/// One ROM in a ROM folder: its ready file, its `.7z` archive, or both. Archived when there's no ready file.
public struct FolderROMFile: Sendable, Equatable {
    public let name: String
    public let ready: URL?
    public let archive: URL?
    /// The file the journal shows for it, as a path in the ROM folder: the ready one (inside its
    /// subfolder, if it's in one), else the archive.
    let fileName: String

    public init(name: String, ready: URL?, archive: URL?, in root: URL? = nil) {
        self.name = name
        self.ready = ready
        self.archive = archive
        let file = ready ?? archive
        let rootPath = root?.standardizedFileURL.path(percentEncoded: false)
        if let file, let rootPath, file.standardizedFileURL.path(percentEncoded: false).hasPrefix(rootPath) {
            fileName = String(file.standardizedFileURL.path(percentEncoded: false).dropFirst(rootPath.count))
        } else {
            fileName = file?.lastPathComponent ?? name
        }
    }

    public var archived: Bool { ready == nil }

    public static func == (a: Self, b: Self) -> Bool { a.name == b.name && a.ready == b.ready && a.archive == b.archive }
}
