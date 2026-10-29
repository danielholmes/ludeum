import Foundation

/// ares's Save states and Game saves for one Platform, in its system's folder under `Emulators/ares/Saves/` in the
/// Data folder (ADR 0028): Ludeum lists a ROM's, Plays from a Save state and deletes one; ares makes them. ares names
/// them by the ROM's file name without its extension (a `.zip`'s own, whatever's inside), and keeps a Sega CD Game's
/// states with the Mega Drive's, as it plays the Mega CD as one. The Sega CD's own backup RAM, in `Mega CD/`, is every
/// Sega CD Game's, so no one Game's Game save.
public struct AresSaves: Sendable {
    /// The system's folder.
    public let folder: URL
    /// The system's screenshots.
    let screenshots: URL

    /// Nil for a Platform ares doesn't play.
    public init?(ludeum: LudeumFolder = .standard, platformId: Int64) {
        guard Emulator.of(platformId: platformId) == .ares else { return nil }
        let name = Self.folderName(platformId)
        self.init(
            folder: ludeum.aresSaves.appending(path: name, directoryHint: .isDirectory),
            screenshots: ludeum.aresScreenshots.appending(path: name, directoryHint: .isDirectory))
    }

    /// The folder ares keeps a Platform's Games' files in, named for the core that plays them: the Sega CD's are the
    /// Mega Drive's, as ares plays the Mega CD as one.
    static func folderName(_ platformId: Int64) -> String { platformId == 4 ? "Nintendo 64" : "Mega Drive" }

    init(folder: URL, screenshots: URL) {
        self.folder = folder
        self.screenshots = screenshots
    }

    /// The slot of a Save state's extension, `bs1` to `bs9`.
    static func slot(ofExtension ext: String) -> Int? {
        guard ext.count == 3, ext.hasPrefix("bs"), let n = Int(ext.dropFirst(2)), (1...9).contains(n) else { return nil }
        return n
    }

    /// What ares names a Game save by: the cartridge's memory (`ram`, `eeprom`, `flash`, `rtc`) and an N64 Controller
    /// Pak, `pak` in port 1, `2.pak` in port 2 and so on.
    static func isGameSave(_ rest: Substring) -> Bool {
        ["ram", "eeprom", "flash", "rtc", "pak"].contains(String(rest)) || rest.wholeMatch(of: /[2-9]\.pak/) != nil
    }

    /// The Save states of the ROM ares names `name`, by slot. `serial` holds the name.
    public func states(of name: String) -> [SaveState] {
        Self.files(in: folder).compactMap { file -> SaveState? in
            guard file.deletingPathExtension().lastPathComponent == name, let slot = Self.slot(ofExtension: file.pathExtension),
                let saved = Self.modified(file)
            else { return nil }
            return SaveState(serial: name, slot: .numbered(slot), previous: false, saved: saved, file: file)
        }
        .sorted { $0.slot < $1.slot }
    }

    /// The Game saves of the ROM ares names `name`, by file name.
    public func gameSaves(of name: String) -> [GameSaveFile] {
        Self.files(in: folder).filter {
            $0.lastPathComponent.hasPrefix(name + ".") && Self.isGameSave($0.lastPathComponent.dropFirst(name.count + 1))
        }
        .compactMap { file in Self.modified(file).map { GameSaveFile(file: file, saved: $0) } }
        .sorted { $0.fileName < $1.fileName }
    }

    /// Every file ares keeps by `name`: its Save states and the undo files it keeps beside them (`.bsu`, `.blu`), its Game
    /// saves, and its screenshots (`<name> <yyyy-MM-dd HH-mm-ss>.png`).
    func files(of name: String) -> [URL] {
        Self.files(in: folder).filter {
            $0.deletingPathExtension().lastPathComponent == name
                && (Self.slot(ofExtension: $0.pathExtension) != nil || ["bsu", "blu"].contains($0.pathExtension))
        }
            + gameSaves(of: name).map(\.file)
            + Self.files(in: screenshots).filter {
                $0.pathExtension == "png" && $0.lastPathComponent.hasPrefix(name + " ")
                    && $0.deletingPathExtension().lastPathComponent.dropFirst(name.count + 1)
                        .wholeMatch(of: /\d{4}-\d\d-\d\d \d\d-\d\d-\d\d/) != nil
            }
    }

    /// Sends it to the Trash.
    public func delete(_ state: SaveState, moveToTrash: (URL) throws -> Void = Trash.move) throws {
        try moveToTrash(state.file)
    }

    /// Moves every file ares keeps by `oldName` to `name`, as a Rename does.
    func move(_ oldName: String, to name: String) throws {
        for file in files(of: oldName) {
            let rest = file.lastPathComponent.dropFirst(oldName.count)
            try FileManager.default.moveItem(at: file, to: file.deletingLastPathComponent().appending(path: name + rest))
        }
    }

    private static func files(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).map {
            folder.appending(path: $0)
        }
    }

    private static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.modificationDate] as? Date
    }
}

/// Why an ares ROM's Rename was refused, with nothing renamed.
public enum AresRenameError: LocalizedError, Equatable {
    /// ares already keeps a file under the new name in the system's folders.
    case savesInTheWay(String)

    public var errorDescription: String? {
        switch self {
        case .savesInTheWay(let file): "ares already keeps \(file) under that name, so nothing was renamed."
        }
    }
}

extension LudeumStore {
    /// Renames an ares ROM as `renameROM(_:to:in:)` does, and its Save states, Game saves and screenshots, which ares
    /// keys by the ROM file's name (ADR 0028): a loose file's, or an Archived cartridge ROM's, which is its name again
    /// once it's Unarchived. A disc ROM's cue sheet in its subfolder keeps its name, and so its saves. Refused, with
    /// nothing renamed, when ares already keeps a file under the new name.
    public func renameAresROM(_ rom: Int64, from oldName: String, to name: String, in folder: ROMFolder, ludeum: LudeumFolder = .standard)
        throws
    {
        let ready = try folder.readyFile(named: oldName)
        let namedByIt =
            if let ready { ready.deletingLastPathComponent().standardizedFileURL == folder.url.standardizedFileURL } else {
                ROMPlatform.all[folder.platformId]?.archiving != .intoFolder
            }
        guard namedByIt, let saves = AresSaves(ludeum: ludeum, platformId: folder.platformId) else {
            return try renameROM(rom, to: name, in: folder)
        }
        if let taken = saves.files(of: name).first { throw AresRenameError.savesInTheWay(taken.lastPathComponent) }
        try renameROM(rom, to: name, in: folder)
        try saves.move(oldName, to: name)
    }
}
