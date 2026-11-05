import CryptoKit
import Foundation

/// A Windows Game's Game save (ADR 0040): what its game wrote, in a folder named for its ROM under `Emulators/Wine/Saves/`
/// in the Data folder. Its `Game` folder holds every file of a Play's clone that was new or differed from the ROM's, at
/// the path it had there, and `Registry.reg` the game's own registry keys as `regedit` exports them.
///
/// Nothing about a game has to be known to keep it but those keys. It holds a few files that aren't saves (a settings
/// file the game rewrites), which costs nothing.
public struct WineGameSave: Sendable, Equatable {
    public let folder: URL

    /// The files the game wrote, at their paths in its folder.
    public var files: URL { folder.appending(path: "Game", directoryHint: .isDirectory) }
    /// The game's own registry keys.
    public var registry: URL { folder.appending(path: "Registry.reg", directoryHint: .notDirectory) }

    /// What it holds, for Game detail: its files' paths in the game's folder, whether it has registry keys, and when the
    /// newest of it was written. Nil when there's no Game save yet.
    public func contents() -> (files: [String], hasRegistry: Bool, written: Date)? {
        let paths = Self.regularFiles(in: files)
        let hasRegistry = FileManager.default.fileExists(atPath: registry.path(percentEncoded: false))
        let all = paths.map { files.appending(path: $0, directoryHint: .notDirectory) } + (hasRegistry ? [registry] : [])
        guard let written = all.compactMap({ try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }).max()
        else { return nil }
        return (paths, hasRegistry, written)
    }

    /// The paths of every file in a folder, at any depth, in order. None when the folder isn't there.
    static func regularFiles(in folder: URL) -> [String] {
        ((try? FileManager.default.subpathsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).sorted().filter {
            (try? folder.appending(path: $0, directoryHint: .notDirectory).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile)
                == true
        }
    }

    /// Lays its files over a fresh clone of the ROM's game, each at its path.
    func lay(over game: URL) throws {
        let fileManager = FileManager.default
        for path in Self.regularFiles(in: files) {
            let destination = game.appending(path: path, directoryHint: .notDirectory)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fileManager.removeItem(at: destination)
            try fileManager.copyItem(at: files.appending(path: path, directoryHint: .notDirectory), to: destination)
        }
    }

    /// Keeps what a Play wrote: every file of `clone` that's new or differs from the one in `original`, the ROM's game,
    /// and `registry`, the export of the game's keys. What it held that the clone no longer differs in goes, so it's
    /// always the whole difference; a file that hasn't changed since it was last kept is left as it is, for Dropbox.
    func gather(from clone: URL, against original: URL, registry exported: Data?) throws {
        let fileManager = FileManager.default
        let changed = Self.regularFiles(in: clone).filter { path in
            Self.differs(
                clone.appending(path: path, directoryHint: .notDirectory),
                from: original.appending(path: path, directoryHint: .notDirectory))
        }
        for path in changed {
            let source = clone.appending(path: path, directoryHint: .notDirectory)
            let destination = files.appending(path: path, directoryHint: .notDirectory)
            let kept = destination.path(percentEncoded: false)
            if fileManager.fileExists(atPath: kept), fileManager.contentsEqual(atPath: source.path(percentEncoded: false), andPath: kept) {
                continue
            }
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Whole or not at all: copied beside where it goes, then swapped in.
            let incoming = destination.deletingLastPathComponent().appending(path: ".\(UUID().uuidString)", directoryHint: .notDirectory)
            try fileManager.copyItem(at: source, to: incoming)
            if fileManager.fileExists(atPath: kept) { try fileManager.removeItem(at: destination) }
            try fileManager.moveItem(at: incoming, to: destination)
        }
        let wanted = Set(changed)
        for path in Self.regularFiles(in: files) where !wanted.contains(path) {
            try fileManager.removeItem(at: files.appending(path: path, directoryHint: .notDirectory))
        }
        Self.removeEmptyFolders(in: files)
        if let exported {
            if (try? Data(contentsOf: registry)) != exported {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                try exported.write(to: registry, options: .atomic)
            }
        } else if fileManager.fileExists(atPath: registry.path(percentEncoded: false)) {
            try fileManager.removeItem(at: registry)
        }
        Self.removeEmptyFolders(in: folder)
        if (try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false)))?.isEmpty == true {
            try? fileManager.removeItem(at: folder)
        }
    }

    /// Whether a file of the clone isn't the ROM's: new, another size, or, written since it was cloned, other bytes. A
    /// clone keeps the time its original was written, so a file with the ROM's size and time is never read.
    static func differs(_ file: URL, from original: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let theirs = try? original.resourceValues(forKeys: keys), let size = theirs.fileSize,
            let mine = try? file.resourceValues(forKeys: keys)
        else { return true }
        if mine.fileSize != size { return true }
        if let written = mine.contentModificationDate, written == theirs.contentModificationDate { return false }
        return !FileManager.default.contentsEqual(atPath: file.path(percentEncoded: false), andPath: original.path(percentEncoded: false))
    }

    /// Removes every folder under `folder` that holds nothing, deepest first.
    private static func removeEmptyFolders(in folder: URL) {
        let fileManager = FileManager.default
        let paths = ((try? fileManager.subpathsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).sorted().reversed()
        for path in paths {
            let item = folder.appending(path: path, directoryHint: .isDirectory)
            guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                let inside = try? fileManager.contentsOfDirectory(atPath: item.path(percentEncoded: false)),
                inside.allSatisfy({ $0 == ".DS_Store" })
            else { continue }
            try? fileManager.removeItem(at: item)
        }
    }
}

/// Why a Play in Wine stopped.
public enum WinePlayError: LocalizedError, Equatable {
    /// The ROM's game is still running in Wine, or closed less than a few seconds ago.
    case stillRunning
    /// Wine couldn't make the ROM's prefix: `wineboot` ended with this status, or left no registry.
    case couldntMakePrefix(String)
    /// `reg` couldn't import a registry file into the prefix.
    case couldntImportRegistry(String)
    /// One of Wine's own programs, run for Ludeum's housekeeping, hadn't ended after this long, and was stopped.
    case tookTooLong(String, seconds: Int)
    /// The last Play's Game save is still in the prefix and couldn't be kept, so nothing is cloned over it.
    case couldntKeepLastSave(String, prefix: String)
    /// Wine ended as it started the game, with this status: what it said is in this file.
    case endedAtOnce(status: Int32, log: String)

    public var errorDescription: String? {
        switch self {
        case .stillRunning: Play.Refusal.stillRunning.message
        case .couldntMakePrefix(let why): "Wine couldn't make its prefix: \(why)"
        case .couldntImportRegistry(let file): "Wine couldn't import \(file) into its prefix's registry."
        case .tookTooLong(let what, let seconds): "Wine's \(what) hadn't ended after \(seconds) seconds, so it was stopped."
        case .couldntKeepLastSave(let why, let prefix):
            "Its last Play's Game save couldn't be kept, so it wasn't started over it: \(why) It's still in \(prefix)."
        case .endedAtOnce(let status, let log): "Wine ended as it started the game (status \(status)). What it said is in \(log)."
        }
    }
}

/// A Play of a Windows ROM in Wine (ADR 0040). The ROM is never run: its `Game` folder is cloned afresh into the ROM's own
/// prefix, the ROM's Game save is laid over the clone, the exe is started, and once the game and its `wineserver` have
/// ended, whatever the clone then differs from the ROM in is the Game save again.
///
/// The prefix is in `Emulators/Wine Prefixes/<ROM name>/` in the Ludeum folder, made when it's missing or was made by
/// another build of Wine or another launch file: Wine builds its Windows, then the launch file's files are laid into
/// it, its drives made and its registry file imported. It holds two files of Ludeum's: what it was made from, and, from
/// when a game is started until its Game save is kept, a note that it has one to keep, so a Play Ludeum didn't see end
/// (it quit first) has its save kept before the next clone replaces it.
public struct WinePlay: Sendable, Equatable {
    /// The ROM's name, which names its prefix and its Game save.
    public let romName: String
    /// The ROM's subfolder, holding its launch file, `Game` and `Prefix`.
    let rom: URL
    let launch: WineLaunchFile
    /// The launch file's SHA-256, which the prefix remembers being made from.
    let launchDigest: String
    let wine: WineSettings

    /// Reads and checks the ROM's launch file. Nothing is touched until `run`.
    init(launchFile: URL, romName: String, wine: WineSettings) throws {
        self.romName = romName
        rom = launchFile.deletingLastPathComponent()
        launch = try WineLaunchFile.read(launchFile)
        launchDigest = try EmulatorInstall.sha256(of: launchFile)
        self.wine = wine
    }

    /// How far a Play has got.
    public enum Phase: Sendable, Equatable {
        /// Keeping the Game save of a Play that ended without Ludeum.
        case keepingLastSave
        /// Wine is building the ROM's Windows: about twenty seconds, the first time.
        case makingPrefix
        /// Cloning the game and laying its Game save over the clone.
        case gettingReady
        case playing
        /// The game has ended: waiting for Wine to write its registry, then keeping the Game save.
        case keepingSave

        /// What Play's button says meanwhile.
        public var title: String {
            switch self {
            case .keepingLastSave: "Keeping its last Game save…"
            case .makingPrefix: "Setting up Windows…"
            case .gettingReady: "Getting it ready…"
            case .playing: "Playing in Wine"
            case .keepingSave: "Keeping its Game save…"
            }
        }
    }

    var prefix: URL { wine.ludeum.winePrefix(ofROM: romName) }
    /// The clone a Play runs, on the prefix's C: drive where the launch file says the game is installed.
    var game: URL {
        prefix.appending(path: "drive_c", directoryHint: .isDirectory).appending(path: launch.installed, directoryHint: .isDirectory)
    }
    var original: URL { rom.appending(path: WineLaunchFile.gameFolder, directoryHint: .isDirectory) }
    var save: WineGameSave { wine.ludeum.wineSave(ofROM: romName) }

    /// What the prefix was made from: the Wine build and the launch file.
    static func madeFrom(in prefix: URL) -> URL { prefix.appending(path: "Made by Ludeum.txt", directoryHint: .notDirectory) }
    /// There while the clone holds a Play's Game save that hasn't been kept.
    static func saveToKeep(in prefix: URL) -> URL { prefix.appending(path: "Game save to keep.txt", directoryHint: .notDirectory) }
    /// What Wine said during the last Play.
    static func log(in prefix: URL) -> URL { prefix.appending(path: "Last Play.log", directoryHint: .notDirectory) }

    /// What a prefix made now would remember: the installed build's record, then the launch file's digest.
    private var madeFromNow: String { (wine.installed?.text ?? "") + launchDigest + "\n" }

    /// Whether the ROM's game is running in Wine now, or closed less than a few seconds ago.
    public var isRunning: Bool { wine.isRunning(prefix: prefix) }

    /// Whether the prefix is there and was made by this build from this launch file.
    var prefixIsCurrent: Bool {
        FileManager.default.fileExists(atPath: prefix.appending(path: "system.reg").path(percentEncoded: false))
            && (try? String(contentsOf: Self.madeFrom(in: prefix), encoding: .utf8)) == madeFromNow
    }

    /// Plays it, start to end, telling `phase` how far it's got. It returns once the game has ended and its Game save is
    /// kept, which can be hours. Throws, with the ROM and its Game save as they were, when anything before the game starts
    /// goes wrong; and when the Game save couldn't be kept afterwards, which leaves it in the prefix for the next Play.
    public func run(phase: @escaping @Sendable (Phase) -> Void = { _ in }) async throws {
        try wine.ludeum.checkData()
        guard !isRunning else { throw WinePlayError.stillRunning }
        let files = FileManager.default
        if files.fileExists(atPath: Self.saveToKeep(in: prefix).path(percentEncoded: false)) {
            phase(.keepingLastSave)
            do {
                try await keepSave()
            } catch {
                throw WinePlayError.couldntKeepLastSave(error.localizedDescription, prefix: prefix.path(percentEncoded: false))
            }
        }
        if !prefixIsCurrent {
            phase(.makingPrefix)
            try await makePrefix()
        }

        phase(.gettingReady)
        try? files.removeItem(at: game)
        try files.createDirectory(at: game.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A clone on APFS: a fraction of a second, and no room taken until the game writes.
        try files.copyItem(at: original, to: game)
        try save.lay(over: game)
        if files.fileExists(atPath: save.registry.path(percentEncoded: false)) { try await importRegistry(save.registry) }
        try Data().write(to: Self.saveToKeep(in: prefix))

        phase(.playing)
        let started = Date()
        let startsIn =
            launch.startsIn.map { game.appending(path: $0, directoryHint: .isDirectory) }
            ?? game.appending(path: launch.exe, directoryHint: .notDirectory).deletingLastPathComponent()
        let log = Self.log(in: prefix)
        let status = try await WineProcess.run(
            wine.wine, [launch.windowsPath(launch.exe)] + (launch.arguments ?? []),
            environment: wine.environment(prefix: prefix, overrides: launch.dllOverrides ?? [:], locale: launch.locale), in: startsIn,
            output: log)

        phase(.keepingSave)
        try await waitForServer()
        try await keepSave()
        if status != 0, Date().timeIntervalSince(started) < 10 {
            throw WinePlayError.endedAtOnce(status: status, log: log.path(percentEncoded: false))
        }
    }

    /// Keeps what the clone differs from the ROM in, with the game's registry keys, as the ROM's Game save.
    private func keepSave() async throws {
        let registry = try await exportRegistry()
        try save.gather(from: game, against: original, registry: registry)
        try? FileManager.default.removeItem(at: Self.saveToKeep(in: prefix))
    }

    /// Makes the prefix anew: Wine builds its Windows, then the launch file's files go into its `windows` folder, its
    /// drives are made, and its registry file is imported.
    private func makePrefix() async throws {
        let files = FileManager.default
        if files.fileExists(atPath: prefix.path(percentEncoded: false)) { try files.removeItem(at: prefix) }
        try files.createDirectory(at: prefix, withIntermediateDirectories: true)
        // About twenty seconds; twice that the first time this Mac runs the engine, as Rosetta translates it.
        let status = try await housekeeping(["wineboot", "--init"], seconds: 300)
        try await waitForServer()
        guard status == 0, files.fileExists(atPath: prefix.appending(path: "system.reg").path(percentEncoded: false)) else {
            throw WinePlayError.couldntMakePrefix(status == 0 ? "wineboot left no registry." : "wineboot ended with status \(status).")
        }

        let windows = prefix.appending(path: "drive_c/windows", directoryHint: .isDirectory)
        let laid = rom.appending(path: WineLaunchFile.prefixFolder, directoryHint: .isDirectory)
        for (from, to) in (launch.windowsFiles ?? [:]).sorted(by: { $0.key < $1.key }) {
            try Self.lay(laid.appending(path: from), over: windows.appending(path: to))
        }

        if let drives = launch.drives, !drives.isEmpty {
            var kinds = "REGEDIT4\n\n[HKEY_LOCAL_MACHINE\\Software\\Wine\\Drives]\n"
            for drive in drives {
                let letter = drive.letter.lowercased()
                // An empty folder in the prefix, linked as the drive: a label is a file at its top.
                let folder = prefix.appending(path: "drives/\(letter)", directoryHint: .isDirectory)
                try files.createDirectory(at: folder, withIntermediateDirectories: true)
                if let label = drive.label { try Data(label.utf8).write(to: folder.appending(path: ".windows-label")) }
                let link = prefix.appending(path: "dosdevices/\(letter):", directoryHint: .notDirectory)
                try? files.removeItem(at: link)
                try files.createSymbolicLink(atPath: link.path(percentEncoded: false), withDestinationPath: "../drives/\(letter)")
                kinds += "\"\(letter):\"=\"\(drive.kind.rawValue)\"\n"
            }
            let file = prefix.appending(path: "Drives.reg", directoryHint: .notDirectory)
            try Data(kinds.utf8).write(to: file)
            defer { try? files.removeItem(at: file) }
            try await importRegistry(file)
        }
        if let registryFile = launch.registryFile { try await importRegistry(laid.appending(path: registryFile)) }
        try await waitForServer()
        try madeFromNow.write(to: Self.madeFrom(in: prefix), atomically: true, encoding: .utf8)
    }

    /// Copies a file to `destination`, or a folder's files over the folder there, replacing any of the same name.
    private static func lay(_ source: URL, over destination: URL) throws {
        let files = FileManager.default
        var isFolder: ObjCBool = false
        guard files.fileExists(atPath: source.path(percentEncoded: false), isDirectory: &isFolder) else { return }
        let pairs =
            isFolder.boolValue
            ? WineGameSave.regularFiles(in: source).map { (source.appending(path: $0), destination.appending(path: $0)) }
            : [(source, destination)]
        for (from, to) in pairs {
            try files.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? files.removeItem(at: to)
            try files.copyItem(at: from, to: to)
        }
    }

    /// Where a registry file sits on the C: drive while `reg` reads or writes it: Windows' own path for it, so
    /// nothing depends on how Wine reads a Mac's.
    private var exchange: (file: URL, windowsPath: String) {
        (prefix.appending(path: "drive_c/ludeum.reg", directoryHint: .notDirectory), "C:\\ludeum.reg")
    }

    /// Runs one of Wine's own programs in the prefix, for Ludeum's housekeeping, given `seconds` to end. One that
    /// doesn't is stopped with everything else in the prefix, so nothing of it is left waiting where I can't see it.
    private func housekeeping(_ arguments: [String], seconds: TimeInterval) async throws -> Int32 {
        let environment = wine.environment(prefix: prefix)
        do {
            return try await WineProcess.run(wine.wine, arguments, environment: environment, timeout: seconds)
        } catch is WineProcess.TimedOut {
            _ = try? await WineProcess.run(wine.wineserver, ["-k"], environment: environment, timeout: 30)
            throw WinePlayError.tookTooLong(arguments.prefix(2).joined(separator: " "), seconds: Int(seconds))
        }
    }

    /// Imports a registry file into the prefix, with `reg`: `regedit` would stop to show a mistake in a window.
    private func importRegistry(_ file: URL) async throws {
        let files = FileManager.default
        try? files.removeItem(at: exchange.file)
        try files.copyItem(at: file, to: exchange.file)
        defer { try? files.removeItem(at: exchange.file) }
        guard try await housekeeping(["reg", "import", exchange.windowsPath], seconds: 60) == 0 else {
            throw WinePlayError.couldntImportRegistry(file.lastPathComponent)
        }
    }

    /// The game's own registry keys as `reg` exports them, in one file's worth: UTF-16 with a byte-order mark, as it
    /// writes one. Nil when the launch file names none, or none of them is in the registry yet.
    private func exportRegistry() async throws -> Data? {
        let files = FileManager.default
        var exports: [String] = []
        for key in launch.registryKeys ?? [] {
            try? files.removeItem(at: exchange.file)
            // A key the game hasn't written yet is an error to `reg`, and exports nothing.
            _ = try await housekeeping(["reg", "export", key, exchange.windowsPath, "/y"], seconds: 60)
            defer { try? files.removeItem(at: exchange.file) }
            guard let data = try? Data(contentsOf: exchange.file), let text = String(data: data, encoding: .utf16) else { continue }
            exports.append(text)
        }
        try await waitForServer()
        return Self.joined(exports).map { Data([0xFF, 0xFE]) + ($0.data(using: .utf16LittleEndian) ?? Data()) }
    }

    /// Several exports as one registry file: the first whole, and the rest without the line that says what kind of file
    /// it is, a blank line between each and the next. Nil when none has a key in it.
    static func joined(_ exports: [String]) -> String? {
        let withKeys = exports.filter { $0.contains("[") }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let first = withKeys.first else { return nil }
        let rest = withKeys.dropFirst().map { export in
            export.firstIndex(of: "[").map { String(export[$0...]) } ?? export
        }
        return ([first] + rest).joined(separator: "\r\n\r\n") + "\r\n"
    }

    /// Waits until the prefix's `wineserver` has ended: it outlives the last program by a few seconds, and writes the
    /// registry as it goes.
    private func waitForServer() async throws {
        _ = try await WineProcess.run(wine.wineserver, ["-w"], environment: wine.environment(prefix: prefix))
    }
}

/// Running `wine` and `wineserver`.
enum WineProcess {
    /// It was stopped for not having ended in the time it was given.
    struct TimedOut: Error {}

    /// A process that a timer on another thread can stop.
    private final class Running: @unchecked Sendable {
        let process = Process()
        private let lock = NSLock()
        private var stopped = false

        /// Stops it if it's still going, remembering that it was.
        func stop() {
            lock.withLock {
                guard process.isRunning else { return }
                stopped = true
                process.terminate()
            }
        }

        var wasStopped: Bool { lock.withLock { stopped } }
    }

    /// Runs it to its end, without holding a thread meanwhile, and returns its exit status. What it prints goes to
    /// `output`, or nowhere. Given a `timeout`, one still going after that many seconds is stopped, and `TimedOut` thrown.
    static func run(
        _ executable: URL, _ arguments: [String], environment: [String: String], in folder: URL? = nil, output: URL? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> Int32 {
        let running = Running()
        let process = running.process
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = folder
        process.standardInput = FileHandle.nullDevice
        var handle = FileHandle.nullDevice
        if let output {
            FileManager.default.createFile(atPath: output.path(percentEncoded: false), contents: nil)
            handle = (try? FileHandle(forWritingTo: output)) ?? .nullDevice
        }
        process.standardOutput = handle
        process.standardError = handle
        defer { if output != nil { try? handle.close() } }
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
                return
            }
            if let timeout { DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { running.stop() } }
        }
        if running.wasStopped { throw TimedOut() }
        return status
    }
}
