import Foundation

/// PCSX2's Save states, in the Data folder where its Standing settings keep them (ADR 0032): `<serial> (<CRC>).<nn>.p2s`
/// for a slot, `.resume.p2s` for the Resume state it saves on closing, and `.<nn>.p2s.backup` for what a slot held before
/// it was saved over. The serial is the disc's (its `SYSTEM.CNF`'s `BOOT2` line) and the CRC its boot executable's, so
/// a Game's states follow its ROM through Rename, Archive and a change of image form, and are found by its Serials
/// alone.
public struct PCSX2SaveStates: Sendable {
    public let folder: URL

    public init(ludeum: LudeumFolder = .standard) {
        self.init(folder: ludeum.pcsx2SaveStates)
    }

    init(folder: URL) {
        self.folder = folder
    }

    /// The states of `serials`: by Disc in `serials`' order, then Resume, then by slot, each slot's previous one after it.
    public func states(of serials: [String]) -> [SaveState] {
        let order = Dictionary(serials.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.compactMap { name -> SaveState? in
            guard let parsed = Self.parse(name, serials: serials) else { return nil }
            let file = folder.appending(path: name)
            guard let saved = Self.modified(file) else { return nil }
            return SaveState(serial: parsed.serial, slot: parsed.slot, previous: parsed.previous, saved: saved, file: file)
        }
        .sorted {
            (order[$0.serial] ?? 0, $0.slot, $0.previous ? 1 : 0) < (order[$1.serial] ?? 0, $1.slot, $1.previous ? 1 : 0)
        }
    }

    /// Its serial, slot and whether it's the previous one, from a file name of one of `serials`; nil for any other file.
    static func parse(_ fileName: String, serials: some Collection<String>) -> (serial: String, slot: SaveState.Slot, previous: Bool)? {
        // The longest, should one serial begin another's name.
        for serial in serials.sorted(by: { $0.count > $1.count }) where fileName.hasPrefix(serial + " (") {
            let rest = fileName.dropFirst(serial.count + 2)
            // The CRC: eight hex digits, then `)`.
            guard rest.count > 9, rest.prefix(8).allSatisfy(\.isHexDigit), rest.dropFirst(8).first == ")" else { continue }
            let suffix = rest.dropFirst(9)
            if suffix == ".resume.p2s" { return (serial, .resume, false) }
            let previous = suffix.hasSuffix(".p2s.backup")
            guard suffix.hasPrefix("."), suffix.hasSuffix(previous ? ".p2s.backup" : ".p2s") else { continue }
            let number = suffix.dropFirst().dropLast(previous ? 11 : 4)
            guard number.count == 2, let n = Int(number) else { continue }
            return (serial, .numbered(n), previous)
        }
        return nil
    }

    /// Sends it to the Trash.
    public func delete(_ state: SaveState, moveToTrash: (URL) throws -> Void = Trash.move) throws {
        try moveToTrash(state.file)
    }

    private static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.modificationDate] as? Date
    }

    /// The state's screenshot, the PNG PCSX2 keeps in it (`Screenshot.png` in the zip a state is, the frame scaled to
    /// fit 640 × 480); nil when it has none or can't be read.
    public static func screenshotPNG(of file: URL) -> Data? {
        Zip.entry(named: "Screenshot.png", in: file)
    }
}

/// Reading one file out of a zip, as PCSX2 writes a state: by its central directory, stored or deflated.
enum Zip {
    /// The contents of the entry named `name`, or nil when the zip has none, or can't be read.
    static func entry(named name: String, in file: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size >= 22 else { return nil }
        // The end of central directory record, within the last 64 KB (its comment at most that long).
        let tailStart = size > 66_000 ? size - 66_000 : 0
        guard (try? handle.seek(toOffset: tailStart)) != nil, let tail = try? handle.readToEnd() else { return nil }
        guard let end = tail.lastRange(of: Data([0x50, 0x4B, 0x05, 0x06]))?.lowerBound, tail.endIndex - end >= 22 else { return nil }
        func u16(_ data: Data, _ offset: Int) -> Int { Int(data[data.startIndex + offset]) | Int(data[data.startIndex + offset + 1]) << 8 }
        func u32(_ data: Data, _ offset: Int) -> Int { u16(data, offset) | u16(data, offset + 2) << 16 }
        let record = end - tail.startIndex
        let entries = u16(tail, record + 10)
        let directorySize = u32(tail, record + 12)
        let directoryOffset = u32(tail, record + 16)
        guard (try? handle.seek(toOffset: UInt64(directoryOffset))) != nil, let directory = try? handle.read(upToCount: directorySize),
            directory.count == directorySize
        else { return nil }
        var at = 0
        for _ in 0..<entries {
            guard at + 46 <= directory.count, u32(directory, at) == 0x0201_4B50 else { return nil }
            let method = u16(directory, at + 10)
            let compressed = u32(directory, at + 20)
            let uncompressed = u32(directory, at + 24)
            let nameLength = u16(directory, at + 28)
            let extraLength = u16(directory, at + 30)
            let commentLength = u16(directory, at + 32)
            let localOffset = u32(directory, at + 42)
            guard at + 46 + nameLength <= directory.count else { return nil }
            let nameStart = directory.startIndex + at + 46
            let entryName = String(decoding: directory[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            at += 46 + nameLength + extraLength + commentLength
            guard entryName == name else { continue }
            // The local header: its own name and extra lengths, then the data.
            guard (try? handle.seek(toOffset: UInt64(localOffset))) != nil, let local = try? handle.read(upToCount: 30), local.count == 30,
                u32(local, 0) == 0x0403_4B50
            else { return nil }
            let dataOffset = localOffset + 30 + u16(local, 26) + u16(local, 28)
            guard (try? handle.seek(toOffset: UInt64(dataOffset))) != nil, let data = try? handle.read(upToCount: compressed),
                data.count == compressed
            else { return nil }
            switch method {
            case 0: return data
            case 8:
                guard let inflated = try? (data as NSData).decompressed(using: .zlib) as Data, inflated.count == uncompressed else {
                    return nil
                }
                return inflated
            default: return nil
            }
        }
        return nil
    }
}

/// One save on a PCSX2 folder memory card: the subfolder the game made, named as the game named it (its serial in the
/// name, `BASLUS-20062…`), with the title in its `icon.sys`.
public struct PS2CardSave: Sendable, Equatable, Identifiable {
    /// The card it's on, by the card's name (`Mcd001.ps2`).
    public let card: String
    /// The save's folder name, as the game named it.
    public let name: String
    /// Its title as the game wrote it into `icon.sys`, in plain characters; nil when there's no `icon.sys` to read.
    public let title: String?
    /// When it was last written.
    public let saved: Date
    public let folder: URL

    public var id: String { "\(card)/\(name)" }
}

/// PCSX2's memory cards, in the Data folder where its Standing settings keep them (ADR 0032). A folder card (a
/// directory) holds one subfolder per save, so a Game's Card saves are the subfolders whose names carry one of its
/// serials, or one of the serials PCSX2's game database says share its saves; a file card (`Mcd001.ps2` as one 8 MB
/// file) holds every game's in one and isn't read.
public struct PCSX2MemoryCards: Sendable {
    public let folder: URL
    /// The folder in PCSX2's app holding `GameIndex.yaml`.
    let resources: URL?

    public init(ludeum: LudeumFolder = .standard) {
        self.init(
            folder: ludeum.pcsx2MemoryCards, resources: ludeum.pcsx2App.appending(path: "Contents/Resources", directoryHint: .isDirectory))
    }

    init(folder: URL, resources: URL?) {
        self.folder = folder
        self.resources = resources
    }

    /// The Card saves of a Game with `serials`, on every folder card, by card then by name.
    public func saves(of serials: [String]) -> [PS2CardSave] {
        let terms = Self.filters(for: serials, in: resources)
        guard !terms.isEmpty else { return [] }
        let files = FileManager.default
        let cards = ((try? files.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).sorted()
            .filter { !$0.hasPrefix(".") && Self.isDirectory(folder.appending(path: $0, directoryHint: .isDirectory)) }
        return cards.flatMap { card -> [PS2CardSave] in
            let cardFolder = folder.appending(path: card, directoryHint: .isDirectory)
            let names = ((try? files.contentsOfDirectory(atPath: cardFolder.path(percentEncoded: false))) ?? []).sorted()
            return names.compactMap { name -> PS2CardSave? in
                guard !name.hasPrefix("."), !name.hasPrefix("_pcsx2_"), terms.contains(where: { name.contains($0) }) else { return nil }
                let save = cardFolder.appending(path: name, directoryHint: .isDirectory)
                guard Self.isDirectory(save) else { return nil }
                let index = save.appending(path: "_pcsx2_index")
                guard let saved = Self.modified(index) ?? Self.modified(save) else { return nil }
                return PS2CardSave(
                    card: card, name: name, title: IconSys.title(of: save.appending(path: "icon.sys")), saved: saved, folder: save)
            }
        }
    }

    /// What a save's name must carry to be one of a Game's: its serials, and for each the serials PCSX2's game database
    /// lists with it (`memcardFilters`, for discs that share saves), as PCSX2 filters a running game's card.
    static func filters(for serials: [String], in resources: URL?) -> [String] {
        var terms: [String] = []
        for serial in serials {
            for term in [serial] + (resources.map { PS2GameIndex(resources: $0).memcardFilters(of: serial) } ?? [])
            where !terms.contains(term) {
                terms.append(term)
            }
        }
        return terms
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.modificationDate] as? Date
    }
}

/// A PlayStation 2 save's `icon.sys`: the title the game gave the save, 68 bytes of Shift JIS at offset 0xC0, in two
/// lines, the second starting at the byte offset the 16-bit value at 0x06 says.
enum IconSys {
    static func title(of file: URL) -> String? {
        guard let data = try? Data(contentsOf: file), data.count >= 0xC0 + 68, data.prefix(4) == Data("PS2D".utf8) else { return nil }
        return title(in: data)
    }

    static func title(in data: Data) -> String? {
        let lineBreak = Int(data[data.startIndex + 6]) | Int(data[data.startIndex + 7]) << 8
        let bytes = Data(data[(data.startIndex + 0xC0)..<(data.startIndex + 0xC0 + 68)])
        let end = bytes.firstIndex(of: 0) ?? bytes.count
        let first = bytes[0..<min(lineBreak, end)]
        let second = lineBreak < end ? bytes[lineBreak..<end] : Data()
        let lines = [first, second].compactMap { line -> String? in
            guard !line.isEmpty, let text = String(data: Data(line), encoding: .shiftJIS) else { return nil }
            let plain = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
            let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }
}

/// PCSX2's game database, `GameIndex.yaml` in its app, keyed by serial.
struct PS2GameIndex {
    let resources: URL

    /// The serials the database says share `serial`'s saves (its `memcardFilters`), itself among them; none when it has
    /// no entry or no filters.
    func memcardFilters(of serial: String) -> [String] {
        guard let text = try? String(contentsOf: resources.appending(path: "GameIndex.yaml"), encoding: .utf8),
            let found = text.range(of: "\n\(serial):\n") ?? (text.hasPrefix("\(serial):\n") ? text.range(of: "\(serial):\n") : nil)
        else { return [] }
        var filters: [String] = []
        var inFilters = false
        for line in text[found.upperBound...].split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix(" ") else { break }
            if line.hasPrefix("  memcardFilters:") {
                inFilters = true
            } else if inFilters, line.hasPrefix("    - ") {
                var value = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                if let comment = value.range(of: " #") { value = String(value[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces) }
                if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
                if !value.isEmpty { filters.append(value) }
            } else if inFilters, !line.hasPrefix("    ") {
                break
            }
        }
        return filters
    }
}
