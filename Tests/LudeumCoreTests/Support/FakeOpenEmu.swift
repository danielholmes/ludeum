import Foundation
import GRDB

@testable import LudeumCore

/// A small OpenEmu library on disk, as `migrate-openemu` finds it: `Library.storedata` with the Core Data
/// tables it reads, and ROM files under `roms/`. Its Application Support folder, which holds each core's battery saves,
/// is apart from the library, as when the library is moved into Dropbox; `supportLinked` makes it a symlink to a
/// folder elsewhere, as when it's linked into Dropbox too.
final class FakeOpenEmu {
    let folder: URL
    /// OpenEmu's Application Support folder, as `migrate-openemu` is given it.
    let support: URL
    let db: DatabaseQueue
    private var nextPK: Int64 = 1

    init(in parent: URL, supportLinked: Bool = false) throws {
        folder = parent.appending(path: "Dropbox/OpenEmu/Game Library", directoryHint: .isDirectory)
        support = parent.appending(path: "Application Support/OpenEmu", directoryHint: .isDirectory)
        if supportLinked {
            let linked = parent.appending(path: "Dropbox/OpenEmu/Application Support", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: support.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: support, withDestinationURL: linked)
        } else {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }
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
                    CREATE TABLE ZROM (Z_PK INTEGER PRIMARY KEY, ZGAME INTEGER, ZLOCATION VARCHAR, ZMD5 VARCHAR, ZFILENAME VARCHAR);
                    """)
        }
    }

    /// Adds a ROM (and its OpenEmu game) and returns its `Z_PK`. `fileName: nil` leaves no file on disk.
    @discardableResult
    func addROM(_ name: String, md5: String, system: String = "openemu.system.snes", fileName: String? = "rom.sfc") throws -> Int64 {
        let pk = nextPK
        if let fileName { try addFile("\(system)/\(pk)-\(fileName)", "rom \(pk)") }
        return try addROM(name, md5: md5, system: system, location: "\(system)/\(pk)-\(fileName ?? "missing.sfc")")
    }

    /// Adds a ROM's row as OpenEmu records it, at `location` under `roms/` (e.g. "Game Boy/Tetris (World).gb"), with no
    /// file put there. `archiveFileName` is its `ZFILENAME`: the file inside the archive at `location`. Returns its `Z_PK`.
    @discardableResult
    func addROM(_ name: String, md5: String, system: String, location: String, archiveFileName: String? = nil) throws -> Int64 {
        let pk = nextPK
        nextPK += 1
        try db.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO ZSYSTEM (ZSYSTEMIDENTIFIER) VALUES (?)", arguments: [system])
            let systemPK = try Int64.fetchOne(db, sql: "SELECT Z_PK FROM ZSYSTEM WHERE ZSYSTEMIDENTIFIER = ?", arguments: [system])!
            try db.execute(sql: "INSERT INTO ZGAME VALUES (?, ?, ?)", arguments: [pk, systemPK, name])
            try db.execute(
                sql: "INSERT INTO ZROM (Z_PK, ZGAME, ZLOCATION, ZMD5, ZFILENAME) VALUES (?, ?, ?, ?, ?)",
                arguments: [
                    pk, pk, location.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), md5.uppercased(), archiveFileName,
                ])
        }
        return pk
    }

    /// Puts a file at `path` under `roms/`, whether or not a ROM's row names it, and returns it.
    @discardableResult
    func addFile(_ path: String, _ contents: String = "rom") throws -> URL {
        let file = folder.appending(path: "roms").appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: file)
        return file
    }

    /// A core's battery save, in `<Core>/Battery Saves/` in the Application Support folder. Returns its file.
    @discardableResult
    func addBatterySave(core: String, _ name: String) throws -> URL {
        let saves = support.appending(path: "\(core)/Battery Saves", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        let file = saves.appending(path: name)
        try Data("save".utf8).write(to: file)
        return file
    }

    /// Deletes a ROM's row, as removing it in OpenEmu does.
    func removeROM(_ pk: Int64) throws {
        try db.write { try $0.execute(sql: "DELETE FROM ZROM WHERE Z_PK = ?", arguments: [pk]) }
    }
}
