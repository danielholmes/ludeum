import Foundation
import GRDB

@testable import JournalCore

/// A small OpenEmu library on disk: `Library.storedata` with the Core Data tables the
/// journal reads, ROM files under `roms/`, and box art under `Artwork/`.
final class FakeOpenEmu {
    let folder: URL
    let db: DatabaseQueue
    private var nextPK: Int64 = 1

    init(in parent: URL, storeUUID: String = "STORE-1") throws {
        folder = parent.appending(path: "OpenEmu Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "roms"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appending(path: "Artwork"), withIntermediateDirectories: true)
        db = try DatabaseQueue(path: folder.appending(path: "Library.storedata").path(percentEncoded: false))
        // Like OpenEmu's own store.
        try db.writeWithoutTransaction { try $0.execute(sql: "PRAGMA journal_mode = WAL") }
        try db.write { db in
            try db.execute(
                sql: """
                    CREATE TABLE Z_METADATA (Z_VERSION INTEGER, Z_UUID VARCHAR, Z_PLIST BLOB);
                    CREATE TABLE ZSYSTEM (Z_PK INTEGER PRIMARY KEY, ZSYSTEMIDENTIFIER VARCHAR UNIQUE);
                    CREATE TABLE ZIMAGE (Z_PK INTEGER PRIMARY KEY, ZRELATIVEPATH VARCHAR);
                    CREATE TABLE ZGAME (Z_PK INTEGER PRIMARY KEY, ZRATING INTEGER, ZBOXIMAGE INTEGER, ZSYSTEM INTEGER,
                        ZGAMETITLE VARCHAR, ZNAME VARCHAR);
                    CREATE TABLE ZROM (Z_PK INTEGER PRIMARY KEY, ZPLAYCOUNT INTEGER, ZGAME INTEGER, ZLASTPLAYED TIMESTAMP,
                        ZPLAYTIME FLOAT, ZLOCATION VARCHAR, ZMD5 VARCHAR);
                    CREATE TABLE ZABSTRACTCOLLECTION (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, ZNAME VARCHAR);
                    -- Entity numbers unlike the real store's (Collection 2, Game 7), so nothing can hardcode them.
                    CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR);
                    INSERT INTO Z_PRIMARYKEY VALUES (3, 'Collection'), (5, 'SmartCollection'), (9, 'Game');
                    CREATE TABLE Z_3GAMES (Z_3COLLECTIONS INTEGER, Z_9GAMES INTEGER);
                    INSERT INTO Z_METADATA VALUES (1, ?, NULL);
                    INSERT INTO ZABSTRACTCOLLECTION VALUES (1000, 5, 'Recently Added');
                    """, arguments: [storeUUID])
        }
    }

    /// Adds a ROM (and its OpenEmu game) and returns its `Z_PK`. `fileName: nil` leaves no file on disk.
    @discardableResult
    func addROM(
        _ name: String, md5: String, system: String = "openemu.system.snes", fileName: String? = "rom.sfc",
        stars: Int = 0, collections: [String] = [], playCount: Int = 0, playTime: Double = 0, lastPlayed: Date? = nil,
        boxArt: Data? = nil, title: String? = nil
    ) throws -> Int64 {
        let pk = nextPK
        nextPK += 1
        let location = "\(system)/\(pk)-\(fileName ?? "missing.sfc")"
        if let fileName {
            let file = folder.appending(path: "roms").appending(path: "\(system)/\(pk)-\(fileName)")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("rom \(pk)".utf8).write(to: file)
        }
        var image: Int64?
        if let boxArt {
            let path = "ART-\(pk)"
            try boxArt.write(to: folder.appending(path: "Artwork").appending(path: path))
            image = pk
            try db.write { try $0.execute(sql: "INSERT INTO ZIMAGE VALUES (?, ?)", arguments: [pk, path]) }
        }
        try db.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO ZSYSTEM (ZSYSTEMIDENTIFIER) VALUES (?)", arguments: [system])
            let systemPK = try Int64.fetchOne(db, sql: "SELECT Z_PK FROM ZSYSTEM WHERE ZSYSTEMIDENTIFIER = ?", arguments: [system])!
            try db.execute(
                sql: "INSERT INTO ZGAME VALUES (?, ?, ?, ?, ?, ?)", arguments: [pk, stars, image, systemPK, title, name])
            try db.execute(
                sql: "INSERT INTO ZROM VALUES (?, ?, ?, ?, ?, ?, ?)",
                arguments: [
                    pk, playCount, pk, lastPlayed?.timeIntervalSinceReferenceDate, playTime,
                    location.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), md5.uppercased(),
                ])
            for collection in collections {
                try db.execute(
                    sql:
                        "INSERT INTO ZABSTRACTCOLLECTION (Z_ENT, ZNAME) SELECT 3, ? WHERE NOT EXISTS (SELECT 1 FROM ZABSTRACTCOLLECTION WHERE ZNAME = ?)",
                    arguments: [collection, collection])
                try db.execute(
                    sql: "INSERT INTO Z_3GAMES SELECT Z_PK, ? FROM ZABSTRACTCOLLECTION WHERE ZNAME = ?", arguments: [pk, collection])
            }
        }
        return pk
    }

    /// Removes a ROM from OpenEmu (row and file), as removing it in OpenEmu would.
    /// OpenEmu's library rebuilt: a new store UUID.
    func replaceStore(uuid: String) throws {
        try db.write { try $0.execute(sql: "UPDATE Z_METADATA SET Z_UUID = ?", arguments: [uuid]) }
    }

    func removeROM(_ pk: Int64) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM ZROM WHERE Z_PK = ?", arguments: [pk])
            try db.execute(sql: "DELETE FROM ZGAME WHERE Z_PK = ?", arguments: [pk])
            try db.execute(sql: "DELETE FROM Z_3GAMES WHERE Z_9GAMES = ?", arguments: [pk])
        }
    }
}
