import Foundation

/// One save inside a memory card, made by a game: a Card save.
public struct CardSave: Sendable, Equatable, Identifiable {
    /// Its name on the card, which starts with its region and its game's Serial (`BASLUS-00551…`).
    public let fileName: String
    /// As the game wrote it, its full-width letters made plain.
    public let title: String
    public let blocks: Int
    /// Its icon's frames, shown in turn: each 16 × 16, RGBA, a byte each.
    public let icon: [Data]

    public var id: String { fileName }
}

/// A PlayStation memory card as DuckStation keeps one: 128 KB, its first block a directory of the 15 after it.
public enum MemoryCard {
    static let size = 128 * 1024
    static let blockSize = 8192

    /// The Card saves in a card's file; nil when it isn't a card.
    public static func saves(of file: URL) -> [CardSave]? {
        (try? Data(contentsOf: file)).flatMap(saves(in:))
    }

    /// The Card saves in `card`, in its directory's order; nil when it isn't a card.
    static func saves(in card: Data) -> [CardSave]? {
        let card = Array(card)
        guard card.count == size, card[0] == 0x4D, card[1] == 0x43 else { return nil }
        func u16(_ offset: Int) -> Int { Int(card[offset]) | Int(card[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int { u16(offset) | u16(offset + 2) << 16 }
        var saves: [CardSave] = []
        for block in 1...15 {
            let frame = block * 128
            // Where a save starts; its other blocks, and deleted and free ones, are passed over.
            guard u32(frame) == 0x51 else { continue }
            let blocks = min(max(u32(frame + 4) / blockSize, 1), 15)
            let name = card[(frame + 0x0A)..<(frame + 0x0A + 21)].prefix { $0 != 0 }
            let start = block * blockSize
            guard card[start] == 0x53, card[start + 1] == 0x43 else { continue }
            let title = card[(start + 4)..<(start + 4 + 64)].prefix { $0 != 0 }
            let palette = (0..<16).map { u16(start + 0x60 + $0 * 2) }
            let frames = min(max(Int(card[start + 2]) - 0x10, 1), 3)
            let icon = (0..<frames).map { f in
                Data(
                    (0..<256).flatMap { pixel -> [UInt8] in
                        let byte = card[start + 128 * (1 + f) + pixel / 2]
                        return rgba(palette[Int(pixel % 2 == 0 ? byte & 0x0F : byte >> 4)])
                    })
            }
            saves.append(
                CardSave(
                    fileName: String(decoding: name, as: UTF8.self),
                    title: (String(data: Data(title), encoding: .shiftJIS) ?? "").precomposedStringWithCompatibilityMapping
                        .trimmingCharacters(in: .whitespaces),
                    blocks: blocks, icon: icon))
        }
        return saves
    }

    /// A colour of an icon's palette, 5 bits each of red, green and blue; 0 is transparent.
    private static func rgba(_ colour: Int) -> [UInt8] {
        guard colour != 0 else { return [0, 0, 0, 0] }
        func channel(_ shift: Int) -> UInt8 {
            let value = UInt8(colour >> shift & 0x1F)
            return value << 3 | value >> 2
        }
        return [channel(0), channel(5), channel(10), 0xFF]
    }
}

/// A ROM's memory card as Game detail shows it: the one DuckStation keeps for its disc.
public struct MemoryCardFile: Sendable, Equatable {
    public let file: URL
    /// When the game last saved to it.
    public let saved: Date
    /// Nil when it couldn't be read as a card.
    public let saves: [CardSave]?
}

/// Each PlayStation ROM's memory card: DuckStation names and manages it, and Ludeum only says where they're kept, in the
/// Data folder (ADR 0024). Game detail shows a ROM's by working out DuckStation's name for it.
public struct DuckStationMemoryCards: Sendable {
    let duckStation: DuckStationSettings

    public init(duckStation: DuckStationSettings = .init()) {
        self.duckStation = duckStation
    }

    /// The folder in DuckStation's app holding the game database its cards are named from.
    public static func resources(of app: URL) -> URL { app.appending(path: "Contents/Resources", directoryHint: .isDirectory) }

    /// The card DuckStation keeps for `serial`'s disc opened from `rom`; nil when it hasn't one yet, or card 1 is off.
    public func memoryCard(serial: String, rom: URL, resources: URL?) -> MemoryCardFile? {
        guard let file = duckStationsCard(serial: serial, rom: rom, resources: resources), let saved = Self.modified(file) else {
            return nil
        }
        return MemoryCardFile(file: file, saved: saved, saves: MemoryCard.saves(of: file))
    }

    /// The card DuckStation's settings give card 1 for `serial`'s disc opened from `rom`, the per-game file's over its
    /// `settings.ini`, as DuckStation names it: by its title in the game database in `resources` by default (a disc
    /// set's, unless a card of the disc's own is there already), or by its Serial, its file's name, or one shared card.
    /// Nil when card 1 is off. A title the game was given in DuckStation's game list isn't looked for. `perGame` stands
    /// in for the per-game file's text.
    func duckStationsCard(serial: String, rom: URL, resources: URL?, perGame: String? = nil) -> URL? {
        let base = (try? String(contentsOf: duckStation.settingsFile, encoding: .utf8)) ?? ""
        let perGame = perGame ?? (try? String(contentsOf: duckStation.gameSettingsFile(serial), encoding: .utf8)) ?? ""
        func setting(_ key: String) -> String? {
            Ini.value(key, in: "MemoryCards", of: perGame) ?? Ini.value(key, in: "MemoryCards", of: base)
        }
        let cards = duckStation.folder("Directory", in: "MemoryCards", default: "memcards")
        func card(_ name: String) -> URL { cards.appending(path: Self.sanitised(name) + "_1.mcd") }
        let fileTitle = rom.deletingPathExtension().lastPathComponent
        switch setting("Card1Type") ?? "PerGameTitle" {
        case "PerGame": return card(serial)
        case "PerGameFileTitle": return card(fileTitle)
        case "Shared":
            let path = setting("Card1Path") ?? ""
            if path.isEmpty { return cards.appending(path: "shared_card_1.mcd") }
            return path.hasPrefix("/") ? URL(filePath: path) : cards.appending(path: path)
        case "PerGameTitle":
            let database = resources.map(GameDatabase.init)
            guard let title = database?.saveTitle(of: serial) else { return card(fileTitle) }
            let disc = card(title)
            guard let set = database?.discSetSaveTitle(of: serial), card(set) != disc else { return disc }
            let usesSet = setting("UsePlaylistTitle").map(Ini.isTrue) ?? true
            return usesSet && !Self.exists(disc) ? card(set) : disc
        default: return nil
        }
    }

    /// A name as DuckStation makes it safe for a file on macOS: control characters, `/`, `*` and `:` become `_`.
    static func sanitised(_ name: String) -> String {
        String(name.unicodeScalars.map { $0.value < 32 || "/*:".unicodeScalars.contains($0) ? "_" : Character($0) })
    }

    private static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    private static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.modificationDate] as? Date
    }
}

/// The game database bundled in DuckStation's app, read only for the titles it names cards by.
struct GameDatabase {
    /// The folder in DuckStation's app holding `discdb.yaml` and `discsets.yaml`.
    let resources: URL

    /// A disc's `saveName`, else its `name`; nil for a disc it doesn't know.
    func saveTitle(of serial: String) -> String? {
        guard let text = try? String(contentsOf: resources.appending(path: "discdb.yaml"), encoding: .utf8),
            let found = text.range(of: "\n\(serial):\n") ?? (text.hasPrefix("\(serial):\n") ? text.range(of: "\(serial):\n") : nil)
        else { return nil }
        // Its fields, up to the next disc's.
        var fields: [String: String] = [:]
        for line in text[found.upperBound...].split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix(" ") else { break }
            if let (key, value) = Self.field(line, indent: "  ") { fields[key] = value }
        }
        return fields["saveName"].flatMap { $0.isEmpty ? nil : $0 } ?? fields["name"]
    }

    /// The `saveName`, else the `name`, of the disc set `serial` is one of; nil when it's in none.
    func discSetSaveTitle(of serial: String) -> String? {
        guard let text = try? String(contentsOf: resources.appending(path: "discsets.yaml"), encoding: .utf8) else { return nil }
        // Each set starts `- name: …`, its other fields indented under it.
        var sets: [[Substring]] = []
        for line in text.split(separator: "\n") {
            if line.hasPrefix("- ") {
                sets.append([Substring("  " + line.dropFirst(2))])
            } else if !sets.isEmpty {
                sets[sets.count - 1].append(line)
            }
        }
        for lines in sets where lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "- \(serial)" }) {
            let fields = Dictionary(lines.compactMap { Self.field($0, indent: "  ") }, uniquingKeysWith: { first, _ in first })
            return fields["saveName"].flatMap { $0.isEmpty ? nil : $0 } ?? fields["name"]
        }
        return nil
    }

    /// `key: "value"` at exactly `indent`, its quotes taken off.
    private static func field(_ line: Substring, indent: String) -> (String, String)? {
        guard line.hasPrefix(indent), !line.dropFirst(indent.count).hasPrefix(" "),
            let colon = line.firstIndex(of: ":")
        else { return nil }
        let key = line[line.index(line.startIndex, offsetBy: indent.count)..<colon].trimmingCharacters(in: .whitespaces)
        var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return (key, value)
    }
}
