import Foundation
import GRDB

/// A DuckStation save state (ADR 0022): made and managed in DuckStation, which keeps it in its own folder as
/// `<serial>_<slot>.sav`, and backed up into the Data folder under the same name.
public struct SaveState: Sendable, Equatable, Identifiable {
    public enum Slot: Sendable, Hashable, Comparable {
        /// The one DuckStation saves on closing the game.
        case resume
        case numbered(Int)
    }

    public let serial: String
    public let slot: Slot
    /// What the slot held before it was saved over, which DuckStation keeps as `.bak`.
    public let previous: Bool
    /// When it was saved: its file's modification date, as DuckStation shows it.
    public let saved: Date
    /// DuckStation's folder has it; else only the backup does, after it was deleted there.
    public let inDuckStation: Bool
    /// The backup has it as DuckStation has it (always, when DuckStation hasn't).
    public let backedUp: Bool
    /// The file to Play and read: DuckStation's, else the backup's.
    public let file: URL

    public var fileName: String { file.lastPathComponent }
    public var id: String { fileName }

    /// "Resume", "Slot 3", "Slot 3 (previous)".
    public var title: String {
        let name =
            switch slot {
            case .resume: "Resume"
            case .numbered(let n): "Slot \(n)"
            }
        return previous ? "\(name) (previous)" : name
    }

    /// Its serial, slot and whether it's the previous one, from a file name of one of `serials`; nil for any other file.
    static func parse(_ fileName: String, serials: some Collection<String>) -> (serial: String, slot: Slot, previous: Bool)? {
        let ext = (fileName as NSString).pathExtension
        guard ext == "sav" || ext == "bak" else { return nil }
        let stem = (fileName as NSString).deletingPathExtension
        // The longest, should one serial begin another's name.
        for serial in serials.sorted(by: { $0.count > $1.count }) where stem.hasPrefix(serial + "_") {
            let rest = stem.dropFirst(serial.count + 1)
            if rest == "resume" { return (serial, .resume, ext == "bak") }
            if let n = Int(rest), n > 0, String(n) == rest { return (serial, .numbered(n), ext == "bak") }
        }
        return nil
    }
}

/// The screenshot a save state was saved with: RGBA, a byte each.
public struct SaveStateScreenshot: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let rgba: Data
}

/// DuckStation's save states, kept where DuckStation keeps them, with a backup of each in the Data folder (ADR 0022).
/// DuckStation's folder is set only in its own settings, which no per-game file can change, so the states stay there;
/// Ludeum copies them, and never deletes a backup because DuckStation's is gone.
public struct DuckStationSaveStates: Sendable {
    /// DuckStation's own folder: its settings' `[Folders] SaveStates`, else `savestates`.
    public let folder: URL
    /// `Emulators/DuckStation/Save States/` in the Data folder.
    public let backup: URL
    /// The Data folder: nothing's backed up while it's missing, so no backup is made somewhere Dropbox doesn't see.
    let data: URL

    public init(ludeum: LudeumFolder = .standard, duckStation: DuckStationSettings = .init()) {
        self.init(folder: duckStation.folder("SaveStates", default: "savestates"), backup: ludeum.duckStationSaveStates, data: ludeum.data)
    }

    init(folder: URL, backup: URL, data: URL) {
        self.folder = folder
        self.backup = backup
        self.data = data
    }

    /// Copies each state of `serials` the backup hasn't got as DuckStation has it. True if any was copied.
    @discardableResult
    public func backUp(_ serials: Set<String>) throws -> Bool {
        guard !serials.isEmpty, isDirectory(data) else { return false }
        var copied = false
        for name in names(in: folder, of: serials) {
            let source = folder.appending(path: name)
            let copy = backup.appending(path: name)
            guard !Self.same(source, copy) else { continue }
            try FileManager.default.copyIntoDataFolder(source, over: copy)
            copied = true
        }
        return copied
    }

    /// The states of `serials`, in DuckStation's folder or only in the backup: by Disc in `serials`' order, then Resume,
    /// then by slot, each slot's previous one after it.
    public func states(of serials: [String]) -> [SaveState] {
        let order = Dictionary(serials.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let names = Set(names(in: folder, of: Set(serials))).union(names(in: backup, of: Set(serials)))
        return names.compactMap { name -> SaveState? in
            guard let parsed = SaveState.parse(name, serials: serials) else { return nil }
            let live = folder.appending(path: name)
            let copy = backup.appending(path: name)
            let inDuckStation = Self.exists(live)
            let file = inDuckStation ? live : copy
            guard let saved = Self.modified(file) else { return nil }
            return SaveState(
                serial: parsed.serial, slot: parsed.slot, previous: parsed.previous, saved: saved, inDuckStation: inDuckStation,
                backedUp: !inDuckStation || Self.same(live, copy), file: file)
        }
        .sorted {
            (order[$0.serial] ?? 0, $0.slot, $0.previous ? 1 : 0) < (order[$1.serial] ?? 0, $1.slot, $1.previous ? 1 : 0)
        }
    }

    /// Sends it to the Trash from DuckStation's folder and from the backup.
    public func delete(
        _ state: SaveState, moveToTrash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) throws {
        for file in [folder.appending(path: state.fileName), backup.appending(path: state.fileName)] where Self.exists(file) {
            try moveToTrash(file)
        }
    }

    /// Copies the backup back into DuckStation's folder, where DuckStation's menus see it again.
    public func restore(_ state: SaveState) throws {
        try FileManager.default.copyIntoDataFolder(backup.appending(path: state.fileName), over: folder.appending(path: state.fileName))
    }

    /// The names of `serials`' states in `folder`.
    private func names(in folder: URL, of serials: Set<String>) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.filter { SaveState.parse($0, serials: serials) != nil }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    private static func attributes(_ url: URL) -> (size: Int64, modified: Date)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
            let size = (attributes[.size] as? NSNumber)?.int64Value, let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return (size, modified)
    }

    private static func modified(_ url: URL) -> Date? { attributes(url)?.modified }

    /// The same size, saved within a second of each other: the copy is what DuckStation has.
    private static func same(_ a: URL, _ b: URL) -> Bool {
        guard let a = attributes(a), let b = attributes(b) else { return false }
        return a.size == b.size && abs(a.modified.timeIntervalSince(b.modified)) < 1
    }

}

extension FileManager {
    /// Copies `source` over `destination` in one step, keeping when it was saved: it's written beside it under a hidden
    /// name, then renamed into place, so Dropbox never sees half of it.
    func copyIntoDataFolder(_ source: URL, over destination: URL) throws {
        let folder = destination.deletingLastPathComponent()
        try createDirectory(at: folder, withIntermediateDirectories: true)
        let partial = folder.appending(path: ".\(destination.lastPathComponent).copying")
        try? removeItem(at: partial)
        try copyItem(at: source, to: partial)
        if let modified = (try? attributesOfItem(atPath: source.path(percentEncoded: false)))?[.modificationDate] as? Date {
            try setAttributes([.modificationDate: modified], ofItemAtPath: partial.path(percentEncoded: false))
        }
        guard rename(partial.path(percentEncoded: false), destination.path(percentEncoded: false)) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            try? removeItem(at: partial)
            throw error
        }
    }
}

extension DuckStationSaveStates {
    /// The state's screenshot, read from its header; nil when it has none, or it can't be read: a state from before
    /// DuckStation compressed them (version 69), or a Zstandard one without `zstd`.
    public static func screenshot(of file: URL, zstd: Zstd? = .find()) -> SaveStateScreenshot? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 216), header.count == 216 else { return nil }
        func u32(_ offset: Int) -> Int {
            Int(header[offset..<offset + 4].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        }
        // "DUCC", and the screenshot fields as they've been since version 69.
        guard u32(0) == 0x4343_5544, u32(4) >= 69 else { return nil }
        let (compression, width, height, size, offset) = (u32(180), u32(184), u32(188), u32(192), u32(196))
        guard (1...4096).contains(width), (1...4096).contains(height), size > 0, size <= 64 << 20,
            (try? handle.seek(toOffset: UInt64(offset))) != nil, let packed = try? handle.read(upToCount: size), packed.count == size
        else { return nil }
        let rgba: Data?
        switch compression {
        case 0: rgba = packed
        // zlib's: its 2-byte header, then deflate.
        case 1: rgba = packed.count > 2 ? try? (packed.dropFirst(2) as NSData).decompressed(using: .zlib) as Data : nil
        case 2: rgba = zstd?.decompress(packed)
        case 3: rgba = try? (packed as NSData).decompressed(using: .lzma) as Data
        default: rgba = nil
        }
        guard let rgba, rgba.count == width * height * 4 else { return nil }
        return SaveStateScreenshot(width: width, height: height, rgba: rgba)
    }
}

/// Zstandard's command line, `zstd` (Homebrew's `zstd`), which DuckStation compresses save states with by default.
/// Ludeum doesn't bundle it.
public struct Zstd: Sendable {
    let executable: URL

    /// `zstd` where Homebrew puts it, if it's installed.
    public static func find() -> Zstd? {
        ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd"].first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { Zstd(executable: URL(filePath: $0)) }
    }

    /// `data` decompressed; nil if it isn't Zstandard.
    func decompress(_ data: Data) -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-dcq"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // Written while the output is read, so neither pipe fills and stops the other.
        let writer = input.fileHandleForWriting
        DispatchQueue.global().async {
            try? writer.write(contentsOf: data)
            try? writer.close()
        }
        let out = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? out : nil
    }
}

extension LudeumStore {
    /// The Serials of every Game's ROMs: the ones whose save states are backed up.
    public func gameSerials() throws -> Set<String> {
        try db.read { db in
            let rows = try String.fetchAll(
                db, sql: "SELECT serials FROM rom WHERE gameId IS NOT NULL AND serialsLookedUp AND serials IS NOT NULL")
            return Set(rows.flatMap { text in (try? JSONDecoder().decode([String?].self, from: Data(text.utf8)))?.compactMap { $0 } ?? [] })
        }
    }
}
