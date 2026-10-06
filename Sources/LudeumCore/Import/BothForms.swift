import Foundation

/// A ROM kept in both forms at once, and how that's resolved: one copy is kept and every other goes to the Trash.
public struct BothForms: Sendable, Equatable {
    /// The copy that's kept: its file, or its subfolder. The Compacted copy when there is one, since it's smaller and
    /// still Plays; else the one a Play opens.
    public let keep: URL
    /// Whether the copy kept is the Compacted one, not the Playable copy beside an Archived `.7z`.
    public let keepsCompacted: Bool
    /// What goes to the Trash, each a file or a subfolder: every other copy, a cue sheet with its tracks.
    public let trash: [URL]

    /// The room a copy takes: its file's size, or everything in its subfolder.
    public static func size(of copy: URL) -> Int64 {
        (try? copy.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? Sizes.total(in: copy) : Sizes.size(of: copy)
    }
}

extension ROMFolder {
    /// How the ROM `name` is resolved when it's kept in both forms; nil when it isn't.
    public func bothForms(named name: String) throws -> BothForms? {
        try scan().first { $0.name == name }.flatMap(bothForms)
    }

    /// As `bothForms(named:)`, for a ROM from a scan.
    func bothForms(of rom: FolderROMFile) -> BothForms? {
        guard rom.inBothForms, let ready = rom.ready else { return nil }
        // Each copy by its file, with everything it's made of: the one a Play opens first.
        let subfolder = rom.fileName.hasPrefix(rom.name + "/") ? url.appending(path: rom.name, directoryHint: .isDirectory) : nil
        var copies = [(file: ready, items: subfolder.map { [$0] } ?? Self.looseItems(ready))]
        for file in rom.otherForms + (rom.archive.map { [$0] } ?? []) where file != ready {
            copies.append((file, Self.looseItems(file)))
        }
        let compacted = compactExtension.flatMap { ext in copies.firstIndex { $0.file.pathExtension.lowercased() == ext } }
        let kept = compacted ?? 0
        return BothForms(
            keep: kept == 0 ? subfolder ?? ready : copies[kept].file, keepsCompacted: compacted != nil,
            trash: copies.enumerated().filter { $0.offset != kept }.flatMap(\.element.items))
    }

    /// A loose file with what belongs to it: a cue sheet's tracks.
    private static func looseItems(_ file: URL) -> [URL] {
        file.pathExtension.lowercased() == "cue" ? ROMFiles.files(of: file) : [file]
    }
}
