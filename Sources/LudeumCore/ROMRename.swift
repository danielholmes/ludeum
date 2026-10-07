import Foundation

/// Renaming a ROM after its Game: the Game's name with the ROM's own tags kept, so `Ōkami (USA).iso` becomes
/// `Okami (USA).iso` and its Version and Disc still read from its name.
public enum ROMRename {
    /// The name to offer a ROM named `romName` (a file's without its extension, or a subfolder's), or nil when it's
    /// already its Game's name followed by nothing but tags, or when its ROM folder couldn't read the Game's name.
    public static func newName(forROM romName: String, gameName: String) -> String? {
        let fileTitle = fitForAFileName(gameName)
        guard !fileTitle.isEmpty, !fileTitle.hasPrefix(".") else { return nil }
        // Checked against the Game's whole name, as it can have tags of its own: "Foo (2008) (USA)" is Foo (2008)'s.
        if romName == fileTitle || (romName.hasPrefix(fileTitle + " ") && ROMName(String(romName.dropFirst(fileTitle.count))).title.isEmpty)
        {
            return nil
        }
        let title = ROMName(romName).title
        guard romName.hasPrefix(title) else { return nil }
        let tags = romName.dropFirst(title.count).trimmingCharacters(in: .whitespaces)
        let name = tags.isEmpty ? fileTitle : "\(fileTitle) \(tags)"
        return name == romName ? nil : name
    }

    /// A colon as No-Intro writes it (" - "), and a slash, which no file name can hold, as "-".
    static func fitForAFileName(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*:\s*"#, with: " - ", options: .regularExpression)
            .replacingOccurrences(of: "/", with: "-")
    }
}

public enum ROMRenameError: Error, Equatable, LocalizedError {
    /// A name its ROM folder wouldn't read back: empty, hidden (starting with a dot) or holding a slash.
    case unreadableName

    public var errorDescription: String? {
        "Its ROM folder can't read that name, so nothing was renamed."
    }
}

extension LudeumStore {
    /// Renames the ROM in its ROM folder, every form it's kept in (`ROMMove.rename`), and in the journal, where it stays
    /// the same ROM with its Match. Refused, with nothing moved, when another ROM has the name in any case, in the
    /// folder or in the journal (a missing one keeps its name so its file can come back to it), or when its ROM folder
    /// wouldn't read the name. A name differing only in case is still a rename.
    public func renameROM(_ rom: Int64, to name: String, in folder: ROMFolder) throws {
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/") else { throw ROMRenameError.unreadableName }
        let (oldName, taken) = try db.read { db in
            let oldName = try String.fetchOne(
                db, sql: "SELECT folderName FROM rom WHERE id = ? AND platformId = ?", arguments: [rom, folder.platformId])
            let taken = try Bool.fetchOne(
                db, sql: "SELECT EXISTS (SELECT 1 FROM rom WHERE platformId = ? AND folderName = ? COLLATE NOCASE AND id <> ?)",
                arguments: [folder.platformId, name, rom])!
            return (oldName, taken)
        }
        guard let oldName else { throw ReviewError.romFilesNotFound }
        if taken { throw ReviewError.alreadyInROMFolder }
        let move = try ROMMove.rename(oldName, to: name, in: folder)
        try move.run()
        do {
            guard let file = try folder.rom(named: name) else { throw ROMRenameError.unreadableName }
            try db.write { db in
                try db.execute(sql: "UPDATE rom SET folderName = ?, name = ? WHERE id = ?", arguments: [name, name, rom])
                try Self.setFolderROM(db, rom, to: file)
            }
        } catch {
            move.undo()
            throw error
        }
    }
}
