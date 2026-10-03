import Foundation
import GRDB

/// One ROM in OpenEmu's library, with everything the Import reads from it.
public struct OpenEmuROMRecord: Codable, Sendable, Hashable {
    /// `ZROM.Z_PK`.
    public let pk: Int64
    public let md5: String
    /// `ZGAME.ZNAME`.
    public let name: String
    /// `ZGAME.ZGAMETITLE`, OpenVGDB's title.
    public let openVGDBTitle: String?
    /// e.g. "openemu.system.snes".
    public let system: String
    public let file: URL?
    /// The file is there. An orphaned entry (row kept, file gone) is imported as a missing ROM.
    public let isPresent: Bool
    /// OpenEmu's stars, 0–5 (0 is none).
    public let stars: Int
    /// The regular collections it's in, by name.
    public let collections: [String]
    public let playCount: Int
    public let lastPlayedAt: Date?
    public let playTimeSeconds: Double
    /// OpenEmu's box art, under the library's `Artwork/`.
    public let boxArt: URL?

    var isPlaylist: Bool { file?.pathExtension.lowercased() == "m3u" }

    var matcherROM: OpenEmuROM {
        OpenEmuROM(id: Int(pk), name: name, openVGDBTitle: openVGDBTitle, system: system, md5: md5, file: file)
    }
}

/// What the Import reads from one snapshot of OpenEmu's database.
public struct OpenEmuLibrarySnapshot: Codable, Sendable, Equatable {
    /// The Core Data store UUID: a different one means the library was rebuilt or replaced.
    public let storeUUID: String
    /// Ordered by `Z_PK`.
    public let roms: [OpenEmuROMRecord]
}

public enum OpenEmuLibrary {
    /// Where OpenEmu itself keeps its library.
    public static func databaseFile(in library: URL) -> URL { library.appending(path: "Library.storedata") }

    /// Copies OpenEmu's database with SQLite's backup API: safe while OpenEmu is running, and
    /// never writes to OpenEmu.
    public static func snapshot(library: URL, to file: URL) throws {
        var config = Configuration()
        config.readonly = true
        let live = try DatabaseQueue(path: databaseFile(in: library).path(percentEncoded: false), configuration: config)
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let copy = try DatabaseQueue(path: file.path(percentEncoded: false))
        try live.backup(to: copy)
        // The copy inherits OpenEmu's WAL mode, which a read-only open can't use without its -shm file.
        try copy.writeWithoutTransaction { try $0.execute(sql: "PRAGMA journal_mode = DELETE") }
        try copy.close()
        try live.close()
    }

    /// Reads a snapshot. File paths and presence are resolved against the live library folder.
    public static func read(snapshot file: URL, library: URL) throws -> OpenEmuLibrarySnapshot {
        var config = Configuration()
        config.readonly = true
        let db = try DatabaseQueue(path: file.path(percentEncoded: false), configuration: config)
        defer { try? db.close() }
        let romsFolder = library.appending(path: "roms", directoryHint: .isDirectory)
        let artwork = library.appending(path: "Artwork", directoryHint: .isDirectory)
        return try db.read { db in
            let uuid = try String.fetchOne(db, sql: "SELECT Z_UUID FROM Z_METADATA") ?? ""
            // Core Data numbers its entities per model version, and names the Collection's many-to-many
            // table after them (Z_2GAMES with Z_2COLLECTIONS and Z_7GAMES in my library), so read them.
            func entity(_ name: String) throws -> Int {
                guard let n = try Int.fetchOne(db, sql: "SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = ?", arguments: [name]) else {
                    throw DatabaseError(message: "OpenEmu's library has no \(name) entity")
                }
                return n
            }
            let collection = try entity("Collection")
            let game = try entity("Game")
            var collections: [Int64: [String]] = [:]
            for row in try Row.fetchAll(
                db,
                sql: """
                    SELECT j.Z_\(game)GAMES AS game, c.ZNAME AS name FROM Z_\(collection)GAMES j
                    JOIN ZABSTRACTCOLLECTION c ON c.Z_PK = j.Z_\(collection)COLLECTIONS
                    WHERE c.Z_ENT = ? AND c.ZNAME IS NOT NULL
                    """, arguments: [collection])
            {
                collections[row["game"], default: []].append(row["name"])
            }
            let roms = try Row.fetchAll(
                db,
                sql: """
                    SELECT r.Z_PK AS pk, r.ZMD5 AS md5, r.ZLOCATION AS location, r.ZPLAYCOUNT AS playCount,
                        r.ZLASTPLAYED AS lastPlayed, r.ZPLAYTIME AS playTime,
                        g.Z_PK AS game, g.ZNAME AS name, g.ZGAMETITLE AS title, g.ZRATING AS rating,
                        s.ZSYSTEMIDENTIFIER AS system, i.ZRELATIVEPATH AS art
                    FROM ZROM r JOIN ZGAME g ON r.ZGAME = g.Z_PK JOIN ZSYSTEM s ON g.ZSYSTEM = s.Z_PK
                    LEFT JOIN ZIMAGE i ON i.Z_PK = g.ZBOXIMAGE
                    ORDER BY r.Z_PK
                    """
            ).map { row in
                let location: String? = row["location"]
                let file = location.flatMap { loc in
                    loc.hasPrefix("file://") ? URL(string: loc) : loc.removingPercentEncoding.map { romsFolder.appending(path: $0) }
                }
                let art: String? = row["art"]
                return OpenEmuROMRecord(
                    pk: row["pk"], md5: (row["md5"] as String?)?.lowercased() ?? "", name: row["name"] ?? "",
                    openVGDBTitle: row["title"], system: row["system"], file: file,
                    isPresent: file.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false,
                    stars: row["rating"] ?? 0, collections: (collections[row["game"]] ?? []).sorted(),
                    playCount: row["playCount"] ?? 0,
                    lastPlayedAt: (row["lastPlayed"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:)),
                    playTimeSeconds: row["playTime"] ?? 0, boxArt: art.map { artwork.appending(path: $0) })
            }
            return OpenEmuLibrarySnapshot(storeUUID: uuid, roms: roms)
        }
    }
}

/// OpenEmu's special collections, which become journal data rather than Lists.
enum SpecialCollection {
    static let backlog = "_TODO"
    static let upNext = "_TODO Next"
    static let current = "_Current"
    static let completed = "_Completed"
    static let childhood = "_Childhood Played"
    static let all: Set<String> = [backlog, upNext, current, completed, childhood]
}
