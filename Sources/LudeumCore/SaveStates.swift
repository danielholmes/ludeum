import Foundation
import GRDB

/// A DuckStation save state: made and managed in DuckStation, which keeps it in the Data folder, where its Standing
/// settings point it (ADR 0024), as `<serial>_<slot>.sav`.
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

/// DuckStation's save states, in `Emulators/DuckStation/Save States/` in the Data folder (ADR 0024): Ludeum lists a
/// Game's, Plays from one and deletes one; DuckStation makes them.
public struct DuckStationSaveStates: Sendable {
    public let folder: URL

    public init(ludeum: LudeumFolder = .standard) {
        self.init(folder: ludeum.duckStationSaveStates)
    }

    init(folder: URL) {
        self.folder = folder
    }

    /// The states of `serials`: by Disc in `serials`' order, then Resume, then by slot, each slot's previous one after it.
    public func states(of serials: [String]) -> [SaveState] {
        let order = Dictionary(serials.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.compactMap { name -> SaveState? in
            guard let parsed = SaveState.parse(name, serials: serials) else { return nil }
            let file = folder.appending(path: name)
            guard let saved = Self.modified(file) else { return nil }
            return SaveState(serial: parsed.serial, slot: parsed.slot, previous: parsed.previous, saved: saved, file: file)
        }
        .sorted {
            (order[$0.serial] ?? 0, $0.slot, $0.previous ? 1 : 0) < (order[$1.serial] ?? 0, $1.slot, $1.previous ? 1 : 0)
        }
    }

    /// Sends it to the Trash.
    public func delete(
        _ state: SaveState, moveToTrash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) throws {
        try moveToTrash(state.file)
    }

    private static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.modificationDate] as? Date
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
