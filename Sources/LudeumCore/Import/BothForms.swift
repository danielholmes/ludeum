import Foundation

/// How a ROM kept in both forms at once is resolved: one copy is kept and every other goes to the Trash.
public struct BothForms: Sendable, Equatable {
    /// The copy that's kept: its file, or its subfolder.
    public let keep: URL
    /// Whether the copy kept is its Compacted one, over the one a Play opens, since it's smaller and still Plays. Else
    /// it's the Playable copy, over its Archived `.7z`.
    public let keepsCompacted: Bool
    /// What goes to the Trash, each a file or a subfolder: every other copy.
    public let trash: [URL]

    /// The room a copy takes: everything in its subfolder, or its file with a cue sheet's tracks.
    public static func size(of copy: URL) -> Int64 {
        (try? copy.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            ? Sizes.total(in: copy) : ROMFiles.files(of: copy).reduce(0) { $0 + Sizes.size(of: $1) }
    }
}

extension ROMFolder {
    /// How the ROM `name` is resolved when it's kept in both forms; nil when it isn't.
    public func bothForms(named name: String) throws -> BothForms? {
        try rom(named: name).flatMap(bothForms)
    }

    /// As `bothForms(named:)`, for a ROM from a scan.
    func bothForms(of rom: FolderROMFile) -> BothForms? {
        guard rom.inBothForms, let ready = rom.ready else { return nil }
        // The copy a Play opens is its subfolder, whole, when it's in one.
        let played = rom.fileName.hasPrefix(rom.name + "/") ? url.appending(path: rom.name, directoryHint: .isDirectory) : ready
        let others = [rom.archive, rom.compactedBesideReady].compactMap { $0 }.filter { $0 != ready }
        let compacted = others.first { $0.pathExtension.lowercased() == compactExtension }
        let keep = compacted ?? played
        return BothForms(keep: keep, keepsCompacted: compacted != nil, trash: ([played] + others).filter { $0 != keep })
    }
}
