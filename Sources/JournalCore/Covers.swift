import CryptoKit
import Foundation
import GRDB
import ImageIO
import UniformTypeIdentifiers

public enum CoverError: Error, Equatable {
    case notAnImage
    /// Upload, replace and remove are only offered while a Game has no IGDB cover.
    case igdbHasACover
}

/// A journal-owned Cover after normalising: JPEG at quality 0.9, at most 1,200 px on its long edge.
public struct NormalisedCover: Sendable, Equatable {
    public let jpeg: Data
    public let width: Int
    public let height: Int
    public let sha256: String
}

public enum CoverOrigin: String, Sendable {
    /// OpenEmu's box art, carried over at the first Import.
    case carried
    case uploaded
}

/// A Cover the journal owns, stored in the journal database so backups carry it.
public struct JournalCover: Sendable, Equatable {
    public let image: NormalisedCover
    public let origin: CoverOrigin
    public var width: Int { image.width }
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

extension JournalStore {
    public func journalCover(_ game: GameID) throws -> JournalCover? {
        try db.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM cover WHERE gameId = ?", arguments: [game]).map { row in
                JournalCover(
                    image: NormalisedCover(jpeg: row["jpeg"], width: row["width"], height: row["height"], sha256: row["sha256"]),
                    origin: CoverOrigin(rawValue: row["origin"]) ?? .uploaded)
            }
        }
    }

    /// Stores (or replaces) a Game's journal-owned Cover. Whether IGDB has one is `Covers`' business.
    public func storeCover(_ game: GameID, _ cover: NormalisedCover, origin: CoverOrigin) throws {
        try db.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO cover (gameId, jpeg, width, height, origin, sha256) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [game, cover.jpeg, cover.width, cover.height, origin.rawValue, cover.sha256])
        }
    }

    public func deleteCover(_ game: GameID) throws {
        try db.write { db in try db.execute(sql: "DELETE FROM cover WHERE gameId = ?", arguments: [game]) }
    }
}

/// What a Game shows as its Cover.
public enum CoverSource: Sendable, Equatable {
    /// IGDB's cover, a file in the cache's images folder.
    case igdb(URL)
    /// A journal-owned Cover.
    case journal(JournalCover)
    case placeholder
}

/// A Game's Cover: IGDB's whenever its record has one (IGDB always wins), else the journal's own.
public struct Covers: Sendable {
    let journal: JournalStore
    let igdb: IGDBClient?

    /// Without an IGDB client (no credentials), linked Games show their journal Cover, if any, and can't upload.
    public init(journal: JournalStore, igdb: IGDBClient?) {
        self.journal = journal
        self.igdb = igdb
    }

    /// The Cover to show, downloading IGDB's on demand. Also deletes a journal-owned Cover that
    /// IGDB has made redundant.
    public func cover(for game: GameID) async throws -> CoverSource {
        if let imageID = try await igdbCoverID(game), let igdb {
            // Download first, so a failed download never costs the journal's Cover.
            let file = try await igdb.cover(imageID: imageID)
            try journal.deleteCover(game)
            return .igdb(file)
        }
        return try journal.journalCover(game).map(CoverSource.journal) ?? .placeholder
    }

    /// Upload, replace and remove are offered only while the Game has no IGDB cover.
    /// Without an IGDB client a linked Game might have an IGDB cover, so uploading waits for one.
    public func canUpload(for game: GameID) async throws -> Bool {
        if igdb == nil, try journal.game(game).igdbGameId != nil { return false }
        return try await igdbCoverID(game) == nil
    }

    public func upload(_ image: Data, for game: GameID) async throws {
        guard try await canUpload(for: game) else { throw CoverError.igdbHasACover }
        try journal.storeCover(game, try CoverImage.normalise(image), origin: .uploaded)
    }

    public func remove(for game: GameID) async throws {
        guard try await canUpload(for: game) else { throw CoverError.igdbHasACover }
        try journal.deleteCover(game)
    }

    /// Deletes the Game's journal-owned Cover, with no prompt, if IGDB now has one: after it gains
    /// a link, or a refresh brings a cover to its record.
    public func reconcile(_ game: GameID) async throws {
        if try await igdbCoverID(game) != nil { try journal.deleteCover(game) }
    }

    /// The `image_id` of IGDB's cover for a linked Game, from the cached record.
    private func igdbCoverID(_ game: GameID) async throws -> String? {
        guard let igdb, let id = try journal.game(game).igdbGameId.map(Int.init) else { return nil }
        return try await igdb.games(ids: [id])[id]?.record["cover"]?["image_id"]?.string
    }
}
