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
                sql: "INSERT OR REPLACE INTO cover (gameId, jpeg, width, height, sha256) VALUES (?, ?, ?, ?, ?)",
                arguments: [game, cover.jpeg, cover.width, cover.height, cover.sha256])
        }
    }

    public func deleteCover(_ game: GameID) throws {
        try db.write { db in try db.execute(sql: "DELETE FROM cover WHERE gameId = ?", arguments: [game]) }
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
}

/// What a Game shows as its Cover.
public enum CoverSource: Sendable, Equatable {
    case upload(NormalisedCover)
    /// libretro-thumbnails' Box art (a PNG) in the cache, by its path on the CDN.
    case libretro(URL, path: String)
    /// IGDB's Cover art in the cache.
    case igdb(URL, imageID: String)
    case placeholder
}

/// A Game's Cover: my upload, else libretro Box art, else IGDB's Cover art,
/// else a placeholder. Everything but uploads lives in the cache, downloaded the first time it's shown.
public struct Covers: Sendable {
    let journal: LudeumStore
    let igdb: IGDBClient?
    let libretro: LibretroThumbnails?

    /// Without a client (no cache, no credentials) its source is skipped.
    public init(journal: LudeumStore, igdb: IGDBClient?, libretro: LibretroThumbnails?) {
        self.journal = journal
        self.igdb = igdb
        self.libretro = libretro
    }

    /// The Cover to show, downloading it on demand. A failed download throws rather than falling
    /// down the order, so a Game never flickers between sources.
    public func cover(for game: GameID) async throws -> CoverSource {
        if let upload = try journal.uploadedCover(game) { return .upload(upload) }
        let roms = try journal.coverROMs(game)
        if let libretro, let path = roms.compactMap({ $0 }).first {
            return .libretro(try await libretro.image(path), path: path)
        }
        if let igdb, let id = try journal.game(game).igdbGameId.map(Int.init),
            let imageID = try await igdb.games(ids: [id])[id]?.record["cover"]?["image_id"]?.string
        {
            return .igdb(try await igdb.cover(imageID: imageID), imageID: imageID)
        }
        return .placeholder
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
