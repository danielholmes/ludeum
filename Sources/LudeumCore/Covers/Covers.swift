import CryptoKit
import Foundation
import GRDB
import ImageIO
import UniformTypeIdentifiers

public enum CoverError: Error, Equatable {
    case notAnImage
}

/// A journal-owned Cover after normalising: JPEG at quality 0.9, at most 1,200 px on its long edge.
public struct NormalisedCover: Sendable, Equatable {
    public let jpeg: Data
    public let width: Int
    public let height: Int
    public let sha256: String
}

public enum CoverImage {
    public static let maxLongEdge = 1_200

    /// Decodes anything macOS can (PNG, HEIC, WebP, …), shrinks it to fit a 1,200 px long edge
    /// (never enlarging it) and re-encodes it as JPEG at quality 0.9.
    public static func normalise(_ data: Data) throws -> NormalisedCover {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
            let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw CoverError.notAnImage }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxLongEdge, max(pixelWidth, pixelHeight)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw CoverError.notAnImage }
        let jpeg = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CoverError.notAnImage
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CoverError.notAnImage }
        let bytes = jpeg as Data
        return NormalisedCover(
            jpeg: bytes, width: image.width, height: image.height,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
    }
}

extension LudeumStore {
    /// The Cover I uploaded for a Game, if any.
    public func uploadedCover(_ game: GameID) throws -> NormalisedCover? {
        try db.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM cover WHERE gameId = ?", arguments: [game]).map { row in
                NormalisedCover(jpeg: row["jpeg"], width: row["width"], height: row["height"], sha256: row["sha256"])
            }
        }
    }

    /// Stores (or replaces) a Game's uploaded Cover.
    public func storeCover(_ game: GameID, _ cover: NormalisedCover) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO cover (gameId, jpeg, width, height, sha256) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT (gameId) DO UPDATE SET
                        jpeg = excluded.jpeg, width = excluded.width, height = excluded.height, sha256 = excluded.sha256
                    """,
                arguments: [game, cover.jpeg, cover.width, cover.height, cover.sha256])
        }
    }

    public func deleteCover(_ game: GameID) throws {
        try db.write { db in try db.execute(sql: "DELETE FROM cover WHERE gameId = ?", arguments: [game]) }
    }

    /// Flags the Game's ROMs to be looked up in libretro again at the next Import, as its names have changed.
    static func lookUpBoxArtAgain(_ db: Database, romsOf game: GameID) throws {
        try db.execute(sql: "UPDATE rom SET libretroLookedUp = 0 WHERE gameId = ?", arguments: [game])
    }

    func romIDs(of game: GameID) throws -> [Int64] {
        try db.read { try Int64.fetchAll($0, sql: "SELECT id FROM rom WHERE gameId = ?", arguments: [game]) }
    }

    /// The ROMs whose Box art a Game shows, best first: its present ROMs (the playlist, then Disc 1),
    /// or when none is present, the most recently added missing one.
    func coverROMs(_ game: GameID) throws -> [String?] {
        try db.read { db in
            let rows = try Row.fetchAll(
                db, sql: "SELECT id, fileName, missing, discNumber, libretroBoxart FROM rom WHERE gameId = ?",
                arguments: [game])
            let present = rows.filter { !($0["missing"] as Bool) }
            let chosen: [Row] =
                present.isEmpty
                ? rows.max { ($0["id"] as Int64) < ($1["id"] as Int64) }.map { [$0] } ?? []
                : present.sorted {
                    func key(_ r: Row) -> (Int, Int, Int64) {
                        ((r["fileName"] as String).lowercased().hasSuffix(".m3u") ? 0 : 1, r["discNumber"] ?? 0, r["id"])
                    }
                    return key($0) < key($1)
                }
            return chosen.map { $0["libretroBoxart"] }
        }
    }

    /// What a Game's Box art is looked up by, by title: its Platform, its names (the one shown, then IGDB's, then its
    /// own) and its Copies' Regions, Gone ones included, as the box is the one I had.
    func boxArtLookup(_ game: GameID) throws -> BoxArtLookup {
        try db.read { db in
            let row = try Row.fetchOne(
                db, sql: "SELECT platformId, name, nameOverride, igdbName FROM game WHERE id = ?", arguments: [game])!
            var titles: [String] = []
            for title in [row["nameOverride"], row["igdbName"], row["name"]] as [String?] {
                if let title, !titles.contains(title) { titles.append(title) }
            }
            let regions = try String?.fetchAll(db, sql: "SELECT regions FROM copy WHERE gameId = ?", arguments: [game])
                .flatMap(Regions.decode)
            return BoxArtLookup(platform: row["platformId"], titles: titles, regions: ROMName.regions(named: regions) ?? [])
        }
    }
}

/// What a Game's Box art is looked up by, by title (`LudeumStore.boxArtLookup`).
struct BoxArtLookup {
    let platform: Int64
    let titles: [String]
    let regions: Set<NameRegion>

    /// The same lookup by other names.
    func titled(_ titles: [String]) -> BoxArtLookup { BoxArtLookup(platform: platform, titles: titles, regions: regions) }
}

/// Each source's Box art for a Game, nil where it has none (`Covers.boxArtBySource`).
public struct BoxArtBySource: Sendable, Equatable {
    public let libretro: CoverSource?
    public let launchBox: CoverSource?
}

/// What a Game shows as its Cover.
public enum CoverSource: Sendable, Equatable {
    case upload(NormalisedCover)
    /// libretro-thumbnails' Box art (a PNG) in the cache, by its path on the CDN.
    case libretro(URL, path: String)
    /// The LaunchBox Games Database's Box art in the cache, by its file name there.
    case launchBox(URL, file: String)
    /// IGDB's Cover art in the cache.
    case igdb(URL, imageID: String)
    case placeholder
}

/// A Game's Cover: my upload, else libretro Box art, else LaunchBox's, else the Cover of the first Bundle that contains
/// it, else IGDB's Cover art, else a placeholder. Everything but uploads lives in the cache, downloaded the first time
/// it's shown.
public struct Covers: Sendable {
    let journal: LudeumStore
    let igdb: IGDBClient?
    let libretro: LibretroThumbnails?
    let launchBox: LaunchBoxGamesDB?

    /// Without a client (no cache, no credentials) its source is skipped.
    public init(journal: LudeumStore, igdb: IGDBClient?, libretro: LibretroThumbnails?, launchBox: LaunchBoxGamesDB?) {
        self.journal = journal
        self.igdb = igdb
        self.libretro = libretro
        self.launchBox = launchBox
    }

    /// The Cover to show, downloading it on demand. A failed download throws rather than falling
    /// down the order, so a Game never flickers between sources.
    public func cover(for game: GameID) async throws -> CoverSource {
        if let upload = try journal.uploadedCover(game) { return .upload(upload) }
        let roms = try journal.coverROMs(game)
        let lookup = try journal.boxArtLookup(game)
        if let found = try await libretroBoxArt(roms: roms, lookup) { return found }
        let record = try await igdbGame(game)
        if let found = try await launchBoxBoxArt(lookup, year: record?.releaseYear) { return found }
        // Only once neither finds a box by the Game's own names: IGDB's alternative names reach further (Commander Keen
        // in Invasion of the Vorticons: Marooned on Mars is `Commander Keen 1 - Marooned on Mars`), but can be a working
        // title another game has (Command & Conquer: Renegade was Commando).
        let alternatives = (record?.alternativeNames ?? []).filter { !lookup.titles.contains($0) }
        if !alternatives.isEmpty {
            let byAlternatives = lookup.titled(alternatives)
            if let found = try await libretroBoxArt(roms: roms, byAlternatives) { return found }
            if let found = try await launchBoxBoxArt(byAlternatives, year: record?.releaseYear) { return found }
        }
        // A Game a Bundle contains, with no Box art, shows the first Bundle's Cover: the box it came in.
        if let bundle = try journal.bundles(containing: game).first {
            let cover = try await cover(for: bundle.id)
            if cover != .placeholder { return cover }
        }
        if let igdb, let id = try journal.game(game).igdbGameId.map(Int.init), let imageID = try await igdb.coverImageID(game: id) {
            return .igdb(try await igdb.cover(imageID: imageID), imageID: imageID)
        }
        return .placeholder
    }

    /// Each source's Box art for the Game on its own, as it would be with no other source: by the Game's names, else by
    /// IGDB's alternative names for it. For comparing them, beside the Cover, while it's decided whether both are
    /// needed; uploads and Bundles play no part.
    public func boxArtBySource(for game: GameID) async throws -> BoxArtBySource {
        let roms = try journal.coverROMs(game)
        let lookup = try journal.boxArtLookup(game)
        let record = try await igdbGame(game)
        let alternatives = (record?.alternativeNames ?? []).filter { !lookup.titles.contains($0) }
        let byAlternatives = alternatives.isEmpty ? nil : lookup.titled(alternatives)
        var libretro = try await libretroBoxArt(roms: roms, lookup)
        if libretro == nil, let byAlternatives { libretro = try await libretroBoxArt(roms: roms, byAlternatives) }
        var launchBox = try await launchBoxBoxArt(lookup, year: record?.releaseYear)
        if launchBox == nil, let byAlternatives { launchBox = try await launchBoxBoxArt(byAlternatives, year: record?.releaseYear) }
        return BoxArtBySource(libretro: libretro, launchBox: launchBox)
    }

    /// Its ROMs' Box art, whatever its names, or for a Game with no ROM, a title match on `lookup` in its Platform's
    /// libretro listing. A listing that can't be read finds nothing, as for a ROM not yet looked up: IGDB's Cover art
    /// shows until it can be.
    private func libretroBoxArt(roms: [String?], _ lookup: BoxArtLookup) async throws -> CoverSource? {
        guard let libretro else { return nil }
        let path =
            roms.isEmpty
            ? try? await libretro.boxart(platform: lookup.platform, titles: lookup.titles, regions: lookup.regions)
            : roms.compactMap { $0 }.first
        guard let path else { return nil }
        return .libretro(try await libretro.image(path), path: path)
    }

    /// A title match on `lookup` in LaunchBox, for any Game libretro has no Box art for, with or without a ROM: for its
    /// Copies' Regions, preferring IGDB's `year` for it, which picks the right one of games of the same name (Doom in
    /// 1993 or 2016).
    private func launchBoxBoxArt(_ lookup: BoxArtLookup, year: Int?) async throws -> CoverSource? {
        guard let launchBox,
            let file = try launchBox.boxart(platform: lookup.platform, titles: lookup.titles, regions: lookup.regions, year: year)
        else { return nil }
        return .launchBox(try await launchBox.image(file), file: file)
    }

    /// The Game's IGDB record, from the cache (fetched if it isn't there yet), or nil for a Game not linked to IGDB. One
    /// that can't be fetched is nil too: it only refines the lookup, and IGDB's Cover art, further down, says why.
    private func igdbGame(_ game: GameID) async throws -> IGDBGame? {
        guard let igdb, let id = try journal.game(game).igdbGameId.map(Int.init) else { return nil }
        return try? await igdb.cachedGame(id: id)
    }

    /// Looks the Game's ROMs up in libretro again straight away, as after renaming it, rather than at the next Import.
    /// One that can't be looked up now still is then.
    public func lookUpBoxArt(forROMsOf game: GameID) async {
        guard let roms = try? journal.romIDs(of: game) else { return }
        try? await BoxArtImport(journal: journal, libretro: libretro).lookUp(roms)
    }

    /// Uploads win over everything, on any Game.
    public func upload(_ image: Data, for game: GameID) throws {
        try journal.storeCover(game, try CoverImage.normalise(image))
    }

    /// Removing an upload falls back down the order.
    public func remove(for game: GameID) throws {
        try journal.deleteCover(game)
    }
}
