import Foundation
import GRDB

@testable import LudeumCore

/// A small OpenEmu library on disk, as `migrate-openemu` finds it: `Library.storedata` with the Core Data
/// tables it reads, and ROM files under `roms/`.
final class FakeOpenEmu {
    let folder: URL
    let db: DatabaseQueue
    private var nextPK: Int64 = 1

    init(in parent: URL) throws {
        folder = parent.appending(path: "OpenEmu Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "roms"), withIntermediateDirectories: true)
        db = try DatabaseQueue(path: folder.appending(path: "Library.storedata").path(percentEncoded: false))
        // Like OpenEmu's own store.
        try db.writeWithoutTransaction { try $0.execute(sql: "PRAGMA journal_mode = WAL") }
        // Read-only opens of a WAL store need its -shm file, which this connection keeps alive.
        try db.write { db in
            try db.execute(
                sql: """
                    CREATE TABLE ZSYSTEM (Z_PK INTEGER PRIMARY KEY, ZSYSTEMIDENTIFIER VARCHAR UNIQUE);
                    CREATE TABLE ZGAME (Z_PK INTEGER PRIMARY KEY, ZSYSTEM INTEGER, ZNAME VARCHAR);
                    CREATE TABLE ZROM (Z_PK INTEGER PRIMARY KEY, ZGAME INTEGER, ZLOCATION VARCHAR, ZMD5 VARCHAR);
                    """)
        }
    }

    /// Adds a ROM (and its OpenEmu game) and returns its `Z_PK`. `fileName: nil` leaves no file on disk.
    @discardableResult
    func addROM(_ name: String, md5: String, system: String = "openemu.system.snes", fileName: String? = "rom.sfc") throws -> Int64 {
        let pk = nextPK
        nextPK += 1
        let location = "\(system)/\(pk)-\(fileName ?? "missing.sfc")"
        if let fileName {
            let file = folder.appending(path: "roms").appending(path: "\(system)/\(pk)-\(fileName)")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("rom \(pk)".utf8).write(to: file)
        }
        try db.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO ZSYSTEM (ZSYSTEMIDENTIFIER) VALUES (?)", arguments: [system])
            let systemPK = try Int64.fetchOne(db, sql: "SELECT Z_PK FROM ZSYSTEM WHERE ZSYSTEMIDENTIFIER = ?", arguments: [system])!
            try db.execute(sql: "INSERT INTO ZGAME VALUES (?, ?, ?)", arguments: [pk, systemPK, name])
            try db.execute(
                sql: "INSERT INTO ZROM VALUES (?, ?, ?, ?)",
                arguments: [pk, pk, location.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), md5.uppercased()])
        }
        return pk
    }

    /// Deletes a ROM's row, as removing it in OpenEmu does.
    func removeROM(_ pk: Int64) throws {
        try db.write { try $0.execute(sql: "DELETE FROM ZROM WHERE Z_PK = ?", arguments: [pk]) }
    }
}
