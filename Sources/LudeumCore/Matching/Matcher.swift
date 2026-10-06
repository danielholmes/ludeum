import CryptoKit
import Foundation

/// A ROM as far as matching it is concerned. The checksum rules were written against OpenEmu's library, which
/// gave each ROM an MD5, an OpenVGDB title and a system; a ROM folder's ROM has none of them yet.
public struct ROMToMatch: Sendable, Hashable {
    /// Its key in the results.
    public let id: Int
    public let name: String
    /// OpenVGDB's title, from OpenEmu.
    public let openVGDBTitle: String?
    /// An OpenEmu system, e.g. "openemu.system.snes", for the NES/SNES header retry; empty for none.
    public let system: String
    /// Empty for none.
    public let md5: String
    /// The ROM file, if known. It may not exist.
    public let file: URL?
    /// The IGDB platforms it could be on, most likely first: its system's, unless given (a ROM folder's one).
    public let platforms: [Int]

    public init(id: Int, name: String, openVGDBTitle: String?, system: String, md5: String, file: URL?, platforms: [Int]? = nil) {
        self.id = id
        self.name = name
        self.openVGDBTitle = openVGDBTitle
        self.system = system
        self.md5 = md5
        self.file = file
        self.platforms = platforms ?? openEmuSystemPlatforms[system] ?? []
    }
}

public enum MatchResult: Sendable, Hashable, Codable {
    /// The checksum identifies the game *and* the names agree (ADR 0004).
    case automatic(gameID: Int)
    /// For the Review queue to confirm.
    case suggestion(Suggestion)
    /// For the Review queue, to search IGDB by hand.
    case noSuggestion
}

public struct Suggestion: Sendable, Hashable, Codable {
    public enum Source: String, Sendable, Hashable, Codable {
        /// The checksum's own game, whose names disagree.
        case checksum
        /// A related record of the checksum's game, whose name agrees.
        case relatedRecord
        /// IGDB name search on the ROM's platforms.
        case nameSearch
    }

    public let gameID: Int
    public let source: Source
    /// Names agree, so the Review queue can bulk-confirm it.
    public let namesAgree: Bool
    /// For a related-record suggestion, the checksum's own game (shown crossed out).
    public let checksumGameID: Int?

    public init(gameID: Int, source: Source, namesAgree: Bool, checksumGameID: Int? = nil) {
        self.gameID = gameID
        self.source = source
        self.namesAgree = namesAgree
        self.checksumGameID = checksumGameID
    }
}

/// OpenEmu system → IGDB platform ids, most likely first. Game Boy covers Game Boy Color,
/// and SNES/NES cover the Japanese Super Famicom/Famicom releases.
public let openEmuSystemPlatforms: [String: [Int]] = [
    "openemu.system.gb": [33, 22], "openemu.system.snes": [19, 58], "openemu.system.nes": [18, 99],
    "openemu.system.psx": [7], "openemu.system.sg": [29], "openemu.system.gba": [24],
    "openemu.system.nds": [20], "openemu.system.psp": [38], "openemu.system.n64": [4],
    "openemu.system.gc": [21], "openemu.system.sms": [64], "openemu.system.scd": [78],
    "openemu.system.saturn": [32], "openemu.system.gg": [35], "openemu.system.pcecd": [150],
]

/// Matches ROMs to IGDB games, from the cache where it can.
public final class Matcher: Sendable {
    let igdb: IGDBClient
    let hasheous: HasheousClient

    public init(igdb: IGDBClient, hasheous: HasheousClient) {
        self.igdb = igdb
        self.hasheous = hasheous
    }

    /// Every ROM's result, keyed by ROM id. `progress` gets (ROMs looked up, total); it can be cancelled.
    public func match(_ roms: [ROMToMatch], progress: @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> [Int: MatchResult] {
        var checksumGame: [Int: Int] = [:]
        var candidates: [Int: [Int]] = [:]
        for (i, rom) in roms.enumerated() {
            try Task.checkCancellation()
            progress(i, roms.count)
            if let game = try await checksumGameID(rom) {
                checksumGame[rom.id] = game
            } else {
                candidates[rom.id] = try await searchCandidates(rom)
            }
        }

        // IGDB records in two batches: checksum games and search candidates, then the checksum games' relatives.
        var games = try await igdb.games(ids: Array(Set(checksumGame.values).union(candidates.values.joined())))
        let relatives = Set(checksumGame.values.flatMap { games[$0].map(relatedIDs) ?? [] }).subtracting(games.keys)
        games.merge(try await igdb.games(ids: Array(relatives))) { a, _ in a }

        var out: [Int: MatchResult] = [:]
        for rom in roms {
            func agree(_ g: IGDBGame) -> Bool { namesAgree(romName: rom.name, openVGDBTitle: rom.openVGDBTitle, game: g) }
            if let id = checksumGame[rom.id] {
                if let game = games[id], agree(game) {
                    out[rom.id] = .automatic(gameID: id)
                } else if let related = games[id].flatMap({ relatedIDs($0).compactMap { games[$0] }.first(where: agree) }) {
                    out[rom.id] = .suggestion(Suggestion(gameID: related.id, source: .relatedRecord, namesAgree: true, checksumGameID: id))
                } else {
                    out[rom.id] = .suggestion(Suggestion(gameID: id, source: .checksum, namesAgree: false))
                }
            } else {
                let eligible = (candidates[rom.id] ?? []).compactMap { games[$0] }.filter(canBeAGame)
                if let g = eligible.first(where: agree) {
                    out[rom.id] = .suggestion(Suggestion(gameID: g.id, source: .nameSearch, namesAgree: true))
                } else if let g = eligible.first {
                    out[rom.id] = .suggestion(Suggestion(gameID: g.id, source: .nameSearch, namesAgree: false))
                } else {
                    out[rom.id] = .noSuggestion
                }
            }
        }
        return out
    }

    /// Hasheous by the ROM's MD5, then for an NES/SNES dump already on disk, by its MD5 without the header.
    private func checksumGameID(_ rom: ROMToMatch) async throws -> Int? {
        // A ROM folder's ROM has no checksum, so it's only ever suggested by name (ADR 0004).
        guard !rom.md5.isEmpty else { return nil }
        if let id = try await hasheous.lookup(md5: rom.md5).match?.igdbGameID { return id }
        guard let file = rom.file, let md5 = headerlessMD5(file, system: rom.system) else { return nil }
        return try await hasheous.lookup(md5: md5).match?.igdbGameID
    }

    /// The first non-empty IGDB name search, trying each of the system's platforms with the ROM's
    /// cleaned name, then OpenVGDB's title.
    private func searchCandidates(_ rom: ROMToMatch) async throws -> [Int] {
        var names: [String] = []
        for n in [cleanName(rom.name), rom.openVGDBTitle ?? ""] where !n.isEmpty && !names.contains(n) { names.append(n) }
        for platform in rom.platforms {
            for name in names {
                let search = IGDBSearch(name: name, platformID: platform)
                if let ids = try await igdb.search([search])[search], !ids.isEmpty { return ids }
            }
        }
        return []
    }
}

/// IGDB records a checksum's game is related to, which may be the right Game when it isn't.
private func relatedIDs(_ game: IGDBGame) -> [Int] {
    let single = ["parent_game", "version_parent"].compactMap { game.record[$0]?["id"]?.int ?? game.record[$0]?.int }
    let lists = ["expanded_games", "remasters", "remakes", "ports", "standalone_expansions", "forks"].flatMap { field in
        (game.record[field]?.array ?? []).compactMap { $0["id"]?.int ?? $0.int }
    }
    return single + lists
}

/// DLC (1), Expansion (2), Mod (5), Season (7), Pack/Addon (13) and Update (14) are never suggested.
private func canBeAGame(_ game: IGDBGame) -> Bool {
    ![1, 2, 5, 7, 13, 14].contains(game.record["game_type"]?.int ?? 0)
}

// MARK: - Headerless checksums

/// MD5 of a headered NES/SNES dump with its header removed, if it has one. Only reads files
/// already on disk (never downloading online-only ones), uncompressed or in a small single-file archive.
func headerlessMD5(_ url: URL, system: String) -> String? {
    guard ["openemu.system.nes", "openemu.system.snes"].contains(system), isLocal(url), let data = romData(url) else { return nil }
    let body: Data
    if system == "openemu.system.nes", data.starts(with: [0x4E, 0x45, 0x53, 0x1A]) {
        body = data.dropFirst(16)
    } else if system == "openemu.system.snes", data.count % 1024 == 512 {
        body = data.dropFirst(512)
    } else {
        return nil
    }
    return Insecure.MD5.hash(data: body).map { String(format: "%02x", $0) }.joined()
}

/// Online-only (File Provider) files are "dataless": reading them would download them.
private func isLocal(_ url: URL) -> Bool {
    var st = stat()
    guard lstat(url.path(percentEncoded: false), &st) == 0 else { return false }
    return st.st_flags & 0x4000_0000 == 0  // SF_DATALESS
}

/// The ROM bytes: read directly, or unpacked in memory from a small single-file .7z/.zip
/// with the system's libarchive `tar`.
private func romData(_ url: URL) -> Data? {
    guard ["7z", "zip"].contains(url.pathExtension.lowercased()) else { return try? Data(contentsOf: url) }
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
    guard size < 16 << 20 else { return nil }
    func tar(_ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/tar")
        p.arguments = args + [url.path(percentEncoded: false)]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }
    let entries = tar(["-tf"]).map { String(decoding: $0, as: UTF8.self).split(separator: "\n") } ?? []
    guard entries.count == 1 else { return nil }
    return tar(["-xOf"])
}
