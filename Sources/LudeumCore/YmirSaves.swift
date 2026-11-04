import Foundation

/// Ymir's Save states and Game saves, in `Emulators/Ymir/` in the Data folder (ADR 0036): Ludeum lists a Game's, by its
/// ROMs' Serials, and deletes a Save state; Ymir makes them, and loads a state with its own keys, as nothing can start it
/// from one.
///
/// A disc's states are in `Save States/<hash of the disc>/`, with a `meta.txt` beside them naming its Product Number, its
/// Serial, so Ludeum needn't work out the hash. Its backup RAM is one image of its own in `Backup Memory/games/`, named
/// `bup-int-<Title> [<Product Number>].bin`, or `bup-ext-<n>M-…` for a cartridge's.
public struct YmirSaves: Sendable {
    let states: URL
    let games: URL

    public init(ludeum: LudeumFolder = .standard) {
        self.init(states: ludeum.ymir(.saveStates), games: ludeum.ymir(.backupMemory).appending(path: "games", directoryHint: .isDirectory))
    }

    init(states: URL, games: URL) {
        self.states = states
        self.games = games
    }

    /// The keys that load a slot in Ymir, 1 to 10: `Ctrl+1` to `Ctrl+9`, and `Ctrl+0` for 10.
    public static func loadKey(slot: Int) -> String { "Ctrl+\(slot == 10 ? 0 : slot)" }

    /// The states of `serials`, by Disc in `serials`' order, then by slot. Ymir's slots are `0.savestate` to `9.savestate`, which it
    /// shows as 1 to 10. The state a slot held before it was saved over (`<n>-1.savestate`) only serves Ymir's Undo, so it
    /// isn't one of them. Every revision of a Product Number is a folder of its own.
    public func states(of serials: [String]) -> [SaveState] {
        let order = Dictionary(serials.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return Self.items(in: states).flatMap { folder -> [SaveState] in
            guard let serial = Self.productNumber(in: folder.appending(path: "meta.txt")), order[serial] != nil else { return [] }
            return (0...9).compactMap { index in
                let file = folder.appending(path: "\(index).savestate")
                return Self.modified(file).map {
                    SaveState(serial: serial, slot: .numbered(index + 1), previous: false, saved: $0, file: file)
                }
            }
        }
        .sorted { (order[$0.serial] ?? 0, $0.slot) < (order[$1.serial] ?? 0, $1.slot) }
    }

    /// Sends it to the Trash, with the state it replaced: Ymir takes a slot with only that as empty.
    public func delete(_ state: SaveState, moveToTrash: (URL) throws -> Void = Trash.move) throws {
        try moveToTrash(state.file)
        let name = state.file.deletingPathExtension().lastPathComponent
        let replaced = state.file.deletingLastPathComponent().appending(path: "\(name)-1.savestate")
        if FileManager.default.fileExists(atPath: replaced.path(percentEncoded: false)) { try moveToTrash(replaced) }
    }

    /// The backup RAM images of `serials`, internal then cartridge, each with the saves in it.
    public func backupImages(of serials: [String]) -> [SaturnBackupImage] {
        let endings = serials.map { "[\(Self.fileName($0))].bin" }
        return Self.items(in: games).filter { file in
            let name = file.lastPathComponent
            return (name.hasPrefix("bup-int-") || name.hasPrefix("bup-ext-")) && endings.contains { name.hasSuffix($0) }
        }
        .compactMap { file in
            Self.modified(file).map { saved in
                SaturnBackupImage(file: file, saved: saved, saves: (try? Data(contentsOf: file)).flatMap(SaturnBackupMemory.saves(in:)))
            }
        }
        .sorted { $0.fileName < $1.fileName }
    }

    /// A Product Number as Ymir puts one in a file's name: these characters, and any but ASCII, become `_`.
    static func fileName(_ serial: String) -> String {
        String(String.UnicodeScalarView(serial.unicodeScalars.map { ":|<>/\\*?".unicodeScalars.contains($0) || !$0.isASCII ? "_" : $0 }))
    }

    /// The Product Number a `meta.txt` gives, when it gives one.
    private static func productNumber(in meta: URL) -> String? {
        guard let data = try? Data(contentsOf: meta) else { return nil }
        let prefix = "Product Number:"
        let line = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).first { $0.hasPrefix(prefix) }
        let number = line?.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return number?.isEmpty == false ? number : nil
    }

    private static func items(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).map {
            folder.appending(path: $0)
        }
    }

    private static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.modificationDate] as? Date
    }
}

/// One image of a Game's backup RAM.
public struct SaturnBackupImage: Sendable, Equatable, Identifiable {
    public let file: URL
    /// When it was last written: its file's modification date.
    public let saved: Date
    /// The saves in it; nil when it isn't an image Ludeum can read.
    public let saves: [SaturnBackupSave]?

    public var fileName: String { file.lastPathComponent }
    public var id: String { fileName }
}

/// One save a game wrote in backup RAM, under the name it chose (`HOUSEOFDEAD`).
public struct SaturnBackupSave: Sendable, Equatable, Identifiable {
    public let name: String
    /// What the game says it is (`HOTD Data`).
    public let comment: String
    /// When the game wrote it, by the console's clock.
    public let written: Date
    /// Its size in bytes.
    public let size: Int

    public var id: String { name }
}

/// The Saturn's backup RAM format, as Ymir reads it (`BackupMemory`): an image of 32 KiB in 64-byte blocks (internal), or a
/// cartridge's 512 KiB to 2 MiB in 512-byte ones or 4 MiB in 1,024-byte ones, each possibly interleaved (`FF xx`, twice the
/// size, as a real one is wired). Block 0 is the header repeated, block 1 is zeros, and a save starts at any later block
/// whose first byte has its top bit set and whose next three are zero.
enum SaturnBackupMemory {
    private static let header = Array("BackUpRam Format".utf8)
    private static let blockSizes = [32 << 10: 64, 512 << 10: 512, 1 << 20: 512, 2 << 20: 512, 4 << 20: 1024]

    /// The saves in an image, in the order they're in it. Nil when it isn't an image: the wrong size, or no header.
    static func saves(in image: Data) -> [SaturnBackupSave]? {
        var bytes = [UInt8](image)
        if blockSizes[bytes.count] == nil, blockSizes[bytes.count / 2] != nil, bytes.count.isMultiple(of: 2),
            stride(from: 0, to: bytes.count, by: 2).allSatisfy({ bytes[$0] == 0xFF })
        {
            bytes = stride(from: 1, to: bytes.count, by: 2).map { bytes[$0] }
        }
        guard let blockSize = blockSizes[bytes.count],
            (0..<blockSize).allSatisfy({ bytes[$0] == header[$0 % header.count] }),
            (blockSize..<(blockSize * 2)).allSatisfy({ bytes[$0] == 0 })
        else { return nil }
        func long(_ at: Int) -> Int { (0..<4).reduce(0) { $0 << 8 | Int(bytes[at + $1]) } }
        return stride(from: blockSize * 2, to: bytes.count, by: blockSize).compactMap { start in
            guard bytes[start] & 0x80 != 0, bytes[(start + 1)...(start + 3)].allSatisfy({ $0 == 0 }) else { return nil }
            let size = long(start + 0x1E)
            guard size < bytes.count - blockSize * 2 else { return nil }
            return SaturnBackupSave(
                name: text(bytes[(start + 0x04)..<(start + 0x0F)]), comment: text(bytes[(start + 0x10)..<(start + 0x1A)]),
                written: date(minutes: long(start + 0x1A)), size: size)
        }
    }

    /// Text up to its first NUL: a Saturn game's is ASCII, or Shift JIS for Japanese.
    private static func text(_ bytes: ArraySlice<UInt8>) -> String {
        let data = Data(bytes.prefix { $0 != 0 })
        return (String(data: data, encoding: .shiftJIS) ?? String(decoding: data, as: UTF8.self)).trimmingCharacters(in: .whitespaces)
    }

    /// A save's date: minutes since the start of 1980, by the console's clock, so it's read as this Mac's time.
    private static func date(minutes: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 1980, month: 1, day: 1)) ?? .distantPast
        return calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
    }
}
