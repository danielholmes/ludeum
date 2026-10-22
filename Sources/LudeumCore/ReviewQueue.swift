import Foundation
import GRDB

/// An unmatched ROM in the Review queue, with its stored suggestion.
public struct ReviewItem: Sendable, Equatable, Identifiable {
    public let romId: Int64
    /// The ROM's name.
    public let romName: String
    /// The IGDB platform it's on: its ROM folder's.
    public let platformId: Int64
    public let missing: Bool
    public let suggestedIgdbGameId: Int64?
    /// Where the suggestion came from: the checksum (or a related record of it), or a name search.
    public let suggestionKind: SuggestionKind?
    /// For a related-record suggestion, the checksum's own game, shown crossed out.
    public let checksumIgdbGameId: Int64?
    public let namesAgree: Bool
    public var id: Int64 { romId }

    public enum SuggestionKind: String, Sendable {
        case checksum, name
    }
}

/// A Game with two or more present ROMs that aren't Discs of one Version.
public struct DuplicateVersionsGame: Sendable, Equatable, Identifiable {
    public let game: Game
    /// Its present ROMs.
    public let roms: [LudeumROM]
    public var id: GameID { game.id }
    /// Its present ROMs grouped into Versions, in the order given: a multi-disc Version's Discs (and playlist) together,
    /// any other ROM alone. Keep only this Version and Split into its own Game each take one.
    public var versions: [[LudeumROM]] {
        LudeumCore.versions(of: roms.map(gameROM)).map { version in version.compactMap { rom in roms.first { $0.id == rom.id } } }
    }
}

/// A Game whose ROMs are all missing: it can't be Played until a file comes back, or I delete it.
public struct MissingROMsGame: Sendable, Equatable, Identifiable {
    public let game: Game
    /// Its ROMs, all missing.
    public let roms: [LudeumROM]
    public var id: GameID { game.id }
}

/// A Game that still has a present ROM, with missing ones left over (a file renamed or replaced, then Added as a new
/// ROM): I delete them, or put a file back.
public struct OldMissingROMsGame: Sendable, Equatable, Identifiable {
    public let game: Game
    public let missing: [LudeumROM]
    /// What it still has, to set the missing ones against.
    public let present: [LudeumROM]
    public var id: GameID { game.id }
}

/// A present ROM kept in both forms at once: a Playable copy beside its Archived `.7z`, or a loose file beside its
/// Compacted copy. Keep the Playable copy (or Keep the Compacted copy) sends the other to the Trash.
public struct BothFormsROM: Sendable, Equatable, Identifiable {
    public let rom: LudeumROM
    /// Its Game, once it's Matched.
    public let game: GameID?
    public var id: Int64 { rom.id }
}

/// A present ROM on a Platform whose Emulator opens an archive, not yet Compacted into it: a loose file, or a `.7z` ares
/// can't open.
public struct NotCompactedROM: Sendable, Equatable, Identifiable {
    public let rom: LudeumROM
    /// What Compact makes of it, e.g. `Tetris (World).7z`.
    public let compactFileName: String
    /// Its Game, once it's Matched.
    public let game: GameID?
    public var id: Int64 { rom.id }
}

/// Everything waiting in the Review queue, by kind.
public struct ReviewQueueItems: Sendable, Equatable {
    /// Every unmatched ROM, each with its suggestion if it has one.
    public var unmatched: [ReviewItem] = []
    public var duplicateVersions: [DuplicateVersionsGame] = []
    public var missingROMs: [MissingROMsGame] = []
    public var oldMissingROMs: [OldMissingROMsGame] = []
    public var bothForms: [BothFormsROM] = []
    public var notCompacted: [NotCompactedROM] = []
    /// Attachments whose files are missing: Locate or Delete each.
    public var missingAttachments: [MissingAttachment] = []
    /// Files in ROM folders that aren't ROMs (ADR 0017): Add each as a ROM, or take it out of its folder.
    public var strayFiles: [StrayFile] = []

    public init() {}

    /// The sidebar badge.
    public var count: Int {
        unmatched.count + duplicateVersions.count + missingROMs.count + oldMissingROMs.count + bothForms.count
            + notCompacted.count + missingAttachments.count + strayFiles.count
    }
}

extension LudeumStore {
    public func reviewQueue() throws -> ReviewQueueItems {
        var items = ReviewQueueItems()
        let rows = try db.read { db in
            try Row.fetchAll(
                db,
                sql:
                    "SELECT *, COALESCE(name, fileName) AS displayName FROM rom WHERE gameId IS NULL ORDER BY displayName COLLATE NOCASE, id"
            )
        }
        items.unmatched = rows.map { row in
            ReviewItem(
                romId: row["id"], romName: row["displayName"], platformId: row["platformId"], missing: row["missing"],
                suggestedIgdbGameId: row["suggestedIgdbGameId"],
                suggestionKind: (row["suggestionKind"] as String?).flatMap(ReviewItem.SuggestionKind.init(rawValue:)),
                checksumIgdbGameId: row["checksumIgdbGameId"], namesAgree: row["namesAgree"] ?? false)
        }
        // Only a Game with two present ROMs or more can have Duplicate Versions, so the rest aren't read one by one.
        let games = try db.read { db in
            try GameID.fetchAll(
                db, sql: "SELECT gameId FROM rom WHERE gameId IS NOT NULL AND NOT missing GROUP BY gameId HAVING COUNT(*) > 1")
        }
        for game in games {
            let roms = try roms(of: game)
            if hasDuplicateVersions(roms.map(gameROM)) {
                items.duplicateVersions.append(DuplicateVersionsGame(game: try self.game(game), roms: roms.filter { !$0.missing }))
            }
        }
        items.duplicateVersions.sort { $0.game.name.localizedStandardCompare($1.game.name) == .orderedAscending }
        let missing = try db.read { db in
            try GameID.fetchAll(db, sql: "SELECT DISTINCT gameId FROM rom WHERE gameId IS NOT NULL AND missing")
        }
        for id in missing {
            let roms = try roms(of: id)
            let game = try self.game(id)
            let present = roms.filter { !$0.missing }
            if present.isEmpty {
                items.missingROMs.append(MissingROMsGame(game: game, roms: roms))
            } else {
                items.oldMissingROMs.append(OldMissingROMsGame(game: game, missing: roms.filter(\.missing), present: present))
            }
        }
        items.missingROMs.sort { $0.game.name.localizedStandardCompare($1.game.name) == .orderedAscending }
        items.oldMissingROMs.sort { $0.game.name.localizedStandardCompare($1.game.name) == .orderedAscending }
        items.bothForms = try bothForms()
        items.notCompacted = try notCompacted()
        items.missingAttachments = try missingAttachments()
        items.strayFiles = try strayFiles()
        return items
    }

    /// Present ROMs the last read of their ROM folder found in both forms, Matched or not, by name.
    private func bothForms() throws -> [BothFormsROM] {
        // A journal waiting for `migrate-openemu` is held before `rom.inBothForms`.
        guard try db.read({ db in try db.columns(in: "rom").contains { $0.name == "inBothForms" } }) else { return [] }
        return try presentFolderROMs(where: "inBothForms").map { BothFormsROM(rom: $0.rom, game: $0.game) }
    }

    /// Present ROM folder ROMs that can be Compacted, Matched or not, by name.
    private func notCompacted() throws -> [NotCompactedROM] {
        let platforms = ROMPlatform.all.filter { $0.value.compactExtension != nil }.keys.map(String.init).joined(separator: ", ")
        return try presentFolderROMs(where: "platformId IN (\(platforms))").compactMap { rom, game in
            ROMArchiving.compactFileName(for: rom).map { NotCompactedROM(rom: rom, compactFileName: $0, game: game) }
        }
    }

    /// Present ROM folder ROMs matching the SQL condition, each with its Game once it's Matched, by name.
    private func presentFolderROMs(where condition: String) throws -> [(rom: LudeumROM, game: GameID?)] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, folderName, platformId, archived, fileName, COALESCE(name, fileName) AS displayName, version,
                        discNumber, gameId
                    FROM rom
                    WHERE folderName IS NOT NULL AND NOT missing AND \(condition)
                    ORDER BY displayName COLLATE NOCASE, id
                    """
            )
            .map { row in
                let fileName: String = row["fileName"]
                let parsed = ROMName((fileName as NSString).deletingPathExtension)
                let rom = LudeumROM(
                    id: row["id"], folderName: row["folderName"], platformId: row["platformId"], fileName: fileName,
                    name: row["displayName"], version: row["version"] ?? parsed.version, disc: row["discNumber"] ?? parsed.disc,
                    missing: false, archived: row["archived"])
                return (rom, row["gameId"])
            }
        }
    }

    /// Whether Matching this ROM to the Game would give it Duplicate Versions. It warns, never blocks.
    public func wouldHaveDuplicateVersions(_ game: GameID, adding rom: Int64) throws -> Bool {
        guard
            let item = try db.read({ db in
                try Row.fetchOne(
                    db, sql: "SELECT fileName, COALESCE(name, fileName) AS displayName, missing FROM rom WHERE id = ?", arguments: [rom])
            })
        else { return false }
        let added = GameROM(id: Int(rom), name: item["displayName"], isPlaylist: isPlaylist(item["fileName"]), isPresent: !item["missing"])
        return hasDuplicateVersions(try roms(of: game).map(gameROM) + [added])
    }

    /// Keep the Playable copy, or Keep the Compacted copy: sends every copy of a ROM kept in both forms to the Trash but
    /// the one `forms` keeps, then reads the ROM again. `forms` is what I was shown: when its ROM folder no longer has it
    /// that way it throws, with nothing sent to the Trash, and the ROM is read again all the same.
    public func keepOneForm(
        _ item: BothFormsROM, as forms: BothForms, romFolders: [ROMFolder],
        moveToTrash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) throws {
        guard let folder = romFolders.first(where: { $0.platformId == item.rom.platformId }) else { throw ReviewError.noROMFolder }
        guard try folder.bothForms(named: item.rom.folderName) == forms else {
            try checkROMAgain(item.id, in: folder)
            throw ReviewError.bothFormsChanged
        }
        // Whatever reached the Trash before a failure, the journal sees what's left.
        defer { try? checkROMAgain(item.id, in: folder) }
        for copy in forms.trash { try moveToTrash(copy) }
    }

    /// Split into its own Game: the Version's ROMs leave the Game unmatched, to be Matched again from the Review queue
    /// (e.g. to IGDB's own listing of an enhanced re-release). The Game keeps its journal data and its other Versions.
    /// Throws, changing nothing, when the Game's Versions aren't the ones shown, or a Playthrough was played on one of the
    /// Version's ROMs.
    public func splitOff(_ version: [LudeumROM], from item: DuplicateVersionsGame) throws {
        try checkVersionsUnchanged(version, of: item)
        try db.write { db in
            try Self.checkNotPlayedOn(db, roms: version.map(\.id))
            for rom in version {
                try db.execute(
                    sql: "UPDATE rom SET gameId = NULL, matchKind = NULL, matchedAt = NULL WHERE id = ? AND gameId = ?",
                    arguments: [rom.id, item.game.id])
                guard db.changesCount == 1 else { throw ReviewError.duplicateVersionsChanged }
            }
        }
    }

    /// Keep only this Version: sends the other Versions' ROMs to the Trash and deletes them, so the Game is left with this
    /// one. Everything is checked before anything moves: when the Game's Versions aren't the ones shown, or a ROM's files
    /// aren't in its ROM folder, or a Playthrough was played on one of them, it throws with nothing sent to the Trash.
    public func keepOnly(
        _ version: [LudeumROM], of item: DuplicateVersionsGame, romFolders: [ROMFolder],
        moveToTrash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) throws {
        try checkVersionsUnchanged(version, of: item)
        let kept = Set(version.map(\.id))
        try db.read { db in try Self.checkNotPlayedOn(db, roms: item.roms.map(\.id).filter { !kept.contains($0) }) }
        let trashing = try item.roms.filter { !kept.contains($0.id) }.map { rom in
            guard let folder = romFolders.first(where: { $0.platformId == rom.platformId }) else { throw ReviewError.noROMFolder }
            guard let file = try folder.rom(named: rom.folderName) else { throw ReviewError.romFilesNotFound }
            return (rom: rom, folder: folder, items: try folder.trashItems(of: file))
        }
        // A playlist ROM's files include its Discs, which are ROMs of their own.
        var trashed: Set<URL> = []
        for (i, (rom, _, items)) in trashing.enumerated() {
            do {
                for item in items where !trashed.contains(item) {
                    try moveToTrash(item)
                    trashed.insert(item)
                }
            } catch {
                // Whatever reached the Trash before the failure (a playlist's Discs among it), the journal sees what's left.
                for (rom, folder, _) in trashing[i...] {
                    try? checkROMAgain(rom.id, in: folder)
                    // One whose files all reached the Trash is deleted, as it would have been.
                    try? db.write { db in try db.execute(sql: "DELETE FROM rom WHERE id = ? AND missing", arguments: [rom.id]) }
                }
                throw error
            }
            try db.write { db in try db.execute(sql: "DELETE FROM rom WHERE id = ?", arguments: [rom.id]) }
        }
    }

    /// Delete ROM: sends an unmatched ROM's files to the Trash and deletes it, as `deleteROM(_:romFolders:)` does any
    /// ROM. Refused, with nothing sent to the Trash, once it's Matched: it's deleted from its Game then.
    public func deleteROM(
        _ item: ReviewItem, romFolders: [ROMFolder],
        moveToTrash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) throws {
        let matched = try db.read { db in
            try Bool.fetchOne(db, sql: "SELECT gameId IS NOT NULL FROM rom WHERE id = ?", arguments: [item.romId])
        }
        guard matched != true else { throw ReviewError.alreadyMatched }
        try deleteROM(item.romId, romFolders: romFolders, moveToTrash: moveToTrash)
    }

    /// Throws unless the Game's present ROMs are still the ones shown, and `version` is one of their Versions.
    private func checkVersionsUnchanged(_ version: [LudeumROM], of item: DuplicateVersionsGame) throws {
        let present = try roms(of: item.game.id).filter { !$0.missing }.map(\.id)
        guard Set(present) == Set(item.roms.map(\.id)), item.versions.contains(where: { $0.map(\.id) == version.map(\.id) })
        else { throw ReviewError.duplicateVersionsChanged }
    }

    /// Assign to Game…: Matches the ROM to an existing Game by hand.
    public func assign(_ item: ReviewItem, to game: GameID) throws {
        try db.write { db in try Self.match(db, rom: item.romId, to: game, kind: "manual", day: today(), now: clock.now()) }
    }

    /// Make by hand…: a new Game with no IGDB link, Matched to the ROM.
    @discardableResult
    public func makeByHand(_ item: ReviewItem, name: String, platform: IGDBPlatform) throws -> GameID {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LudeumError.nameRequired }
        return try db.write { db in
            try db.execute(
                sql: "INSERT INTO platform (id, name) VALUES (?, ?) ON CONFLICT (id) DO NOTHING", arguments: [platform.id, platform.name])
            try db.execute(sql: "INSERT INTO game (platformId, name) VALUES (?, ?)", arguments: [platform.id, name])
            let game = db.lastInsertedRowID
            try Self.match(db, rom: item.romId, to: game, kind: "manual", day: today(), now: clock.now())
            return game
        }
    }

    /// Matches the ROM to the Game with that IGDB link on that Platform, creating the Game if needed.
    func match(_ item: ReviewItem, igdbGameId: Int64, igdbName: String, platform: IGDBPlatform, kind: String) throws -> GameID {
        try db.write { db in
            try db.execute(
                sql: "INSERT INTO platform (id, name) VALUES (?, ?) ON CONFLICT (id) DO NOTHING", arguments: [platform.id, platform.name])
            return try Self.matchToIGDBGame(
                db, rom: item.romId, romName: item.romName, igdbGameId: igdbGameId, igdbName: igdbName, platformId: platform.id,
                kind: kind, day: today(), now: clock.now())
        }
    }

    /// Matches the ROM to the Game with that IGDB link on its Platform, creating the Game (named after the ROM) if needed:
    /// a Review queue answer, or an Import's Automatic Match. The Platform must be in the journal.
    static func matchToIGDBGame(
        _ db: Database, rom: Int64, romName: String, igdbGameId: Int64, igdbName: String, platformId: Int64, kind: String,
        day: String, now: Date
    ) throws -> GameID {
        let game: GameID
        if let existing = try GameID.fetchOne(
            db, sql: "SELECT id FROM game WHERE igdbGameId = ? AND platformId = ?", arguments: [igdbGameId, platformId])
        {
            game = existing
        } else {
            try db.execute(
                sql: "INSERT INTO game (platformId, name, igdbGameId, igdbName) VALUES (?, ?, ?, ?)",
                arguments: [platformId, cleanName(romName), igdbGameId, igdbName])
            game = db.lastInsertedRowID
        }
        try match(db, rom: rom, to: game, kind: kind, day: day, now: now)
        return game
    }

    /// Sets the ROM's Match and clears its suggestion.
    static func match(_ db: Database, rom: Int64, to game: GameID, kind: String, day: String, now: Date) throws {
        try db.execute(
            sql: """
                UPDATE rom SET gameId = ?, matchKind = ?, matchedAt = ?,
                    suggestedIgdbGameId = NULL, suggestionKind = NULL, checksumIgdbGameId = NULL, namesAgree = NULL
                WHERE id = ? AND gameId IS NULL
                """, arguments: [game, kind, now, rom])
        guard db.changesCount == 1 else { throw ReviewError.alreadyMatched }
    }
}

public enum ReviewError: Error, Equatable {
    /// The item was answered already (e.g. twice from the UI).
    case alreadyMatched
    /// IGDB doesn't know the suggested game any more.
    case suggestionGone
    /// For a Rename, or a Stray file given to a missing ROM, the ROM's Platform already has another ROM by that name (in
    /// any case), or a file where one of its files would go.
    case alreadyInROMFolder
    /// The ROM is present, but its files aren't in its ROM folder (or the folder can't be read).
    case romFilesNotFound
    /// The ROM's Platform has no ROM folder.
    case noROMFolder
    /// The ROM's copies aren't the ones shown when I chose which to keep: one gone, or another added meanwhile.
    case bothFormsChanged
    /// The Game's present ROMs aren't the ones shown when I chose a Version: one Split off, gone, or added meanwhile.
    case duplicateVersionsChanged
    /// A missing ROM given a Stray file has its own file back already.
    case notMissing
    /// The Stray file has left its ROM folder since it was listed.
    case strayFileGone
}

private func gameROM(_ rom: LudeumROM) -> GameROM {
    GameROM(id: Int(rom.id), name: rom.name, isPlaylist: isPlaylist(rom.fileName), isPresent: !rom.missing)
}

private func isPlaylist(_ fileName: String) -> Bool { (fileName as NSString).pathExtension.lowercased() == "m3u" }

/// Answering Review queue items with IGDB: confirming suggestions and choosing search results.
public struct ReviewQueue: Sendable {
    let journal: LudeumStore
    let igdb: IGDBClient

    public init(journal: LudeumStore, igdb: IGDBClient) {
        self.journal = journal
        self.igdb = igdb
    }

    /// Confirm: Matches the ROM to its suggestion, on the ROM's Platform.
    @discardableResult
    public func confirm(_ item: ReviewItem) async throws -> GameID {
        guard let suggested = item.suggestedIgdbGameId else { throw ReviewError.suggestionGone }
        guard let record = try await igdb.games(ids: [Int(suggested)])[Int(suggested)] else { throw ReviewError.suggestionGone }
        return try journal.match(
            item, igdbGameId: suggested, igdbName: record.name ?? cleanName(item.romName), platform: try await platform(item.platformId),
            kind: "confirmed")
    }

    /// Whether confirming would give an existing Game Duplicate Versions. It warns, never blocks.
    public func confirmWouldGiveDuplicateVersions(_ item: ReviewItem) async throws -> Bool {
        guard let suggested = item.suggestedIgdbGameId, let game = try journal.gameID(igdbGameId: suggested, platformId: item.platformId)
        else { return false }
        return try journal.wouldHaveDuplicateVersions(game, adding: item.romId)
    }

    /// A result from Search IGDB…: a manual Match.
    @discardableResult
    public func choose(_ item: ReviewItem, igdbGameId: Int64, name: String, platform: IGDBPlatform) async throws -> GameID {
        try journal.match(item, igdbGameId: igdbGameId, igdbName: name, platform: platform, kind: "manual")
    }

    private func platform(_ id: Int64) async throws -> IGDBPlatform {
        if let known = try journal.platform(id) { return known }
        return try await igdb.platforms().first { $0.id == id } ?? IGDBPlatform(id: id, name: "Platform \(id)")
    }
}
