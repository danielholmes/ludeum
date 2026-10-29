import Foundation

/// The name MesenCE keeps a ROM's Save states, Game saves and screenshots by (ADR 0027): its file's name without its
/// extension, or the name of the file inside its `.7z`, with nothing of its Platform in it. A disc ROM's is its cue
/// sheet's.
public struct MesenROMName: Sendable, Equatable {
    /// The name, without an extension: `DuckTales (USA)`.
    public let name: String
    /// The path of the file MesenCE opens inside the ROM's archive, when it's in one.
    public let inArchive: String?

    /// MesenCE's name for the ROM whose ready file is `file`, listing it with 7-Zip when it's an archive (the file in it
    /// MesenCE opens: the one of the Platform's kinds, else the first). Nil for an archive 7-Zip can't list, or one with
    /// no file in it.
    public static func of(_ file: URL, platformId: Int64, sevenZip: SevenZip? = .find()) async -> MesenROMName? {
        guard ["7z", "zip"].contains(file.pathExtension.lowercased()) else {
            return MesenROMName(name: file.deletingPathExtension().lastPathComponent, inArchive: nil)
        }
        guard let sevenZip, let entries = try? await sevenZip.contents(of: file) else { return nil }
        let kinds = ROMPlatform.all[platformId]?.readyExtensions ?? []
        let entry = entries.first { kinds.contains(($0.fileName as NSString).pathExtension.lowercased()) } ?? entries.first
        return entry.map { MesenROMName(name: ($0.fileName as NSString).deletingPathExtension, inArchive: $0.path) }
    }

    /// The path of a file inside an archive given `name`, keeping its folder and extension.
    static func path(_ inside: String, renamedTo name: String) -> String {
        ((inside as NSString).deletingLastPathComponent as NSString).appendingPathComponent(name + "." + (inside as NSString).pathExtension)
    }
}

/// A Game save an Emulator keeps for a ROM by its name, which the game wrote itself: MesenCE's `<name>.srm`, `.sav`,
/// `.rtc` and the like, ares's `<name>.ram`, `.eeprom`, `.pak` and the like.
public struct GameSaveFile: Sendable, Equatable, Identifiable {
    public let file: URL
    /// When the Emulator last wrote it: its file's modification date. MesenCE writes one when the Game stops, ares every
    /// 30 seconds of play too.
    public let saved: Date

    public var fileName: String { file.lastPathComponent }
    public var id: String { fileName }
}

/// MesenCE's Save states and Game saves for one Platform, in its folders under `Emulators/MesenCE/<Platform>/` in the
/// Data folder (ADR 0027): Ludeum lists a ROM's, Plays from a Save state and deletes one; MesenCE makes them.
public struct MesenSaveStates: Sendable {
    public let saveStates: URL
    public let saves: URL
    let screenshots: URL

    /// Nil for a Platform MesenCE doesn't play.
    public init?(ludeum: LudeumFolder = .standard, platformId: Int64) {
        guard let saveStates = ludeum.mesen(.saveStates, platform: platformId), let saves = ludeum.mesen(.saves, platform: platformId),
            let screenshots = ludeum.mesen(.screenshots, platform: platformId)
        else { return nil }
        self.init(saveStates: saveStates, saves: saves, screenshots: screenshots)
    }

    init(saveStates: URL, saves: URL, screenshots: URL) {
        self.saveStates = saveStates
        self.saves = saves
        self.screenshots = screenshots
    }

    /// The slot MesenCE's automatic Save state goes in, which a Game resumes from.
    static let resumeSlot = 11

    /// The Save states of the ROM MesenCE names `name`: Resume, then by slot. `serial` holds the name.
    public func states(of name: String) -> [SaveState] {
        Self.files(in: saveStates).compactMap { file -> SaveState? in
            guard file.pathExtension == "mss", let slot = Self.slot(file.deletingPathExtension().lastPathComponent, of: name),
                let saved = Self.modified(file)
            else { return nil }
            return SaveState(
                serial: name, slot: slot == Self.resumeSlot ? .resume : .numbered(slot), previous: false, saved: saved, file: file)
        }
        .sorted { $0.slot < $1.slot }
    }

    /// The Game saves of the ROM MesenCE names `name`, by file name.
    public func gameSaves(of name: String) -> [GameSaveFile] {
        Self.files(in: saves).filter { $0.lastPathComponent.hasPrefix(name + ".") }
            .compactMap { file in Self.modified(file).map { GameSaveFile(file: file, saved: $0) } }
            .sorted { $0.fileName < $1.fileName }
    }

    /// Every file MesenCE keeps by `name`: its Save states (`<name>_<slot>.mss`), Game saves (`<name>.<ext>`) and
    /// screenshots (`<name>_<nnn>.png`).
    func files(of name: String) -> [URL] {
        Self.files(in: saveStates).filter {
            $0.pathExtension == "mss" && Self.slot($0.deletingPathExtension().lastPathComponent, of: name) != nil
        }
            + gameSaves(of: name).map(\.file)
            + Self.files(in: screenshots).filter { Self.isScreenshot($0.deletingPathExtension().lastPathComponent, of: name) }
    }

    /// Whether a file's name without its extension is one of `name`'s screenshots, `<name>_<nnn>`, numbered from `000`.
    static func isScreenshot(_ stem: String, of name: String) -> Bool {
        guard stem.hasPrefix(name + "_") else { return false }
        let rest = stem.dropFirst(name.count + 1)
        return !rest.isEmpty && rest.allSatisfy(\.isASCII) && rest.allSatisfy(\.isNumber)
    }

    /// Sends it to the Trash.
    public func delete(_ state: SaveState, moveToTrash: (URL) throws -> Void = Trash.move) throws {
        try moveToTrash(state.file)
    }

    /// The slot in a file's name without its extension, `<name>_<slot>`, when it's `name`'s.
    static func slot(_ stem: String, of name: String) -> Int? {
        guard stem.hasPrefix(name + "_") else { return nil }
        let rest = stem.dropFirst(name.count + 1)
        guard let n = Int(rest), n > 0, String(n) == rest else { return nil }
        return n
    }

    private static func files(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).map {
            folder.appending(path: $0)
        }
    }

    private static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.modificationDate] as? Date
    }

    /// The ROM's file name a Save state was saved with, read from its header: `DuckTales (USA).nes`. Nil when it isn't
    /// a MesenCE state.
    static func romName(inState data: Data) -> String? { MesenStateHeader(data)?.romName }

    /// Moves every file MesenCE keeps by `oldName` to `name`, as a Rename does.
    func move(_ oldName: String, to name: String) throws {
        for file in files(of: oldName) {
            let rest = file.lastPathComponent.dropFirst(oldName.count)
            try FileManager.default.moveItem(at: file, to: file.deletingLastPathComponent().appending(path: name + rest))
        }
    }
}

/// Why a MesenCE ROM's Rename was refused, with nothing renamed.
public enum MesenRenameError: LocalizedError, Equatable {
    /// MesenCE already keeps a file under the new name in the Platform's folders.
    case savesInTheWay(String)

    public var errorDescription: String? {
        switch self {
        case .savesInTheWay(let file): "MesenCE already keeps \(file) under that name, so nothing was renamed."
        }
    }
}

extension LudeumStore {
    /// Renames a MesenCE ROM as `renameROM(_:to:in:)` does, and what MesenCE keys it by (ADR 0027): the file inside its
    /// `.7z` when that has the ROM's name (7-Zip's `rn`, which doesn't repack), renamed first and put back should the
    /// ROM's own rename fail, then its Save states, Game saves and screenshots in its Platform's folders. A ROM MesenCE
    /// names otherwise keeps its saves as they are: a disc ROM's cue sheet in its subfolder, or a file inside of
    /// another name. Refused, with nothing renamed, when MesenCE already keeps a file under the new name.
    public func renameMesenROM(
        _ rom: Int64, from oldName: String, to name: String, in folder: ROMFolder, ludeum: LudeumFolder = .standard,
        sevenZip: SevenZip? = .find()
    ) async throws {
        // Only a loose file, or an archive, is renamed with the ROM: a subfolder's files keep their names.
        guard let ready = try folder.readyFile(named: oldName),
            ready.deletingLastPathComponent().standardizedFileURL == folder.url.standardizedFileURL,
            let key = await MesenROMName.of(ready, platformId: folder.platformId, sevenZip: sevenZip), key.name == oldName
        else { return try renameROM(rom, to: name, in: folder) }
        let saves = MesenSaveStates(ludeum: ludeum, platformId: folder.platformId)
        if let taken = saves?.files(of: name).first { throw MesenRenameError.savesInTheWay(taken.lastPathComponent) }
        var inside: (from: String, to: String)?
        if let path = key.inArchive, let sevenZip {
            inside = (path, MesenROMName.path(path, renamedTo: name))
            try await sevenZip.rename(path, to: MesenROMName.path(path, renamedTo: name), in: ready)
        }
        do {
            try renameROM(rom, to: name, in: folder)
        } catch {
            if let inside, let sevenZip { try? await sevenZip.rename(inside.to, to: inside.from, in: ready) }
            throw error
        }
        try saves?.move(oldName, to: name)
    }
}
