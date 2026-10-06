import Foundation

/// Every file a ROM is made of, starting from the file a Play opens: a cue sheet brings its tracks,
/// and a playlist its discs (and their tracks). Files it names that aren't there are left out.
public enum ROMFiles {
    public static func files(of main: URL) -> [URL] {
        var out: [URL] = []
        func add(_ file: URL) {
            guard !out.contains(file), FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return }
            out.append(file)
            let folder = file.deletingLastPathComponent()
            switch file.pathExtension.lowercased() {
            case "cue": for track in ROMFolder.cueTracks(file) { add(folder.appending(path: track)) }
            case "m3u": for disc in playlistEntries(file) { add(folder.appending(path: disc)) }
            default: break
            }
        }
        add(main)
        return out
    }

    /// A playlist's lines, less blanks and comments.
    static func playlistEntries(_ m3u: URL) -> [String] {
        guard let text = try? String(contentsOf: m3u, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}

extension ROMFolder {
    /// Every file of the ROM `name`: everything in its subfolder, else its loose file (with a cue
    /// sheet's tracks), and its `.7z` and the Compacted copy beside its ready file, when there is one.
    public func files(named name: String) throws -> [URL] {
        guard let rom = try scan().first(where: { $0.name == name }) else { return [] }
        return try files(of: rom)
    }

    /// Every file of a ROM from a scan, as `files(named:)`.
    func files(of rom: FolderROMFile) throws -> [URL] {
        var files: [URL] = []
        if let subfolder = subfolder(of: rom.name, holding: rom.ready) {
            files = try FileManager.default.subpathsOfDirectory(atPath: subfolder.path(percentEncoded: false)).sorted()
                .map { subfolder.appending(path: $0, directoryHint: .notDirectory) }
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        } else if let ready = rom.ready {
            files = ROMFiles.files(of: ready)
        }
        return files + [rom.archive, rom.compactedBesideReady].compactMap { $0 }.filter { !files.contains($0) }
    }
}
