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

    /// A missing ROM of its Platform it could be, with the name of the Game it's Matched to, if any.
    public struct MissingROM: Sendable, Equatable, Identifiable {
        public let rom: LudeumROM
        public let gameName: String?
        public var id: Int64 { rom.id }
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

    /// The missing ROMs of a Stray file's Platform, which it may be (its file renamed in Finder, or replaced): those whose
    /// names share the most words with its name first, then by name.
    public func missingROMs(for stray: StrayFile) throws -> [StrayFile.MissingROM] {
        let condition = "r.platformId = ? AND r.missing AND r.folderName IS NOT NULL"
        let roms = try roms(where: condition, arguments: [stray.platformId])
        let games = try db.read { db in
            try Row.fetchAll(db, sql: "SELECT id, gameId FROM rom r WHERE \(condition)", arguments: [stray.platformId])
                .reduce(into: [Int64: GameID]()) { $0[$1["id"]] = $1["gameId"] }
        }
        let words = Self.words(stray.name)
        func shared(_ rom: LudeumROM) -> Int { Self.words(rom.folderName).intersection(words).count }
        let likeliest = roms.sorted { a, b in
            let (sharedA, sharedB) = (shared(a), shared(b))
            if sharedA != sharedB { return sharedA > sharedB }
            return a.folderName.localizedStandardCompare(b.folderName) == .orderedAscending
        }
        return try likeliest.map { rom in
            StrayFile.MissingROM(rom: rom, gameName: try games[rom.id].map { try game($0).name })
        }
    }

    private static func words(_ name: String) -> Set<String> {
        Set(name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    /// Gives a missing ROM of its Platform a Stray file as its own: its file renamed in Finder, or replaced. It takes the
    /// file's name, and its Version from it, and stays the same ROM with its Match, Copy details and Playthroughs; its
    /// checksum, its old file's, goes. Refused, with nothing changed, when the ROM isn't missing any more, the file has
    /// left its ROM folder, or another ROM has its name in another case.
    public func giveStrayFile(_ stray: StrayFile, to rom: Int64, in folder: ROMFolder) throws {
        guard folder.platformId == stray.platformId else { throw ReviewError.noROMFolder }
        guard let file = try folder.rom(named: stray.name) else { throw ReviewError.strayFileGone }
        let parsed = ROMName(file.name)
        try db.write { db in
            guard
                try Bool.fetchOne(
                    db, sql: "SELECT missing FROM rom WHERE id = ? AND platformId = ?", arguments: [rom, stray.platformId]) == true
            else { throw ReviewError.notMissing }
            guard
                try Bool.fetchOne(
                    db, sql: "SELECT EXISTS (SELECT 1 FROM rom WHERE platformId = ? AND folderName = ? COLLATE NOCASE)",
                    arguments: [stray.platformId, file.name]) == false
            else { throw ReviewError.alreadyInROMFolder }
            try Self.notStray(db, file.name, on: stray.platformId)
            try db.execute(
                sql: """
                    UPDATE rom SET folderName = ?, name = ?, version = ?, discNumber = ?, discLabel = ?, md5 = NULL, crc = NULL
                    WHERE id = ?
                    """,
                arguments: [file.name, file.name, parsed.version, parsed.disc, parsed.discLabel, rom])
            try Self.setFolderROM(db, rom, to: file)
        }
    }

    /// No Stray file of that name: it's gone from its ROM folder, or a ROM of that name is recorded.
    static func notStray(_ db: Database, _ name: String, on platformId: Int64) throws {
        try db.execute(sql: "DELETE FROM strayFile WHERE platformId = ? AND name = ?", arguments: [platformId, name])
    }
}
