import Foundation
import GRDB

/// A game file in a ROM folder that the journal doesn't have as a ROM (ADR 0017). An Import lists it in the Review queue
/// rather than recording it, until it's Added as a ROM or leaves its ROM folder.
public struct StrayFile: Sendable, Equatable, Identifiable {
    public let id: Int64
    /// The IGDB platform whose ROM folder it's in.
    public let platformId: Int64
    /// The name it would have as a ROM: its file's without the extension, or its subfolder's.
    public let name: String
    /// Its file, as a path in the ROM folder.
    public let fileName: String
    public var key: Key { Key(platformId: platformId, name: name) }

    /// A file in a ROM folder, by its Platform and its name there: as a ROM is known.
    public struct Key: Sendable, Hashable {
        public let platformId: Int64
        public let name: String

        public init(platformId: Int64, name: String) {
            self.platformId = platformId
            self.name = name
        }
    }
}

extension LudeumStore {
    /// Every Stray file, by Platform then name. None in a journal waiting for `migrate-openemu`, which has no table for them.
    func strayFiles() throws -> [StrayFile] {
        try db.read { db in
            guard try db.tableExists("strayFile") else { return [] }
            return try Row.fetchAll(
                db, sql: "SELECT id, platformId, name, fileName FROM strayFile ORDER BY platformId, name COLLATE NOCASE"
            )
            .map { StrayFile(id: $0["id"], platformId: $0["platformId"], name: $0["name"], fileName: $0["fileName"]) }
        }
    }

    /// Puts one ROM folder's Stray files as an Import read them, returning the names of those that weren't Stray files
    /// before. A file recorded as a ROM since the folder was read (by Add ROM) isn't one.
    static func setStrayFiles(_ db: Database, on platformId: Int64, to files: [FolderROMFile]) throws -> [String] {
        let before = Set(try String.fetchAll(db, sql: "SELECT name FROM strayFile WHERE platformId = ?", arguments: [platformId]))
        let roms = Set(
            try String.fetchAll(
                db, sql: "SELECT folderName FROM rom WHERE platformId = ? AND folderName IS NOT NULL", arguments: [platformId]))
        let strays = files.filter { !roms.contains($0.name) }
        let names = Set(strays.map(\.name))
        for name in before.subtracting(names) { try notStray(db, name, on: platformId) }
        var new: [String] = []
        for file in strays {
            try db.execute(
                sql: """
                    INSERT INTO strayFile (platformId, name, fileName) VALUES (?, ?, ?)
                    ON CONFLICT (platformId, name) DO UPDATE SET fileName = excluded.fileName
                    """,
                arguments: [platformId, file.name, file.fileName])
            if !before.contains(file.name) { new.append(file.name) }
        }
        return new
    }

    /// No Stray file of that name: it's gone from its ROM folder, or a ROM of that name is recorded.
    static func notStray(_ db: Database, _ name: String, on platformId: Int64) throws {
        try db.execute(sql: "DELETE FROM strayFile WHERE platformId = ? AND name = ?", arguments: [platformId, name])
    }
}
