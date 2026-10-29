import Foundation

/// The ares release Ludeum installs (ADR 0028): a versioned tag, pinned with its universal zip's SHA-256 as GitHub's
/// release API gives it. A bump is the version and digest here, and costs every Save state, as a state loads only in
/// the build that saved it.
public struct AresRelease: Sendable, Equatable {
    /// Its number, the tag without its "v": what `--version` prints, after a "v".
    public let version: String
    /// The zip's SHA-256, lowercase hex.
    public let sha256: String

    public static let pinned = AresRelease(version: "148", sha256: "1ae232ab6de341210f171f51d84b311527eb1399060706589334a8a7de136bb0")

    /// Where the zip is.
    public var url: URL {
        URL(string: "https://github.com/ares-emulator/ares/releases/download/v\(version)/ares-macos-universal.zip")!
    }
}

/// Why an Install stopped, with nothing replaced.
public enum AresInstallError: LocalizedError, CustomStringConvertible, Equatable {
    /// GitHub hadn't the zip.
    case notFound(version: String, status: Int)
    /// The zip isn't the one the release's digest names.
    case badChecksum(expected: String, found: String)
    /// The zip had no ares.app in it.
    case noApp
    /// `ditto` couldn't unpack the zip, with what it said.
    case couldntUnpack(String)
    /// The app in the zip says it's another version, or couldn't say.
    case wrongBuild(found: String?)

    /// `description`, so a Background task's failure shows it.
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .notFound(let version, let status): "Couldn't download ares v\(version): GitHub answered \(status)."
        case .badChecksum(let expected, let found): "The download isn't the release Ludeum expects (SHA-256 \(found), not \(expected))."
        case .noApp: "The download has no ares.app in it."
        case .couldntUnpack(let why): "Couldn't unpack the download: \(why)"
        case .wrongBuild(let found):
            "The download says it's \(found.map { "v\($0)" } ?? "no version"), not v\(AresRelease.pinned.version)."
        }
    }
}

/// Installs the ares Ludeum keeps (ADR 0028): fetches the pinned release's zip, checks it against the digest, unpacks
/// it with no quarantine, checks its build, and swaps the app into `Emulators/ares/ares.app` in the Ludeum folder. It's
/// made portable by the `settings.bml` beside it: the one the copy it replaces kept, else the one ares keeps for itself
/// (`existing`), with my controls. Then the Standing settings are written. Its version is checked with a portable
/// `settings.bml` of its own in the download's folder, as ares writes one whenever it starts, so it writes none of mine.
/// Nothing is replaced until the new copy checks out.
public struct AresInstaller: Sendable {
    let ludeum: LudeumFolder
    let release: AresRelease
    let transport: any HTTPTransport
    /// The `settings.bml` an ares that isn't portable keeps for itself.
    let existing: URL

    /// `release`, `transport` and `existing` stand in for the pinned release, the real GitHub and ares's own settings,
    /// in tests.
    public init(
        ludeum: LudeumFolder = .standard, release: AresRelease = .pinned, transport: any HTTPTransport = URLSessionTransport(),
        existing: URL = URL.applicationSupportDirectory.appending(path: "ares/settings.bml")
    ) {
        self.ludeum = ludeum
        self.release = release
        self.transport = transport
        self.existing = existing
    }

    /// Where the download is unpacked and checked before it's swapped in. Cleared first and after.
    var work: URL { ludeum.emulators.appending(path: ".installing ares", directoryHint: .isDirectory) }

    /// `progress` is told how far it's got, 0 to 1.
    public func install(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let files = FileManager.default
        try ludeum.checkData()
        try? files.removeItem(at: work)
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: work) }

        let zip = work.appending(path: release.url.lastPathComponent)
        let response = try await transport.download(URLRequest(url: release.url), to: zip) { progress($0 * 0.8) }
        guard response.statusCode == 200 else { throw AresInstallError.notFound(version: release.version, status: response.statusCode) }
        try Task.checkCancellation()
        let digest = try EmulatorInstall.sha256(of: zip)
        guard digest == release.sha256.lowercased() else {
            throw AresInstallError.badChecksum(expected: release.sha256, found: digest)
        }

        // The release zip holds `ares-v<version>/ares.app`.
        let unpacked = work.appending(path: "unpacked", directoryHint: .isDirectory)
        do {
            try EmulatorInstall.unpack(zip, into: unpacked)
        } catch let failed as EmulatorInstall.CouldntUnpack {
            throw AresInstallError.couldntUnpack(failed.message)
        }
        progress(0.9)
        let folders = [unpacked] + ((try? files.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)) ?? [])
        guard
            let app = folders.map({ $0.appending(path: "ares.app", directoryHint: .isDirectory) })
                .first(where: { files.isExecutableFile(atPath: $0.appending(path: "Contents/MacOS/ares").path(percentEncoded: false)) })
        else { throw AresInstallError.noApp }
        EmulatorInstall.removeQuarantine(app)
        try Data().write(to: app.deletingLastPathComponent().appending(path: AresSettings.fileName))
        let found = EmulatorVersions.read(.ares, app: app).flatMap { EmulatorVersions.parse($0, .dotted) }
        guard let found, found == Int(release.version).map({ [$0] }) else {
            throw AresInstallError.wrongBuild(found: found?.map(String.init).joined(separator: "."))
        }
        try Task.checkCancellation()

        // The swap: the old copy aside, the new one in; should the new one not go in, the old one goes back. What ares
        // keeps is beside the app, not in it, so it stays where it is.
        let installed = ludeum.aresApp
        let replaced = ludeum.aresFolder.appending(path: "ares (replaced).app", directoryHint: .isDirectory)
        try files.createDirectory(at: ludeum.aresFolder, withIntermediateDirectories: true)
        try? files.removeItem(at: replaced)
        let hadOne = files.fileExists(atPath: installed.path(percentEncoded: false))
        if hadOne { try files.moveItem(at: installed, to: replaced) }
        do {
            try files.moveItem(at: app, to: installed)
        } catch {
            if hadOne { try? files.moveItem(at: replaced, to: installed) }
            throw error
        }
        if hadOne { try files.removeItem(at: replaced) }
        let settings = AresSettings(ludeum: ludeum)
        if !settings.isPortable, files.fileExists(atPath: existing.path(percentEncoded: false)) {
            try files.copyItem(at: existing, to: settings.settingsFile)
        }
        try settings.writeStanding()
        progress(1)
    }
}

extension LudeumFolder {
    /// The folder of the ares Ludeum installs (ADR 0028): the app, and beside it the `settings.bml` that makes it
    /// portable.
    public var aresFolder: URL { emulators.appending(path: "ares", directoryHint: .isDirectory) }

    /// The ares Ludeum installs.
    public var aresApp: URL { aresFolder.appending(path: "ares.app", directoryHint: .isDirectory) }

    /// Where ares keeps Save states and Game saves, a folder for each of its systems: `Emulators/ares/Saves/` in the
    /// Data folder.
    public var aresSaves: URL { data.appending(path: "Emulators/ares/Saves", directoryHint: .isDirectory) }

    /// Where ares keeps screenshots, a folder for each of its systems.
    public var aresScreenshots: URL { data.appending(path: "Emulators/ares/Screenshots", directoryHint: .isDirectory) }
}

/// The ares Ludeum installs and keeps (ADR 0028): `Emulators/ares/ares.app` in the Ludeum folder, made portable by a
/// `settings.bml` beside it, which ares finds there before its own in Application Support, so no other ares shares it.
///
/// Its **Standing settings** are written before every Play: its Saves path (Save states and Game saves alike) and its
/// screenshots into the Data folder, where ares makes a folder for each of its systems, and Game saves written every 30
/// seconds of play. ares rewrites the whole file when it starts and quits, so they're only written while it isn't
/// running. Everything else in the file is ares's own, and what's changed in it during a Play lasts. Run-ahead, the
/// Game's own, is a `--setting` for that launch, which ares puts back when it quits.
public struct AresSettings: Sendable {
    /// The ares.app Ludeum installs.
    public let app: URL
    /// The Ludeum folder, whose Data folder holds what ares keeps.
    let ludeum: LudeumFolder

    public init(ludeum: LudeumFolder = .standard) {
        self.app = ludeum.aresApp
        self.ludeum = ludeum
    }

    /// The name ares looks for beside its app.
    static let fileName = "settings.bml"

    /// Its `settings.bml`, beside it.
    var settingsFile: URL { app.deletingLastPathComponent().appending(path: Self.fileName) }

    /// The app's executable is there.
    public var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/ares").path(percentEncoded: false))
    }

    /// Its `settings.bml` is beside it, so its settings are its own.
    public var isPortable: Bool { FileManager.default.fileExists(atPath: settingsFile.path(percentEncoded: false)) }

    /// The system ares plays a Platform's Games as.
    static func system(_ platformId: Int64) -> String {
        switch platformId {
        case 4: "Nintendo 64"
        case 78: "Mega CD"
        default: "Mega Drive"
        }
    }

    /// Writes the Standing settings, then gives the ROM to open as its Platform's system, starting from `saveState`'s
    /// slot if given (`<name>.bs<slot>`, which ares finds by the ROM's name). Run-ahead is on or off (one frame): any
    /// run-ahead frames turn it on, for this launch only.
    func arguments(rom: URL, platformId: Int64, settings: EmulatorSettings, saveState: URL? = nil) throws -> [String] {
        try writeStanding()
        let slot = saveState.flatMap { AresSaves.slot(ofExtension: $0.pathExtension) }
        return ["--system", Self.system(platformId), "--setting", "General/RunAhead=\((settings.runAheadFrames ?? 0) > 0)"]
            + (slot.map { ["--save-state", String($0)] } ?? []) + [rom.path(percentEncoded: false)]
    }

    /// Writes the Standing settings into `settings.bml`, making the folders they name. Refused while the Data folder is
    /// missing, so nothing is kept somewhere Dropbox doesn't see. The file is left alone when it already says so.
    public func writeStanding() throws {
        try ludeum.checkData()
        for folder in [ludeum.aresSaves, ludeum.aresScreenshots] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let original = try? String(contentsOf: settingsFile, encoding: .utf8)
        let updated = Self.standing(in: original ?? "", ludeum: ludeum)
        guard updated != original else { return }
        try FileManager.default.createDirectory(at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try updated.write(to: settingsFile, atomically: true, encoding: .utf8)
    }

    /// `bml` with the Standing settings. ares appends a system's name to a path, so each ends in `/`.
    static func standing(in bml: String, ludeum: LudeumFolder) -> String {
        func path(_ folder: URL) -> String {
            let path = folder.path(percentEncoded: false)
            return path.hasSuffix("/") ? path : path + "/"
        }
        var bml = BML.setting("Paths/Saves", to: path(ludeum.aresSaves), in: bml)
        bml = BML.setting("Paths/Screenshots", to: path(ludeum.aresScreenshots), in: bml)
        return BML.setting("General/AutoSaveMemory", to: "true", in: bml)
    }
}

/// ares's settings format: a node a line, `Name` or `Name: value`, its children indented two spaces under it.
enum BML {
    /// `bml` with the node at `path` (`Paths/Saves`) set to `value`, the rest as it was: an empty one given its value, and
    /// one that's missing added at the end of its parent's children, its parent too if that's missing.
    static func setting(_ path: String, to value: String, in bml: String) -> String {
        var lines = bml.isEmpty ? [] : bml.components(separatedBy: "\n")
        // The file's last newline leaves an empty last line, which stays last.
        let trailing = lines.last == "" ? lines.removeLast() : nil
        let names = path.split(separator: "/").map(String.init)
        var start = 0
        var end = lines.count
        for (depth, name) in names.enumerated() {
            let indent = String(repeating: "  ", count: depth)
            let line = indent + name + (depth == names.count - 1 ? ": \(value)" : "")
            if let found = (start..<end).first(where: { node(lines[$0], depth: depth) == name }) {
                if depth == names.count - 1 { lines[found] = line }
                start = found + 1
                end = (start..<end).first { lines[$0].isEmpty || indentation(lines[$0]) <= depth * 2 } ?? end
            } else {
                // At the end of the parent's children, before any blank lines that close them.
                var at = end
                while at > start, lines[at - 1].isEmpty { at -= 1 }
                lines.insert(line, at: at)
                start = at + 1
                end = start
            }
        }
        if let trailing { lines.append(trailing) } else if !lines.isEmpty { lines.append("") }
        return lines.joined(separator: "\n")
    }

    /// The name of the node on `line`, when it's at `depth`.
    private static func node(_ line: String, depth: Int) -> String? {
        guard indentation(line) == depth * 2, !line.isEmpty else { return nil }
        let rest = line.dropFirst(depth * 2)
        return String(rest.prefix { $0 != ":" }).trimmingCharacters(in: .whitespaces)
    }

    private static func indentation(_ line: String) -> Int { line.prefix { $0 == " " }.count }
}

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
        let system = platformId == 4 ? "Nintendo 64" : "Mega Drive"
        self.init(
            folder: ludeum.aresSaves.appending(path: system, directoryHint: .isDirectory),
            screenshots: ludeum.aresScreenshots.appending(path: system, directoryHint: .isDirectory))
    }

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
    /// keys by the ROM file's name (ADR 0028). A disc ROM's cue sheet in its subfolder keeps its name, and so its saves.
    /// Refused, with nothing renamed, when ares already keeps a file under the new name.
    public func renameAresROM(_ rom: Int64, from oldName: String, to name: String, in folder: ROMFolder, ludeum: LudeumFolder = .standard)
        throws
    {
        guard let ready = try folder.readyFile(named: oldName),
            ready.deletingLastPathComponent().standardizedFileURL == folder.url.standardizedFileURL,
            let saves = AresSaves(ludeum: ludeum, platformId: folder.platformId)
        else { return try renameROM(rom, to: name, in: folder) }
        if let taken = saves.files(of: name).first { throw AresRenameError.savesInTheWay(taken.lastPathComponent) }
        try renameROM(rom, to: name, in: folder)
        try saves.move(oldName, to: name)
    }
}
