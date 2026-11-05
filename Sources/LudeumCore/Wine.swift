import Darwin
import Foundation

extension LudeumFolder {
    /// The Wine Ludeum installs (ADR 0040): its `bin`, `lib` and `share`, with nothing of it an app.
    public var wineFolder: URL { emulators.appending(path: "Wine", directoryHint: .isDirectory) }

    /// Where each Windows ROM's prefix is, outside the Data folder: Wine makes one again in seconds.
    public var winePrefixes: URL { emulators.appending(path: "Wine Prefixes", directoryHint: .isDirectory) }

    /// The prefix of the ROM `name`: the Windows it runs in, with the clone of its game a Play runs.
    public func winePrefix(ofROM name: String) -> URL { winePrefixes.appending(path: name, directoryHint: .isDirectory) }

    /// Where Windows Games' Game saves are, in the Data folder.
    public var wineSaves: URL { data.appending(path: "Emulators/Wine/Saves", directoryHint: .isDirectory) }

    /// The Game save of the ROM `name`: what its game wrote, in a folder of its own.
    public func wineSave(ofROM name: String) -> WineGameSave {
        WineGameSave(folder: wineSaves.appending(path: name, directoryHint: .isDirectory))
    }
}

/// The Wine Ludeum installs and keeps (ADR 0040): `Emulators/Wine/` in the Ludeum folder, one pinned build for every
/// Windows ROM, whose `bin/wine` Ludeum runs directly.
///
/// It has no settings file to keep in step: everything a Play fixes is environment for the one launch (`WINEPREFIX`,
/// `WINEDLLOVERRIDES`, `WINEDEBUG`, `LC_ALL`), and what a game needs is in its ROM's launch file (`WineLaunchFile`).
public struct WineSettings: Sendable, Equatable {
    /// Where the engine is.
    public let folder: URL
    /// The Ludeum folder, which holds the ROMs' prefixes, and whose Data folder holds their Game saves.
    let ludeum: LudeumFolder

    public init(ludeum: LudeumFolder = .standard) {
        self.folder = ludeum.wineFolder
        self.ludeum = ludeum
    }

    var wine: URL { folder.appending(path: "bin/wine", directoryHint: .notDirectory) }
    var wineserver: URL { folder.appending(path: "bin/wineserver", directoryHint: .notDirectory) }

    /// Its `wine` and `wineserver` are there.
    public var isInstalled: Bool {
        [wine, wineserver].allSatisfy { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
    }

    /// What Install recorded of the build that's there, or nil for a copy Ludeum didn't install.
    public var installed: WineRelease.Installed? { WineRelease.Installed(folder: folder) }

    /// The DLLs every launch turns off: Wine's .NET and its web browser, which no game here uses and which a new prefix
    /// would otherwise stop to install.
    static let disabledDLLs = ["mscoree", "mshtml"]

    /// The environment of a `wine` or `wineserver` run in `prefix`: Ludeum's own with Wine's settings set over it. A
    /// game's DLL `overrides` come ahead of the ones every launch turns off.
    func environment(prefix: URL, overrides: [String: String] = [:], locale: String? = nil) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("WINE") }
        environment["WINEPREFIX"] = Self.withoutSlash(prefix)
        let games = overrides.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        let disabled = Self.disabledDLLs.filter { overrides[$0] == nil }
        environment["WINEDLLOVERRIDES"] = (games + (disabled.isEmpty ? [] : [disabled.joined(separator: ",") + "="])).joined(separator: ";")
        environment["WINEDEBUG"] = "-all"
        if let locale { environment["LC_ALL"] = locale }
        return environment
    }

    /// A folder's path without a trailing `/`.
    static func withoutSlash(_ folder: URL) -> String {
        let path = folder.path(percentEncoded: false)
        return path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
    }

    /// Whether anything of this Wine is running, for any ROM: a game, or the `wineserver` that outlives it by a few
    /// seconds. Install replaces the engine, so it waits for none to be.
    public var isRunning: Bool {
        // The folder as the system names it, through any link: a process's path is given that way.
        guard let real = realpath(Self.withoutSlash(folder), nil) else { return false }
        defer { free(real) }
        let prefix = String(cString: real) + "/"
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let found = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard found > 0 else { return false }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids.prefix(Int(found)) where pid > 0 {
            let length = proc_pidpath(pid, &path, UInt32(path.count))
            guard length > 0 else { continue }
            if String(decoding: path.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self).hasPrefix(prefix) { return true }
        }
        return false
    }

    /// Whether a `wineserver` is running for `prefix`: its game is still open, or closed less than a few seconds ago.
    /// The server holds a lock on a file it names for the prefix's folder (`/tmp/.wine-<uid>/server-<device>-<inode>/lock`,
    /// in Wine's `server/request.c`), which is what `wineserver -k` and `-w` look at too.
    public func isRunning(prefix: URL) -> Bool {
        var info = stat()
        guard stat(Self.withoutSlash(prefix), &info) == 0 else { return false }
        let lock =
            "/tmp/.wine-\(getuid())/server-\(String(UInt64(bitPattern: Int64(info.st_dev)), radix: 16))-\(String(info.st_ino, radix: 16))/lock"
        let descriptor = open(lock, O_RDONLY)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var held = flock(l_start: 0, l_len: 1, l_pid: 0, l_type: Int16(F_WRLCK), l_whence: Int16(SEEK_SET))
        guard fcntl(descriptor, F_GETLK, &held) != -1 else { return false }
        return held.l_type != Int16(F_UNLCK)
    }

    /// Takes away the prefix of a ROM that's gone, unless it holds a Play's Game save not yet kept, or its game is still
    /// running. Its Game save stays in the Data folder, as with every Emulator's.
    public func removePrefix(ofROM name: String) {
        let prefix = ludeum.winePrefix(ofROM: name)
        guard !isRunning(prefix: prefix),
            !FileManager.default.fileExists(atPath: WinePlay.saveToKeep(in: prefix).path(percentEncoded: false))
        else { return }
        try? FileManager.default.removeItem(at: prefix)
    }
}

/// A Windows ROM's launch file, `launch.json` at the top of its subfolder (ADR 0040): the file a Play opens, saying how
/// the prepared game beside it is started. Its paths are written with `/`.
///
/// ```json
/// {
///   "exe": "EMPIRES.EXE",
///   "installedAt": "Games/AoE",
///   "dllOverrides": { "ddraw": "n,b" },
///   "locale": "en_US.UTF-8",
///   "registryFile": "aoe.reg",
///   "drives": [{ "letter": "d", "kind": "cdrom", "label": "AOE" }],
///   "windowsFiles": { "ir41_32.dll": "syswow64/ir41_32.dll", "Fonts": "Fonts" },
///   "registryKeys": ["HKEY_CURRENT_USER\\Software\\Microsoft\\Games\\Age of Empires\\1.00"]
/// }
/// ```
public struct WineLaunchFile: Codable, Sendable, Equatable {
    /// The exe a Play starts, a path inside the ROM's `Game` folder.
    public var exe: String
    /// The folder it starts in, a path inside `Game`. Left out, it's the exe's own.
    public var startsIn: String?
    /// What follows the exe on its command line.
    public var arguments: [String]?
    /// Where the game's folder is on the prefix's C: drive, e.g. `Games/AoE` for `C:\Games\AoE`: where its registry values
    /// say it's installed. Left out, it's `Game`.
    public var installedAt: String?
    /// The DLLs Wine takes from the game's folder ahead of its own, or turns off, each as Wine writes it: `n,b` for
    /// native then builtin, nothing for off.
    public var dllOverrides: [String: String]?
    /// The locale the game runs in, e.g. `en_GB.UTF-8`. Left out, it's this Mac's.
    public var locale: String?
    /// A registry file in the ROM's `Prefix` folder, imported when the prefix is made.
    public var registryFile: String?
    /// The drives the prefix is given beside C:.
    public var drives: [Drive]?
    /// Files and folders in the ROM's `Prefix` folder, each with where it goes in the prefix's `windows` folder. A folder
    /// is laid over the one there.
    public var windowsFiles: [String: String]?
    /// The registry keys that are the game's own, as a 64-bit Windows names them (a 32-bit game's under
    /// `HKEY_LOCAL_MACHINE\Software` are in `Wow6432Node`). They're kept in its Game save.
    public var registryKeys: [String]?

    /// A drive made for the game: an empty folder that says it's this kind of drive, with this label, which is as much
    /// as a disc check that looks at the two needs.
    public struct Drive: Codable, Sendable, Equatable {
        public var letter: String
        public var kind: Kind
        public var label: String?

        public enum Kind: String, Codable, Sendable {
            case hd, floppy, cdrom, network, ramdisk
        }
    }

    /// The launch file's name in a Windows ROM's subfolder.
    public static let name = "launch.json"
    /// The folders beside it: the game as it has to be to run, and what's laid into its prefix.
    static let gameFolder = "Game"
    static let prefixFolder = "Prefix"

    /// Where the game's folder is on the C: drive.
    var installed: String { installedAt ?? "Game" }

    /// Reads a ROM's launch file and checks it against the ROM around it, so a Play that would go wrong says why first.
    public static func read(_ file: URL) throws(WineLaunchFileError) -> WineLaunchFile {
        let launch: WineLaunchFile
        do {
            launch = try JSONDecoder().decode(WineLaunchFile.self, from: try Data(contentsOf: file))
        } catch let error as DecodingError {
            throw .unreadable(describe(error))
        } catch {
            throw .unreadable(error.localizedDescription)
        }
        try launch.check(in: file.deletingLastPathComponent())
        return launch
    }

    /// What's wrong with its JSON, in words that name the entry.
    private static func describe(_ error: DecodingError) -> String {
        func entry(_ path: [any CodingKey]) -> String {
            path.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        }
        return switch error {
        case .keyNotFound(let key, let context): "it has no \"\(entry(context.codingPath + [key]))\""
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            "its \"\(entry(context.codingPath))\" isn't the kind of value it should be"
        case .dataCorrupted(let context) where context.codingPath.isEmpty: "it isn't JSON"
        case .dataCorrupted(let context): "its \"\(entry(context.codingPath))\" isn't a value it can be"
        @unknown default: "it isn't a launch file"
        }
    }

    /// Throws when it names something outside the ROM or not in it, or a drive, DLL or registry key that can't be.
    func check(in rom: URL) throws(WineLaunchFileError) {
        let files = FileManager.default
        func exists(_ url: URL, folder: Bool? = nil) -> Bool {
            var isFolder: ObjCBool = false
            guard files.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isFolder) else { return false }
            return folder.map { $0 == isFolder.boolValue } ?? true
        }
        let game = rom.appending(path: Self.gameFolder, directoryHint: .isDirectory)
        let prefix = rom.appending(path: Self.prefixFolder, directoryHint: .isDirectory)
        guard exists(game, folder: true) else { throw .noGameFolder }
        for path in [exe, installed] + [startsIn, registryFile].compactMap({ $0 }) + (windowsFiles ?? [:]).flatMap({ [$0.key, $0.value] })
        where !Self.isInside(path) {
            throw .outside(path)
        }
        // Each Play replaces what's there, so not Windows' own folders, nor anywhere in the two it changes as it runs.
        let top = installed.split(separator: "/").map { $0.lowercased() }
        if ["windows", "users"].contains(top[0])
            || (top.count == 1 && ["program files", "program files (x86)", "programdata"].contains(top[0]))
        {
            throw .cantInstallAt(installed)
        }
        guard exists(game.appending(path: exe), folder: false) else { throw .notFound("\(Self.gameFolder)/\(exe)") }
        if let startsIn, !exists(game.appending(path: startsIn), folder: true) { throw .notFound("\(Self.gameFolder)/\(startsIn)") }
        if let registryFile, !exists(prefix.appending(path: registryFile), folder: false) {
            throw .notFound("\(Self.prefixFolder)/\(registryFile)")
        }
        for from in (windowsFiles ?? [:]).keys.sorted() where !exists(prefix.appending(path: from)) {
            throw .notFound("\(Self.prefixFolder)/\(from)")
        }
        var letters: Set<String> = []
        for drive in drives ?? [] {
            let letter = drive.letter.lowercased()
            // C: is the prefix's own, and Z: is this Mac's disk.
            guard letter.count == 1, ("d"..."y").contains(letter), letters.insert(letter).inserted else { throw .badDrive(drive.letter) }
            if let label = drive.label, label.isEmpty || label.contains(where: \.isNewline) { throw .badDrive(drive.letter) }
        }
        for (dll, order) in dllOverrides ?? [:] {
            guard !dll.isEmpty, dll.allSatisfy({ $0.isLetter || $0.isNumber || "._-*".contains($0) }),
                order.allSatisfy({ $0.isLetter || $0 == "," })
            else { throw .badOverride(dll) }
        }
        if let locale, locale.isEmpty || !locale.allSatisfy({ $0.isLetter || $0.isNumber || "_.@-".contains($0) }) {
            throw .badLocale(locale)
        }
        for key in registryKeys ?? [] {
            guard ["HKEY_LOCAL_MACHINE\\", "HKEY_CURRENT_USER\\"].contains(where: { key.hasPrefix($0) && key.count > $0.count }),
                !key.contains("\""), !key.contains(where: \.isNewline)
            else { throw .badRegistryKey(key) }
        }
    }

    /// Whether a path stays inside the folder it's read from: written with `/`, from no root, and never climbing out.
    static func isInside(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"), !path.contains("\\") else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    /// A path inside the game's folder as Windows writes it on the C: drive: `C:\Games\AoE\EMPIRES.EXE`.
    func windowsPath(_ path: String) -> String {
        "C:\\" + (installed + "/" + path).split(separator: "/").joined(separator: "\\")
    }
}

/// What's wrong with a Windows ROM's launch file.
public enum WineLaunchFileError: LocalizedError, Equatable {
    /// It couldn't be read as a launch file, with why.
    case unreadable(String)
    /// There's no `Game` folder beside it.
    case noGameFolder
    /// It names a file or folder that isn't in the ROM.
    case notFound(String)
    /// It names a path that isn't one inside the ROM.
    case outside(String)
    /// It puts the game's folder where Windows keeps its own.
    case cantInstallAt(String)
    /// A drive that can't be made: not one letter from D to Y, one made twice, or with a label that can't be one.
    case badDrive(String)
    /// A DLL override that isn't one.
    case badOverride(String)
    case badLocale(String)
    /// A registry key that isn't under `HKEY_LOCAL_MACHINE` or `HKEY_CURRENT_USER`.
    case badRegistryKey(String)

    public var errorDescription: String? {
        let file = WineLaunchFile.name
        return switch self {
        case .unreadable(let why): "Its \(file) can't be read: \(why)."
        case .noGameFolder: "It has no \(WineLaunchFile.gameFolder) folder beside its \(file)."
        case .notFound(let path): "Its \(file) names \(path), which isn't in it."
        case .outside(let path): "Its \(file) names \(path), which isn't a path inside it, written with /."
        case .cantInstallAt(let path): "Its \(file) puts the game at \(path) on the C: drive, which is Windows' own folder."
        case .badDrive(let letter): "Its \(file) makes a drive \(letter), which isn't one letter from D to Y, made once, with a label."
        case .badOverride(let dll): "Its \(file) overrides the DLL \(dll) in a way Wine doesn't read."
        case .badLocale(let locale): "Its \(file) names the locale \(locale), which isn't one."
        case .badRegistryKey(let key):
            "Its \(file) names the registry key \(key), which isn't under HKEY_LOCAL_MACHINE or HKEY_CURRENT_USER."
        }
    }
}

/// Why a Windows ROM's Rename was refused, with nothing renamed.
public enum WineRenameError: LocalizedError, Equatable {
    /// There's already a Game save or a prefix under the new name.
    case inTheWay(String)

    public var errorDescription: String? {
        switch self {
        case .inTheWay(let name): "Wine already keeps a Game save or a prefix for \(name), so nothing was renamed."
        }
    }
}

extension LudeumStore {
    /// Renames a Windows ROM as `renameROM(_:to:in:)` does, and its Game save's folder and its prefix with it. Refused,
    /// with nothing renamed, when either is already there under the new name.
    public func renameWineROM(
        _ rom: Int64, from oldName: String, to name: String, in folder: ROMFolder, ludeum: LudeumFolder = .standard
    ) throws {
        let files = FileManager.default
        let moves = [
            (ludeum.wineSave(ofROM: oldName).folder, ludeum.wineSave(ofROM: name).folder),
            (ludeum.winePrefix(ofROM: oldName), ludeum.winePrefix(ofROM: name)),
        ]
        // Differing only in case, they're the one folder.
        let sameFolder = oldName.caseInsensitiveCompare(name) == .orderedSame
        if !sameFolder, moves.contains(where: { files.fileExists(atPath: $0.1.path(percentEncoded: false)) }) {
            throw WineRenameError.inTheWay(name)
        }
        try renameROM(rom, to: name, in: folder)
        for (old, new) in moves where files.fileExists(atPath: old.path(percentEncoded: false)) { try files.moveItem(at: old, to: new) }
    }
}
