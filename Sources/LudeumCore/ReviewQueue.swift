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
    /// The Platforms Confirm offers: the ROM's, and its siblings (Game Boy and Game Boy Color, NES and Famicom,
    /// SNES and Super Famicom). Choosing another moves the ROM into that Platform's ROM folder.
    public var platformChoices: [Int64] { ROMPlatform.siblings(of: platformId) }

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

/// A Game that still has a present ROM, with missing ones left over (a file renamed or replaced, which Import found
/// as a new ROM): I forget them, or put a file back.
public struct OldMissingROMsGame: Sendable, Equatable, Identifiable {
    public let game: Game
    public let missing: [LudeumROM]
    /// What it still has, to set the missing ones against.
    public let present: [LudeumROM]
    public var id: GameID { game.id }
}

/// A ROM whose subfolder holds its Discs but no playlist, so Play can't open them all: Make playlist writes one.
public struct NoPlaylistItem: Sendable, Equatable, Identifiable {
    public let romId: Int64
    /// The ROM's name: its subfolder's.
    public let romName: String
    public let platformId: Int64
    public var id: Int64 { romId }
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
    /// Name and related-record suggestions whose names agree: bulk-confirmable.
    public var namesAgree: [ReviewItem] = []
    public var checksumSuggestions: [ReviewItem] = []
    public var nameSuggestions: [ReviewItem] = []
    public var noSuggestion: [ReviewItem] = []
    public var duplicateVersions: [DuplicateVersionsGame] = []
    public var missingROMs: [MissingROMsGame] = []
    public var oldMissingROMs: [OldMissingROMsGame] = []
    public var noPlaylist: [NoPlaylistItem] = []
    public var bothForms: [BothFormsROM] = []
    /// Bulk-compactable.
    public var notCompacted: [NotCompactedROM] = []

    public init() {}

    /// The sidebar badge.
    public var count: Int {
        namesAgree.count + checksumSuggestions.count + nameSuggestions.count + noSuggestion.count + duplicateVersions.count
            + noPlaylist.count + missingROMs.count + oldMissingROMs.count + bothForms.count + notCompacted.count
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
        for row in rows {
            let item = ReviewItem(
                romId: row["id"], romName: row["displayName"], platformId: row["platformId"], missing: row["missing"],
                suggestedIgdbGameId: row["suggestedIgdbGameId"],
                suggestionKind: (row["suggestionKind"] as String?).flatMap(ReviewItem.SuggestionKind.init(rawValue:)),
                checksumIgdbGameId: row["checksumIgdbGameId"], namesAgree: row["namesAgree"] ?? false)
            switch (item.suggestedIgdbGameId, item.suggestionKind, item.namesAgree) {
            case (nil, _, _): items.noSuggestion.append(item)
            case (_, _, true): items.namesAgree.append(item)
            case (_, .checksum, _): items.checksumSuggestions.append(item)
            default: items.nameSuggestions.append(item)
            }
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
        items.noPlaylist = try db.read { db in
            guard try Self.hasNeedsPlaylist(db) else { return [] }
            return try Row.fetchAll(
                db,
                sql: "SELECT id, folderName, platformId FROM rom WHERE needsPlaylist AND NOT missing ORDER BY folderName COLLATE NOCASE, id"
            )
            .map { NoPlaylistItem(romId: $0["id"], romName: $0["folderName"], platformId: $0["platformId"]) }
        }
        items.bothForms = try bothForms()
        items.notCompacted = try notCompacted()
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

    /// Make playlist: writes `<ROM name>.m3u` into the ROM's subfolder, naming its Discs in order, so Play opens them all.
    /// Throws, writing nothing, when its folder no longer has Discs without a playlist.
    public func makePlaylist(_ item: NoPlaylistItem, romFolders: [ROMFolder]) throws {
        guard let folder = romFolders.first(where: { $0.platformId == item.platformId }) else { throw ReviewError.noROMFolder }
        let discs = try folder.discsWithoutPlaylist(named: item.romName)
        guard !discs.isEmpty else { throw ReviewError.noDiscsWithoutPlaylist }
        let subfolder = folder.url.appending(path: item.romName, directoryHint: .isDirectory).standardizedFileURL
        let lines = discs.map { $0.standardizedFileURL.pathComponents.dropFirst(subfolder.pathComponents.count).joined(separator: "/") }
        let playlist = subfolder.appending(path: "\(item.romName).m3u", directoryHint: .notDirectory)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: playlist, options: .withoutOverwriting)
        let file = try folder.rom(named: item.romName)
        try db.write { db in try Self.setFolderROM(db, item.romId, to: file) }
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
    /// Throws, changing nothing, when the Game's Versions aren't the ones shown.
    public func splitOff(_ version: [LudeumROM], from item: DuplicateVersionsGame) throws {
        try checkVersionsUnchanged(version, of: item)
        try db.write { db in
            for rom in version {
                try db.execute(
                    sql: "UPDATE rom SET gameId = NULL, matchKind = NULL, matchedAt = NULL WHERE id = ? AND gameId = ?",
                    arguments: [rom.id, item.game.id])
                guard db.changesCount == 1 else { throw ReviewError.duplicateVersionsChanged }
            }
        }
    }

    /// Keep only this Version: sends the other Versions' ROMs to the Trash and forgets them, so the Game is left with this
    /// one. Everything is checked before anything moves: when the Game's Versions aren't the ones shown, or a ROM's files
    /// aren't in its ROM folder, it throws with nothing sent to the Trash.
    public func keepOnly(
        _ version: [LudeumROM], of item: DuplicateVersionsGame, romFolders: [ROMFolder],
        moveToTrash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) throws {
        try checkVersionsUnchanged(version, of: item)
        let kept = Set(version.map(\.id))
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
                    // One whose files all reached the Trash is forgotten, as it would have been.
                    try? db.write { db in try db.execute(sql: "DELETE FROM rom WHERE id = ? AND missing", arguments: [rom.id]) }
                }
                throw error
            }
            try db.write { db in try db.execute(sql: "DELETE FROM rom WHERE id = ?", arguments: [rom.id]) }
        }
    }

    /// Delete ROM: sends an unmatched ROM's files to the Trash and forgets it. A missing one is just forgotten. Refused,
    /// with nothing sent to the Trash, once it's Matched, or when it's present but its files aren't in its ROM folder.
    public func deleteROM(
        _ item: ReviewItem, romFolders: [ROMFolder],
        moveToTrash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) throws {
        guard
            let row = try db.read({ db in
                try Row.fetchOne(db, sql: "SELECT folderName, missing, gameId FROM rom WHERE id = ?", arguments: [item.romId])
            })
        else { return }
        guard row["gameId"] as GameID? == nil else { throw ReviewError.alreadyMatched }
        let forget = {
            try self.db.write { db in try db.execute(sql: "DELETE FROM rom WHERE id = ? AND gameId IS NULL", arguments: [item.romId]) }
        }
        if row["missing"] { return try forget() }
        guard let folder = romFolders.first(where: { $0.platformId == item.platformId }) else { throw ReviewError.noROMFolder }
        guard let file = try folder.rom(named: row["folderName"]) else { throw ReviewError.romFilesNotFound }
        do {
            for trashed in try folder.trashItems(of: file) { try moveToTrash(trashed) }
        } catch {
            // Whatever reached the Trash before the failure, the journal sees what's left; all of it there, it's forgotten.
            try? checkROMAgain(item.romId, in: folder)
            try? db.write { db in try db.execute(sql: "DELETE FROM rom WHERE id = ? AND missing", arguments: [item.romId]) }
            throw error
        }
        try forget()
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

    /// Matches the ROM to the Game with that IGDB link on that Platform, creating the Game if needed. With `romMove`,
    /// the ROM goes to the Platform too: its files move first, and move back if the Match then fails.
    func match(
        _ item: ReviewItem, igdbGameId: Int64, igdbName: String, platform: IGDBPlatform, kind: String, romMove: ROMMove? = nil
    ) throws -> GameID {
        try romMove?.run()
        do {
            return try db.write { db in
                try db.execute(
                    sql: "INSERT INTO platform (id, name) VALUES (?, ?) ON CONFLICT (id) DO NOTHING",
                    arguments: [platform.id, platform.name])
                if romMove != nil {
                    try db.execute(sql: "UPDATE rom SET platformId = ? WHERE id = ?", arguments: [platform.id, item.romId])
                }
                return try Self.matchToIGDBGame(
                    db, rom: item.romId, romName: item.romName, igdbGameId: igdbGameId, igdbName: igdbName, platformId: platform.id,
                    kind: kind, day: today(), now: clock.now())
            }
        } catch {
            romMove?.undo()
            throw error
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

    /// Plans moving a ROM to a sibling Platform. A missing ROM, or one still OpenEmu's, has no files here to move, so
    /// only its Platform changes. Throws, with nothing touched, when the ROM can't go there.
    func romMove(_ item: ReviewItem, to platformId: Int64, romFolders: [ROMFolder]) throws -> ROMMove {
        let row = try db.read { db in
            try Row.fetchOne(db, sql: "SELECT folderName, missing FROM rom WHERE id = ?", arguments: [item.romId])
        }
        guard let row, let name = row["folderName"] as String? else { return ROMMove(moves: []) }
        let taken = try db.read { db in
            try Bool.fetchOne(
                db, sql: "SELECT EXISTS (SELECT 1 FROM rom WHERE platformId = ? AND folderName = ?)", arguments: [platformId, name])!
        }
        if taken { throw ReviewError.alreadyInROMFolder }
        if row["missing"] { return ROMMove(moves: []) }
        guard let from = romFolders.first(where: { $0.platformId == item.platformId }),
            let to = romFolders.first(where: { $0.platformId == platformId })
        else { throw ReviewError.noROMFolder }
        return try ROMMove.plan(name, from: from, to: to)
    }

    /// Sets the ROM's Match, clears its suggestion, and applies any OpenEmu data held for it since the first Import.
    static func match(_ db: Database, rom: Int64, to game: GameID, kind: String, day: String, now: Date) throws {
        try db.execute(
            sql: """
                UPDATE rom SET gameId = ?, matchKind = ?, matchedAt = ?,
                    suggestedIgdbGameId = NULL, suggestionKind = NULL, checksumIgdbGameId = NULL, namesAgree = NULL
                WHERE id = ? AND gameId IS NULL
                """, arguments: [game, kind, now, rom])
        guard db.changesCount == 1 else { throw ReviewError.alreadyMatched }
        if let held = try Row.fetchOne(db, sql: "SELECT * FROM heldOpenEmuData WHERE romId = ?", arguments: [rom]) {
            let collections = (try? JSONDecoder().decode([String].self, from: Data((held["collections"] as String).utf8))) ?? []
            try applyOpenEmuData(
                db, game: game, collections: Set(collections),
                start: (held["currentStart"] as String?).flatMap(PartialDate.init))
            try db.execute(sql: "DELETE FROM heldOpenEmuData WHERE romId = ?", arguments: [rom])
        }
    }
}

public enum ReviewError: Error, Equatable {
    /// The item was answered already (e.g. twice from the UI).
    case alreadyMatched
    /// IGDB doesn't know the suggested game any more.
    case suggestionGone
    /// Confirm offers only the ROM's Platform and its siblings.
    case notASiblingPlatform
    /// The sibling Platform (or, for a Rename, the ROM's own) already has a ROM by that name, or a file where one of its
    /// files would go.
    case alreadyInROMFolder
    /// The ROM is present, but its files aren't in its ROM folder (or the folder can't be read).
    case romFilesNotFound
    /// The ROM's Platform, or the sibling, has no ROM folder.
    case noROMFolder
    /// The sibling's ROM folder doesn't read the ROM's file type.
    case siblingWontReadFile
    /// Make playlist found no Discs without a playlist in the ROM's subfolder: gone, or given one meanwhile.
    case noDiscsWithoutPlaylist
    /// The ROM's copies aren't the ones shown when I chose which to keep: one gone, or another added meanwhile.
    case bothFormsChanged
    /// The Game's present ROMs aren't the ones shown when I chose a Version: one Split off, gone, or added meanwhile.
    case duplicateVersionsChanged
}

private func gameROM(_ rom: LudeumROM) -> GameROM {
    GameROM(id: Int(rom.id), name: rom.name, isPlaylist: isPlaylist(rom.fileName), isPresent: !rom.missing)
}

private func isPlaylist(_ fileName: String) -> Bool { (fileName as NSString).pathExtension.lowercased() == "m3u" }

/// Answering Review queue items with IGDB: confirming suggestions and choosing search results.
public struct ReviewQueue: Sendable {
    let journal: LudeumStore
    let igdb: IGDBClient
    let romFolders: [ROMFolder]

    /// `romFolders` are where Confirm on a sibling Platform moves a ROM's files from and to.
    public init(journal: LudeumStore, igdb: IGDBClient, romFolders: [ROMFolder] = []) {
        self.journal = journal
        self.igdb = igdb
        self.romFolders = romFolders
    }

    /// Confirm: Matches the ROM to its suggestion, on the ROM's Platform or one of its siblings (`platformChoices`).
    /// On a sibling, the ROM moves there too: into its ROM folder when present, only in the journal when missing or
    /// still OpenEmu's.
    @discardableResult
    public func confirm(_ item: ReviewItem, on platformId: Int64? = nil) async throws -> GameID {
        let platformId = platformId ?? item.platformId
        guard item.platformChoices.contains(platformId) else { throw ReviewError.notASiblingPlatform }
        guard let suggested = item.suggestedIgdbGameId else { throw ReviewError.suggestionGone }
        guard let record = try await igdb.games(ids: [Int(suggested)])[Int(suggested)] else { throw ReviewError.suggestionGone }
        let romMove = platformId == item.platformId ? nil : try journal.romMove(item, to: platformId, romFolders: romFolders)
        let platform = try await platform(platformId)
        return try journal.match(
            item, igdbGameId: suggested, igdbName: record.name ?? cleanName(item.romName), platform: platform, kind: "confirmed",
            romMove: romMove)
    }

    /// Whether confirming on that Platform would give an existing Game Duplicate Versions. It warns, never blocks.
    public func confirmWouldGiveDuplicateVersions(_ item: ReviewItem, on platformId: Int64? = nil) async throws -> Bool {
        guard let suggested = item.suggestedIgdbGameId,
            let game = try journal.gameID(igdbGameId: suggested, platformId: platformId ?? item.platformId)
        else { return false }
        return try journal.wouldHaveDuplicateVersions(game, adding: item.romId)
    }

    /// Confirm all: every item whose names agree, skipping any answered meanwhile. Returns how many it confirmed.
    public func confirmAll() async throws -> Int {
        let items = try journal.reviewQueue().namesAgree
        _ = try await igdb.games(ids: items.compactMap(\.suggestedIgdbGameId).map(Int.init))  // one batch, then cached
        var confirmed = 0
        for item in items {
            do {
                try await confirm(item)
                confirmed += 1
            } catch ReviewError.alreadyMatched {
                // Answered on its own meanwhile.
            }
        }
        return confirmed
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
