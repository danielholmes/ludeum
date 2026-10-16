import Foundation
import GRDB

/// The LaunchBox Games Database: retail box scans for nearly every Platform, Windows and the ones libretro-thumbnails has
/// no repo for among them. The whole database is one dump, `Metadata.zip` (about 110 MB, 575 MB unzipped), made daily.
/// It's read at most every 30 days, by the launch refresh, downloaded to a file and streamed out of the zip without
/// unpacking it, and only what finds a Game's images is kept, in the cache: each game on a Platform `platforms` maps, with
/// its year, names and their title keys, and its Box - Front and Screenshot images (about 73 MB). Images come from
/// `images.launchbox-app.com` by file name, downloaded the first time one's shown.
public final class LaunchBoxGamesDB: Sendable {
    let cache: CacheStore
    let transport: HTTPTransport

    /// How long a dump is kept before the launch refresh reads LaunchBox's again.
    static let maxAge: TimeInterval = 30 * 86_400
    /// How long after a dump couldn't be downloaded or read before it's tried again, rather than at every launch.
    static let retryAfter: TimeInterval = 86_400
    static let dumpURL = URL(string: "https://gamesdb.launchbox-app.com/Metadata.zip")!
    /// The cache entry whose `fetched_at` says when the dump was last read. Its number goes up whenever what's kept of a
    /// dump changes, so the next launch reads it again rather than wait for it to be 30 days old.
    static let readKey = "launchbox:metadata:2"
    /// The cache entry whose `fetched_at` says when a dump last couldn't be downloaded or read.
    static let failedKey = "launchbox:failed"

    public init(cache: CacheStore, transport: HTTPTransport = URLSessionTransport()) {
        self.cache = cache
        self.transport = transport
    }

    /// True when no dump has been read, or the last was read more than 30 days ago, unless one couldn't be downloaded or
    /// read in the last day.
    public func isStale() throws -> Bool {
        let entries = try cache.entries([Self.readKey, Self.failedKey])
        let now = cache.clock.now()
        if let failed = entries[Self.failedKey], now.timeIntervalSince(failed.fetchedAt) < Self.retryAfter { return false }
        guard let read = entries[Self.readKey] else { return true }
        return now.timeIntervalSince(read.fetchedAt) > Self.maxAge
    }

    /// Downloads the dump and replaces what's kept of the last one. One that can't be downloaded or read throws and
    /// leaves the last one in place, to be tried again a day later.
    public func refresh() async throws {
        let zip = FileManager.default.temporaryDirectory.appending(path: "ludeum-launchbox-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: zip) }
        do {
            let response = try await transport.download(URLRequest(url: Self.dumpURL), to: zip)
            guard response.statusCode == 200 else { throw HTTPStatusError(status: response.statusCode, url: Self.dumpURL) }
            try cache.replaceLaunchBox(try LaunchBoxDump.read(zip: zip))
        } catch {
            try? cache.store([Self.failedKey: Data()])
            throw error
        }
    }

    /// The file name of a game's Box - Front, matched by title on the Platform as libretro's are (`LibretroLookup`), each
    /// of `titles` in turn, by title key, then by loose title key. Of several, a game's own name beats another's
    /// alternate name, then the game released in `year` is preferred (one of another year still matches), then the box
    /// for `regions`, else North America's, the World's,
    /// one with no region, Europe's, Japan's; then the shortest name, then the first in the dump. Nil when nothing
    /// matches, before any dump has been read, or for a Platform LaunchBox has none for.
    public func boxart(platform: Int64, titles: [String], regions: Set<NameRegion>, year: Int?) throws -> String? {
        guard let platforms = Self.platforms[platform] else { return nil }
        let regionOrder = Self.regionOrder(regions)
        let boxes = try images(of: [.boxFront], platforms: platforms, titles: titles)
        return boxes.min { a, b in
            func rank(_ box: LaunchBoxImage) -> (Int, Int, Int, Int, Int) {
                (
                    box.own ? 0 : 1, year == nil || box.year == year ? 0 : 1,
                    regionOrder.firstIndex { $0.contains(box.region) } ?? regionOrder.count, box.nameLength, box.position
                )
            }
            return rank(a) < rank(b)
        }?.fileName
    }

    /// The file names of a game's Screenshots, title screens first, all of the one game matched by title as for its Box
    /// art: its own name beats another's alternate name, then the game released in `year` is preferred, then the
    /// shortest name, then the lowest LaunchBox id. Empty when nothing matches.
    public func screenshots(platform: Int64, titles: [String], year: Int?) throws -> [String] {
        guard let platforms = Self.platforms[platform] else { return [] }
        let shots = try images(of: LaunchBoxImageType.screenshots, platforms: platforms, titles: titles)
        func rank(_ shot: LaunchBoxImage) -> (Int, Int, Int, Int) {
            (shot.own ? 0 : 1, year == nil || shot.year == year ? 0 : 1, shot.nameLength, shot.gameID)
        }
        guard let best = shots.min(by: { rank($0) < rank($1) }) else { return [] }
        var seen: Set<String> = []
        return shots.filter { $0.gameID == best.gameID && seen.insert($0.fileName).inserted }
            .sorted { ($0.type.rawValue, $0.position) < ($1.type.rawValue, $1.position) }
            .map(\.fileName)
    }

    /// Every image of `types` of the games on `platforms` that the first title to match any finds: each of `titles` in
    /// turn (then spelled out), by title key, then by loose title key, as libretro's are matched.
    private func images(of types: [LaunchBoxImageType], platforms: [String], titles: [String]) throws -> [LaunchBoxImage] {
        let spelled = titles.map(LibretroLookup.spelledOut).filter { !titles.contains($0) }
        for tier in TitleKey.allCases {
            for title in titles + spelled {
                let key = tier.of(title)
                guard !key.isEmpty else { continue }
                let found = try cache.launchBoxImages(types, tier, key, platforms: platforms)
                if !found.isEmpty { return found }
            }
        }
        return []
    }

    /// An image by its file name, from the cache or downloaded the first time.
    public func image(_ fileName: String) async throws -> URL {
        try await cache.image(at: "launchbox/\(fileName)") {
            let url = URL(string: "https://images.launchbox-app.com")!.appending(path: fileName)
            let (data, response) = try await transport.send(URLRequest(url: url))
            guard response.statusCode == 200 else { throw HTTPStatusError(status: response.statusCode, url: url) }
            return data
        }
    }

    /// The regions a box can be for, best first: `own`'s, then North America's, the World's, none, Europe's, Japan's,
    /// Korea's. LaunchBox names countries as well as regions; a European country counts as Europe, as do Australia and
    /// Oceania, which get PAL releases.
    static func regionOrder(_ own: Set<NameRegion>) -> [Set<String?>] {
        let preferred: [NameRegion] = [.usa, .europe, .japan, .korea]
        func names(_ region: NameRegion) -> Set<String?> {
            switch region {
            case .usa: ["North America", "United States", "Canada"]
            case .europe:
                [
                    "Europe", "United Kingdom", "Germany", "France", "Spain", "Italy", "The Netherlands", "Sweden",
                    "Finland", "Norway", "Greece", "Russia", "Australia", "Oceania",
                ]
            case .japan: ["Japan"]
            case .korea: ["Korea"]
            }
        }
        return preferred.filter(own.contains).map(names)
            + [names(.usa), ["World"], [nil], names(.europe), names(.japan), names(.korea)]
    }

    /// LaunchBox's platforms for each IGDB platform it has games for. IGDB splits some it doesn't (the Famicom and NES,
    /// the Super Famicom and SNES, the DSi and DS, the New 3DS and 3DS), and LaunchBox splits some IGDB doesn't
    /// (Windows 3.x, MSX2+, PSP minis).
    static let platforms: [Int64: [String]] = [
        3: ["Linux"], 4: ["Nintendo 64"], 5: ["Nintendo Wii"], 6: ["Windows", "Windows 3.X"], 7: ["Sony Playstation"],
        8: ["Sony Playstation 2"], 9: ["Sony Playstation 3"], 11: ["Microsoft Xbox"], 12: ["Microsoft Xbox 360"],
        13: ["MS-DOS"], 14: ["Apple Mac OS"], 15: ["Commodore 64", "Commodore 128", "Commodore MAX Machine"],
        16: ["Commodore Amiga"], 18: ["Nintendo Entertainment System"], 19: ["Super Nintendo Entertainment System"],
        20: ["Nintendo DS"], 21: ["Nintendo GameCube"], 22: ["Nintendo Game Boy Color"], 23: ["Sega Dreamcast"],
        24: ["Nintendo Game Boy Advance"], 25: ["Amstrad CPC"], 26: ["Sinclair ZX Spectrum"], 27: ["Microsoft MSX"],
        29: ["Sega Genesis"], 30: ["Sega 32X"], 32: ["Sega Saturn"], 33: ["Nintendo Game Boy"], 34: ["Android"],
        35: ["Sega Game Gear"], 37: ["Nintendo 3DS"], 38: ["Sony PSP", "Sony PSP Minis"], 39: ["Apple iOS"],
        41: ["Nintendo Wii U"], 42: ["Nokia N-Gage"], 44: ["Tapwave Zodiac"], 46: ["Sony Playstation Vita"],
        48: ["Sony Playstation 4"], 49: ["Microsoft Xbox One"], 50: ["3DO Interactive Multiplayer"],
        51: ["Nintendo Famicom Disk System"], 52: ["Arcade"], 53: ["Microsoft MSX2", "Microsoft MSX2+"], 57: ["WonderSwan"],
        58: ["Super Nintendo Entertainment System"], 59: ["Atari 2600"], 60: ["Atari 7800"], 61: ["Atari Lynx"],
        62: ["Atari Jaguar"], 63: ["Atari ST"], 64: ["Sega Master System"], 65: ["Atari 800", "Atari XEGS"],
        66: ["Atari 5200"], 67: ["Mattel Intellivision"], 68: ["ColecoVision"], 69: ["BBC Microcomputer System"],
        70: ["GCE Vectrex"], 71: ["Commodore VIC-20"], 72: ["Ouya"], 75: ["Apple II"], 77: ["Sharp X1"], 78: ["Sega CD"],
        79: ["SNK Neo Geo MVS"], 80: ["SNK Neo Geo AES"], 82: ["Web Browser"], 84: ["Sega SG-1000"],
        86: ["NEC TurboGrafx-16"], 87: ["Nintendo Virtual Boy"], 88: ["Magnavox Odyssey"], 90: ["Commodore PET"],
        91: ["Bally Astrocade"], 94: ["Commodore Plus 4"], 99: ["Nintendo Entertainment System"],
        114: ["Commodore Amiga CD32"], 115: ["Apple IIGS"], 116: ["Acorn Archimedes"], 117: ["Philips CD-i"],
        118: ["Fujitsu FM Towns Marty"], 119: ["SNK Neo Geo Pocket"], 120: ["SNK Neo Geo Pocket Color"],
        121: ["Sharp X68000"], 122: ["Nuon"], 123: ["WonderSwan Color"], 125: ["NEC PC-8801"], 126: ["Tandy TRS-80"],
        127: ["Fairchild Channel F"], 128: ["PC Engine SuperGrafx"], 129: ["Texas Instruments TI 99/4A"],
        130: ["Nintendo Switch"], 133: ["Magnavox Odyssey 2"], 134: ["Acorn Electron"], 136: ["SNK Neo Geo CD"],
        137: ["Nintendo 3DS"], 138: ["Interton VC 4000"], 149: ["NEC PC-9801"], 150: ["NEC TurboGrafx-CD"],
        151: ["TRS-80 Color Computer"], 152: ["Fujitsu FM-7"], 153: ["Dragon 32/64"], 158: ["Commodore CDTV"],
        159: ["Nintendo DS"], 166: ["Nintendo Pokemon Mini"], 167: ["Sony Playstation 5"],
        169: ["Microsoft Xbox Series X/S"], 236: ["Exidy Sorcerer"], 274: ["NEC PC-FX"], 306: ["Nintendo Satellaview"],
        307: ["Nintendo Game & Watch"], 339: ["Sega Pico"], 373: ["Sinclair ZX-81"], 376: ["Epoch Super Cassette Vision"],
        379: ["Tiger Game.com"], 380: ["Casio Loopy"], 407: ["Mattel HyperScan"], 408: ["Mega Duck"],
        410: ["Atari Jaguar CD"], 415: ["Watara Supervision"], 416: ["Nintendo 64DD"], 438: ["Arduboy"],
        439: ["VTech V.Smile"], 440: ["Sega Dreamcast VMU"], 441: ["Sony PocketStation"], 473: ["Emerson Arcadia 2001"],
        480: ["Funtech Super Acan"], 481: ["Tomy Tutor"], 482: ["Sega CD 32X"], 487: ["Pioneer LaserActive"],
        504: ["Uzebox"], 506: ["Amstrad GX4000"], 508: ["Nintendo Switch 2"],
    ]
}

/// A name's two title keys, each a column of `launchbox_name`, tried in turn as libretro's fuzzy match does.
enum TitleKey: String, CaseIterable {
    case title = "title_key"
    case loose = "loose_title_key"

    func of(_ title: String) -> String {
        switch self {
        case .title: LibretroLookup.titleKey(title)
        case .loose: LibretroLookup.looseTitleKey(title)
        }
    }
}

/// The image types kept from a dump, each stored as its raw value; Screenshots in the order they're shown, title screens
/// first.
enum LaunchBoxImageType: Int, CaseIterable, Sendable {
    case boxFront, titleScreen, gameplay

    static let screenshots: [LaunchBoxImageType] = [.titleScreen, .gameplay]

    /// Its name in the dump.
    var name: String {
        switch self {
        case .boxFront: "Box - Front"
        case .titleScreen: "Screenshot - Game Title"
        case .gameplay: "Screenshot - Gameplay"
        }
    }

    init?(name: String) {
        guard let type = Self.allCases.first(where: { $0.name == name }) else { return nil }
        self = type
    }
}

/// One image a title key found.
struct LaunchBoxImage: Sendable {
    let gameID: Int
    let type: LaunchBoxImageType
    let fileName: String
    let region: String?
    /// Found by the game's own name, not an alternate one.
    let own: Bool
    let year: Int?
    /// The length of the name it was found by.
    let nameLength: Int
    /// Its place in the dump.
    let position: Int
}

/// What's kept of a dump: the games on the Platforms `LaunchBoxGamesDB.platforms` maps that have an image of a kept type,
/// each game's names and those images.
struct LaunchBoxDump: Sendable {
    struct Game: Sendable {
        let id: Int
        let platform: String
        let year: Int?
    }

    struct Name: Sendable {
        let gameID: Int
        let name: String
        let own: Bool
    }

    struct Image: Sendable {
        let gameID: Int
        let type: LaunchBoxImageType
        let region: String?
        let fileName: String
    }

    var games: [Game] = []
    var names: [Name] = []
    var images: [Image] = []

    /// `Metadata.xml`, streamed out of the zip by the system's `unzip`, so the 575 MB is never written out.
    static func read(zip: URL) throws -> LaunchBoxDump {
        let unzip = Process()
        unzip.executableURL = URL(filePath: "/usr/bin/unzip")
        unzip.arguments = ["-p", zip.path(percentEncoded: false), "Metadata.xml"]
        let pipe = Pipe()
        unzip.standardOutput = pipe
        unzip.standardError = FileHandle.nullDevice
        try unzip.run()
        try? pipe.fileHandleForWriting.close()
        let dump: LaunchBoxDump
        do {
            guard let stream = InputStream(fileAtPath: "/dev/fd/\(pipe.fileHandleForReading.fileDescriptor)") else {
                throw LaunchBoxDumpError.unreadable("its unzipped output couldn't be opened")
            }
            dump = try read(stream)
        } catch {
            unzip.terminate()
            unzip.waitUntilExit()
            throw error
        }
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            throw LaunchBoxDumpError.unreadable("unzip exited with status \(unzip.terminationStatus)")
        }
        return dump
    }

    /// The dump's XML. One with no game kept throws rather than leave nothing to look in.
    static func read(_ stream: InputStream) throws -> LaunchBoxDump {
        let reader = DumpReader()
        let parser = XMLParser(stream: stream)
        parser.delegate = reader
        guard parser.parse() else {
            throw LaunchBoxDumpError.unreadable(parser.parserError?.localizedDescription ?? "it isn't XML")
        }
        let dump = reader.kept()
        guard !dump.games.isEmpty else { throw LaunchBoxDumpError.unreadable("it has no games") }
        return dump
    }
}

enum LaunchBoxDumpError: Error, CustomStringConvertible {
    case unreadable(String)

    var description: String {
        switch self {
        case .unreadable(let why): "LaunchBox's Metadata.zip couldn't be read: \(why)"
        }
    }
}

/// Collects the fields wanted from each `Game`, `GameAlternateName` and `GameImage`, skipping the rest (overviews and
/// the like) unread.
private final class DumpReader: NSObject, XMLParserDelegate {
    private static let fields: [String: Set<String>] = [
        "Game": ["DatabaseID", "Name", "Platform", "ReleaseDate", "ReleaseYear"],
        "GameAlternateName": ["DatabaseID", "AlternateName"],
        "GameImage": ["DatabaseID", "FileName", "Type", "Region"],
    ]
    private static let platforms = Set(LaunchBoxGamesDB.platforms.values.joined())

    private var games: [Int: (game: LaunchBoxDump.Game, name: String)] = [:]
    private var gameOrder: [Int] = []
    private var alternateNames: [(gameID: Int, name: String)] = []
    private var images: [LaunchBoxDump.Image] = []

    private var section: String?
    private var field: String?
    private var text = ""
    private var values: [String: String] = [:]

    func parser(
        _ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        if let section {
            if Self.fields[section]!.contains(element) {
                field = element
                text = ""
            }
        } else if Self.fields[element] != nil {
            section = element
            values = [:]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if field != nil { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if element == field {
            values[element] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            field = nil
        } else if element == section {
            finish(element)
            section = nil
        }
    }

    private func finish(_ section: String) {
        guard let id = values["DatabaseID"].flatMap(Int.init) else { return }
        switch section {
        case "Game":
            guard let platform = values["Platform"], Self.platforms.contains(platform), let name = values["Name"], !name.isEmpty
            else { return }
            let year = values["ReleaseDate"].flatMap { Int($0.prefix(4)) } ?? values["ReleaseYear"].flatMap(Int.init)
            if games[id] == nil { gameOrder.append(id) }
            games[id] = (LaunchBoxDump.Game(id: id, platform: platform, year: year), name)
        case "GameAlternateName":
            if let name = values["AlternateName"], !name.isEmpty { alternateNames.append((id, name)) }
        case "GameImage":
            guard let type = values["Type"].flatMap(LaunchBoxImageType.init(name:)), let file = values["FileName"], !file.isEmpty
            else { return }
            images.append(
                LaunchBoxDump.Image(gameID: id, type: type, region: values["Region"].flatMap { $0.isEmpty ? nil : $0 }, fileName: file))
        default: break
        }
    }

    /// The games on mapped Platforms with an image kept, whatever order the dump gave them in.
    func kept() -> LaunchBoxDump {
        let keptImages = images.filter { games[$0.gameID] != nil }
        let withImages = Set(keptImages.map(\.gameID))
        let ids = gameOrder.filter(withImages.contains)
        return LaunchBoxDump(
            games: ids.map { games[$0]!.game },
            names: ids.map { LaunchBoxDump.Name(gameID: $0, name: games[$0]!.name, own: true) }
                + alternateNames.filter { withImages.contains($0.gameID) }.map {
                    LaunchBoxDump.Name(gameID: $0.gameID, name: $0.name, own: false)
                },
            images: keptImages)
    }
}

extension CacheStore {
    /// Replaces what's kept of the last dump with `dump`, all at once, and notes when it was read.
    func replaceLaunchBox(_ dump: LaunchBoxDump) throws {
        let readAt = clock.now().timeIntervalSince1970
        try db.write { db in
            try db.execute(sql: "DELETE FROM launchbox_game; DELETE FROM launchbox_name; DELETE FROM launchbox_image")
            let game = try db.makeStatement(sql: "INSERT INTO launchbox_game (id, platform, year) VALUES (?, ?, ?)")
            for g in dump.games { try game.execute(arguments: [g.id, g.platform, g.year]) }
            let name = try db.makeStatement(
                sql: "INSERT INTO launchbox_name (game_id, own, length, title_key, loose_title_key) VALUES (?, ?, ?, ?, ?)")
            for n in dump.names {
                try name.execute(
                    arguments: [n.gameID, n.own, n.name.count, TitleKey.title.of(n.name), TitleKey.loose.of(n.name)])
            }
            let image = try db.makeStatement(
                sql: "INSERT INTO launchbox_image (game_id, type, region, file_name, position) VALUES (?, ?, ?, ?, ?)")
            for (position, i) in dump.images.enumerated() {
                try image.execute(arguments: [i.gameID, i.type.rawValue, i.region, i.fileName, position])
            }
            try db.execute(
                sql: "INSERT OR REPLACE INTO entry (key, payload, fetched_at) VALUES (?, ?, ?)",
                arguments: [LaunchBoxGamesDB.readKey, Data(), readAt])
        }
    }

    /// Every image of `types` of the games on `platforms` with a name whose `titleKey` is `key`.
    func launchBoxImages(_ types: [LaunchBoxImageType], _ titleKey: TitleKey, _ key: String, platforms: [String]) throws -> [LaunchBoxImage]
    {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT g.id, i.type, i.file_name, i.region, n.own, g.year, n.length, i.position
                    FROM launchbox_name n
                    JOIN launchbox_game g ON g.id = n.game_id
                    JOIN launchbox_image i
                        ON i.game_id = g.id AND i.type IN (\(types.map { _ in "?" }.joined(separator: ",")))
                    WHERE n.\(titleKey.rawValue) = ? AND g.platform IN (\(platforms.map { _ in "?" }.joined(separator: ",")))
                    """,
                arguments: StatementArguments(types.map(\.rawValue) + [key] + platforms)
            ).compactMap { row in
                LaunchBoxImageType(rawValue: row["type"]).map { type in
                    LaunchBoxImage(
                        gameID: row["id"], type: type, fileName: row["file_name"], region: row["region"], own: row["own"],
                        year: row["year"], nameLength: row["length"], position: row["position"])
                }
            }
        }
    }
}
