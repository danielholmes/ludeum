import Foundation
import GRDB

/// One ROM in OpenEmu's library, as `migrate-openemu` reads it.
public struct OpenEmuROMRecord: Sendable, Hashable {
    /// `ZROM.Z_PK`.
    public let pk: Int64
    /// e.g. "openemu.system.snes".
    public let system: String
    public let file: URL?
    /// The file is there. An orphaned entry (row kept, file gone) has none.
    public let isPresent: Bool
}

/// OpenEmu system → IGDB platform ids, most likely first: the Platforms `migrate-openemu` lets a system's ROM
/// go to. Game Boy covers Game Boy Color, and SNES/NES cover the Japanese Super Famicom/Famicom releases.
let openEmuSystemPlatforms: [String: [Int]] = [
    "openemu.system.gb": [33, 22], "openemu.system.snes": [19, 58], "openemu.system.nes": [18, 99],
    "openemu.system.psx": [7], "openemu.system.sg": [29], "openemu.system.gba": [24],
    "openemu.system.nds": [20], "openemu.system.psp": [38], "openemu.system.n64": [4],
    "openemu.system.gc": [21], "openemu.system.sms": [64], "openemu.system.scd": [78],
    "openemu.system.saturn": [32], "openemu.system.gg": [35], "openemu.system.pcecd": [150],
]

/// What `migrate-openemu` reads from one snapshot of OpenEmu's database.
public struct OpenEmuLibrarySnapshot: Sendable, Equatable {
    /// Ordered by `Z_PK`.
    public let roms: [OpenEmuROMRecord]
}

/// OpenEmu's library, read only by `migrate-openemu` as it moves the ROMs out (ADR 0009).
public enum OpenEmuLibrary {
    /// Where OpenEmu itself keeps its library.
    public static func databaseFile(in library: URL) -> URL { library.appending(path: "Library.storedata") }

    /// Opens OpenEmu's store to read. A read-only connection can't open a WAL store whose -shm file
    /// is gone (after a clean close), so that case falls back to a normal connection used only for reading.
    static func openForReading(_ file: URL) throws -> DatabaseQueue {
        var config = Configuration()
        config.readonly = true
        do {
            return try DatabaseQueue(path: file.path(percentEncoded: false), configuration: config)
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CANTOPEN {
            return try DatabaseQueue(path: file.path(percentEncoded: false))
        }
    }

    /// Copies OpenEmu's database with SQLite's backup API: safe while OpenEmu is running, and
    /// never writes to OpenEmu.
    public static func snapshot(library: URL, to file: URL) throws {
        let live = try openForReading(databaseFile(in: library))
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
        return try db.read { db in
            let roms = try Row.fetchAll(
                db,
                sql: """
                    SELECT r.Z_PK AS pk, r.ZLOCATION AS location, s.ZSYSTEMIDENTIFIER AS system
                    FROM ZROM r JOIN ZGAME g ON r.ZGAME = g.Z_PK JOIN ZSYSTEM s ON g.ZSYSTEM = s.Z_PK
                    ORDER BY r.Z_PK
                    """
            ).map { row in
                let location: String? = row["location"]
                let file = location.flatMap { loc in
                    loc.hasPrefix("file://") ? URL(string: loc) : loc.removingPercentEncoding.map { romsFolder.appending(path: $0) }
                }
                return OpenEmuROMRecord(
                    pk: row["pk"], system: row["system"], file: file,
                    isPresent: file.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false)
            }
            return OpenEmuLibrarySnapshot(roms: roms)
        }
    }
}
