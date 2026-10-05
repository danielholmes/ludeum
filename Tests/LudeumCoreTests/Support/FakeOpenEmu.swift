import Foundation
import GRDB

@testable import LudeumCore

/// A small OpenEmu library on disk: `Library.storedata` with the Core Data tables the journal
/// reads and writes (keeping `Z_PRIMARYKEY.Z_MAX` current, as Core Data does), ROM files under
/// `roms/`, and box art under `Artwork/`.
final class FakeOpenEmu {
    let folder: URL
    let db: DatabaseQueue
    private var nextPK: Int64 = 1

    // Entity numbers unlike the real store's (Collection 2, Game 7, Image 9), so nothing can hardcode them.
    static let abstractCollection = 1
    static let collection = 3
    static let smartCollection = 5
    static let game = 9
    static let image = 10
    static let rom = 11

    init(in parent: URL, storeUUID: String = "STORE-1") throws {
        folder = parent.appending(path: "OpenEmu Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "roms"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appending(path: "Artwork"), withIntermediateDirectories: true)
        db = try DatabaseQueue(path: folder.appending(path: "Library.storedata").path(percentEncoded: false))
        // Like OpenEmu's own store.
        try db.writeWithoutTransaction { try $0.execute(sql: "PRAGMA journal_mode = WAL") }
        // Read-only opens of a WAL store need its -shm file, which this connection keeps alive.
        try db.write { db in
            try db.execute(
                sql: """
                    CREATE TABLE Z_METADATA (Z_VERSION INTEGER, Z_UUID VARCHAR, Z_PLIST BLOB);
                    CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR, Z_SUPER INTEGER, Z_MAX INTEGER);
                    INSERT INTO Z_PRIMARYKEY VALUES
                        (1, 'AbstractCollection', 0, 1000), (3, 'Collection', 1, 0), (4, 'CollectionFolder', 1, 0),
                        (5, 'SmartCollection', 1, 0), (9, 'Game', 0, 0), (10, 'Image', 0, 0), (11, 'ROM', 0, 0), (12, 'System', 0, 0);
                    CREATE TABLE ZSYSTEM (Z_PK INTEGER PRIMARY KEY, ZSYSTEMIDENTIFIER VARCHAR UNIQUE);
                    CREATE TABLE ZIMAGE (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZFORMAT INTEGER, ZBOX INTEGER,
                        ZHEIGHT FLOAT, ZWIDTH FLOAT, ZRELATIVEPATH VARCHAR, ZSOURCE VARCHAR);
                    CREATE TABLE ZGAME (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZRATING INTEGER, ZSTATUS INTEGER,
                        ZBOXIMAGE INTEGER, ZSYSTEM INTEGER, ZGAMETITLE VARCHAR, ZNAME VARCHAR);
                    CREATE TABLE ZROM (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZPLAYCOUNT INTEGER, ZGAME INTEGER,
                        ZLASTPLAYED TIMESTAMP, ZPLAYTIME FLOAT, ZLOCATION VARCHAR, ZMD5 VARCHAR);
                    CREATE TABLE ZABSTRACTCOLLECTION (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZFOLDER INTEGER, ZNAME VARCHAR);
                    CREATE TABLE Z_3GAMES (Z_3COLLECTIONS INTEGER, Z_9GAMES INTEGER, PRIMARY KEY (Z_3COLLECTIONS, Z_9GAMES));
                    INSERT INTO Z_METADATA VALUES (1, ?, NULL);
                    INSERT INTO ZABSTRACTCOLLECTION VALUES (1000, 5, 1, NULL, 'Recently Added');
                    """, arguments: [storeUUID])
        }
    }

    /// Adds a ROM (and its OpenEmu game) and returns its `Z_PK`. `fileName: nil` leaves no file on disk.
    @discardableResult
    func addROM(
        _ name: String, md5: String, system: String = "openemu.system.snes", fileName: String? = "rom.sfc",
        stars: Int = 0, collections: [String] = [],
        boxArt: Data? = nil, title: String? = nil, status: Int = 0
    ) throws -> Int64 {
        let pk = nextPK
        nextPK += 1
        let location = "\(system)/\(pk)-\(fileName ?? "missing.sfc")"
        if let fileName {
            let file = folder.appending(path: "roms").appending(path: "\(system)/\(pk)-\(fileName)")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("rom \(pk)".utf8).write(to: file)
        }
        try db.write { db in
            var image: Int64?
            if let boxArt {
                let path = "ART-\(pk)"
                try boxArt.write(to: folder.appending(path: "Artwork").appending(path: path))
                image = try Self.nextKey(db, root: Self.image)
                try db.execute(
                    sql: "INSERT INTO ZIMAGE VALUES (?, ?, 1, 3, ?, 100, 100, ?, NULL)", arguments: [image, Self.image, pk, path])
            }
            try db.execute(sql: "INSERT OR IGNORE INTO ZSYSTEM (ZSYSTEMIDENTIFIER) VALUES (?)", arguments: [system])
            let systemPK = try Int64.fetchOne(db, sql: "SELECT Z_PK FROM ZSYSTEM WHERE ZSYSTEMIDENTIFIER = ?", arguments: [system])!
            try db.execute(
                sql: "INSERT INTO ZGAME VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?)",
                arguments: [pk, Self.game, stars, status, image, systemPK, title, name])
            try db.execute(
                sql: "INSERT INTO ZROM VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?)",
                arguments: [
                    pk, Self.rom, 0, pk, nil, 0,
                    location.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), md5.uppercased(),
                ])
            try db.execute(
                sql: "UPDATE Z_PRIMARYKEY SET Z_MAX = MAX(Z_MAX, ?) WHERE Z_ENT IN (?, ?)", arguments: [pk, Self.game, Self.rom])
            for collection in collections {
                let id = try collectionPK(db, collection) ?? addCollection(db, collection)
                try db.execute(sql: "INSERT INTO Z_3GAMES VALUES (?, ?)", arguments: [id, pk])
            }
        }
        return pk
    }

    /// A regular collection made in OpenEmu, as Core Data would make it.
    @discardableResult
    func addCollection(_ name: String) throws -> Int64 { try db.write { try addCollection($0, name) } }

    private func addCollection(_ db: Database, _ name: String) throws -> Int64 {
        let pk = try Self.nextKey(db, root: Self.abstractCollection)
        try db.execute(sql: "INSERT INTO ZABSTRACTCOLLECTION VALUES (?, ?, 1, NULL, ?)", arguments: [pk, Self.collection, name])
        return pk
    }

    private func collectionPK(_ db: Database, _ name: String) throws -> Int64? {
        try Int64.fetchOne(
            db, sql: "SELECT Z_PK FROM ZABSTRACTCOLLECTION WHERE ZNAME = ? AND Z_ENT = ?", arguments: [name, Self.collection])
    }

    /// The next key from a root entity's `Z_MAX`, raised as Core Data does.
    static func nextKey(_ db: Database, root: Int) throws -> Int64 {
        try db.execute(sql: "UPDATE Z_PRIMARYKEY SET Z_MAX = Z_MAX + 1 WHERE Z_ENT = ?", arguments: [root])
        return try Int64.fetchOne(db, sql: "SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_ENT = ?", arguments: [root])!
    }

    /// OpenEmu's library rebuilt: a new store UUID.
    func replaceStore(uuid: String) throws {
        try db.write { try $0.execute(sql: "UPDATE Z_METADATA SET Z_UUID = ?", arguments: [uuid]) }
    }

    /// Removes a ROM from OpenEmu (row and file), as removing it in OpenEmu would.
    func removeROM(_ pk: Int64) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM ZROM WHERE Z_PK = ?", arguments: [pk])
            try db.execute(sql: "DELETE FROM ZGAME WHERE Z_PK = ?", arguments: [pk])
            try db.execute(sql: "DELETE FROM Z_3GAMES WHERE Z_9GAMES = ?", arguments: [pk])
        }
    }

    // MARK: Reading back

    func stars(_ game: Int64) throws -> Int {
        try db.read { try Int.fetchOne($0, sql: "SELECT ZRATING FROM ZGAME WHERE Z_PK = ?", arguments: [game])! }
    }

    /// Regular collections by name, with their games' `Z_PK`s.
    func collections() throws -> [String: Set<Int64>] {
        try db.read { db in
            var out: [String: Set<Int64>] = [:]
            for name in try String.fetchAll(db, sql: "SELECT ZNAME FROM ZABSTRACTCOLLECTION WHERE Z_ENT = ?", arguments: [Self.collection])
            {
                out[name] = []
            }
            for row in try Row.fetchAll(
                db, sql: "SELECT c.ZNAME, j.Z_9GAMES FROM Z_3GAMES j JOIN ZABSTRACTCOLLECTION c ON c.Z_PK = j.Z_3COLLECTIONS")
            {
                out[row[0], default: []].insert(row[1])
            }
            return out
        }
    }
}
