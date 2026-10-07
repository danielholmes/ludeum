import Foundation
import GRDB

public enum AddROMError: Error, Equatable {
    /// Nothing picked, or a mix that isn't one game: several files that aren't each a different Disc, say.
    case notOneGame
    /// No Platform's ROM folder reads what was picked.
    case noPlatformReadsIt
    /// The Platform's ROM folder doesn't read what was picked.
    case platformWontReadIt(String)
    /// The ROM folder already has a ROM of that name.
    case alreadyInROMFolder(String)
    /// The journal remembers a missing ROM of that name that's another Game's: forget it first.
    case missingROMIsAnotherGames(String)
    /// Several files that could each be the game: which is isn't clear.
    case ambiguous([String])
    /// Nothing picked is a file the Emulator opens.
    case noImage
    /// Once in place, the ROM folder didn't read it as a Playable ROM, so it was taken out again.
    case notReadAfterward(String)
    /// Of several ROMs Added at once, these couldn't go in (each "name: why"); the rest did.
    case notAllAdded([String], of: Int)
}

extension AddROMError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notOneGame: "That isn't one game: pick its file, its folder, an archive of it, or each of its Discs."
        case .noPlatformReadsIt: "No Platform's ROM folder reads that."
        case .platformWontReadIt(let platform): "\(platform)'s ROM folder doesn't read that."
        case .alreadyInROMFolder(let name): "\(name) is already in its ROM folder."
        case .missingROMIsAnotherGames(let name):
            "The journal remembers a missing ROM called \(name) on another Game. Forget it there first."
        case .ambiguous(let images): "Which of these is the game isn't clear: \(images.joined(separator: ", "))."
        case .noImage: "Nothing in it is a game image."
        case .notReadAfterward(let name): "Its ROM folder didn't read \(name) as a Playable ROM, so it was taken out again."
        case .notAllAdded(let failures, let total):
            "\(failures.count) of \(total) ROMs couldn't be added, and the rest were. " + failures.joined(separator: " ")
        }
    }
}

/// Files picked from elsewhere to Add as a ROM: one file (a cue sheet brings its tracks, a playlist its Discs), a
/// `.7z` or `.zip` of the game, a folder holding it, or each Disc of a multi-disc Version.
public struct ROMSource: Sendable, Equatable {
    public let urls: [URL]

    public init(_ urls: [URL]) {
        self.urls = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Files picked at once as several ROMs, in name order: each folder and each archive is one, and so is each other
    /// file, less any that another brings along (a cue sheet's tracks, a playlist's Discs). The Discs of one Version are
    /// one ROM together, unless no Platform reads them that way (GameCube keeps each Disc a ROM of its own).
    public static func split(_ urls: [URL]) async -> [ROMSource] {
        func key(_ url: URL) -> String { url.standardizedFileURL.path(percentEncoded: false) }
        let loose = urls.filter { ROMSource([$0]).isFolder == false && ROMSource([$0]).archive == nil }
        let brought = Set(loose.flatMap { ROMFiles.files(of: $0).dropFirst() }.map(key))
        var sources = urls.filter { url in !loose.contains(url) }.map { ROMSource([$0]) }
        let versions = Dictionary(grouping: loose.filter { !brought.contains(key($0)) }) {
            ROMName($0.deletingPathExtension().lastPathComponent).withoutDisc
        }
        for files in versions.values {
            let discs = ROMSource(files)
            if files.count > 1, !ROMFolder.discs(files).isEmpty, let platforms = try? await discs.platforms(sevenZip: nil),
                !platforms.isEmpty
            {
                sources.append(discs)
            } else {
                sources += files.map { ROMSource([$0]) }
            }
        }
        return sources.sorted { $0.romName.localizedStandardCompare($1.romName) == .orderedAscending }
    }

    /// The ROM's name: its file's without the extension, or its folder's; with several Discs, Disc 1's without its Disc.
    public var romName: String {
        if urls.count > 1, let first = ROMFolder.discs(urls).first {
            return ROMName(first.deletingPathExtension().lastPathComponent).withoutDisc
        }
        guard let url = urls.first else { return "" }
        return isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }

    /// One folder, which becomes the ROM's subfolder.
    public var isFolder: Bool {
        urls.count == 1 && (try? urls[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// One `.7z` or `.zip`.
    public var archive: URL? {
        urls.count == 1 && !isFolder && ["7z", "zip"].contains(urls[0].pathExtension.lowercased()) ? urls[0] : nil
    }

    /// The Platforms whose ROM folders read it, by IGDB platform id: a folder, or several Discs, only where ROMs are kept
    /// in subfolders. An archive is read by what's inside it, so needs 7-Zip.
    public func platforms(sevenZip: SevenZip?) async throws -> [Int64] {
        guard !urls.isEmpty else { throw AddROMError.notOneGame }
        if urls.count > 1 && ROMFolder.discs(urls).isEmpty { throw AddROMError.notOneGame }
        let inside: [String]
        if isFolder {
            inside = Self.files(in: urls[0]).map(\.path)
        } else if let archive {
            guard let sevenZip else { throw ArchiveError.noSevenZip }
            inside = try await sevenZip.list(archive).map(\.path)
        } else {
            inside = urls.map(\.path)
        }
        let extensions = Set(inside.filter { !Self.isHidden($0) }.map { ($0 as NSString).pathExtension.lowercased() })
        let platforms = ROMPlatform.all.filter { _, platform in
            if (isFolder || urls.count > 1) && platform.archiving != .intoFolder { return false }
            // A Compacted archive is read as it is.
            if let archive, archive.pathExtension.lowercased() == platform.compactExtension { return true }
            return !extensions.isDisjoint(with: platform.readyExtensions)
        }
        return platforms.keys.sorted()
    }

    /// Of the Platforms that read it, the one it's most likely for: the only one, else the only one whose Emulator
    /// prefers its file's extension above any other (a `.gb` is Game Boy's, though Game Boy Color reads it too).
    public func likeliestPlatform(of platforms: [Int64]) -> Int64? {
        if platforms.count == 1 { return platforms[0] }
        guard urls.count == 1, !isFolder, archive == nil else { return nil }
        let ext = urls[0].pathExtension.lowercased()
        let preferring = platforms.filter { ROMPlatform.all[$0]?.readyExtensions.first == ext }
        return preferring.count == 1 ? preferring[0] : nil
    }

    /// Every file in the folder, at any depth, less hidden files that aren't a game.
    static func files(in folder: URL) -> [URL] {
        ((try? FileManager.default.subpathsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? [])
            .filter { !isHidden($0) }
            .map { folder.appending(path: $0, directoryHint: .notDirectory) }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }

    /// Whether a path is a hidden file that isn't a game: Finder's `.DS_Store` and `._` companions, and any other hidden
    /// file no Emulator opens. A game's own name can start with a dot (`.hack--Link (Japan).iso`).
    static func isHidden(_ path: String) -> Bool {
        guard (path as NSString).pathComponents.contains(where: { $0.hasPrefix(".") }) else { return false }
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        return name.hasPrefix("._") || !ROMPlatform.all.values.contains { $0.readyExtensions.contains(ext) }
    }
}

/// Who an Added ROM is Matched to, by hand.
public enum AddROMMatch: Sendable, Equatable {
    /// The Game with this IGDB link on the Platform, made if the journal doesn't have it yet.
    case igdb(gameId: Int64, name: String, platform: IGDBPlatform)
    /// A Game the journal has, e.g. one whose ROMs are all missing. `forgettingMissing` forgets its missing ROMs once the
    /// new one is in.
    case game(GameID, forgettingMissing: Bool)
    /// A new Game with no IGDB link, made by hand with this name on the ROM's Platform, for a game IGDB doesn't have.
    case byHand(name: String)
}

/// Add ROM: puts a game picked from elsewhere into its Platform's ROM folder in the form the Platform keeps, then records
/// it and Matches it by hand. A Compactable Platform's ROM is Compacted; a Platform whose ROMs are kept in subfolders
/// gets one named after the ROM, with a playlist for its Discs; anything else is one Playable file named after the ROM.
/// An archive is unpacked first unless it's already the one its Emulator opens. Everything is made in a hidden work
/// folder inside the ROM folder and moves into place only once it's all there; with `keepingOriginals` false, the
/// picked files go to the Trash last of all, once the ROM is in the journal.
public struct AddROM: Sendable {
    let journal: LudeumStore
    let sevenZip: SevenZip?
    let libretro: LibretroThumbnails?
    let moveToTrash: @Sendable (URL) throws -> Void

    public init(
        journal: LudeumStore, sevenZip: SevenZip? = SevenZip.find(), libretro: LibretroThumbnails? = nil,
        moveToTrash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.journal = journal
        self.sevenZip = sevenZip
        self.libretro = libretro
        self.moveToTrash = moveToTrash
    }

    /// What Add ROM will make of it in the ROM folder, e.g. `Tetris (World).7z` or `Fear Effect 2 (Europe)/`, for the
    /// sheet to show before it starts.
    public static func fileName(of source: ROMSource, in folder: ROMFolder) -> String {
        let name = source.romName
        if source.isFolder || source.urls.count > 1 || folder.archiving == .intoFolder { return "\(name)/" }
        if let compact = folder.compactExtension { return "\(name).\(compact)" }
        let ext = source.archive == nil ? source.urls.first?.pathExtension.lowercased() ?? "" : "…"
        return "\(name).\(ext)"
    }

    /// Adds the ROM and returns its Game. Throws, with the ROM folder and journal as they were and the picked files
    /// untouched, when anything goes wrong before the ROM is in the journal.
    @discardableResult
    public func add(
        _ source: ROMSource, to folder: ROMFolder, match: AddROMMatch, keepingOriginals: Bool,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> GameID {
        let name = source.romName
        if case .byHand(let gameName) = match, gameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LudeumError.nameRequired
        }
        try await check(source, fits: folder)
        let missingRow = try missingROM(named: name, on: folder.platformId, for: match)
        let (destination, file) = try await put(source, in: folder, progress: progress)
        let game: GameID
        do {
            let checksum = await ROMChecksum.of(file, platformId: folder.platformId, sevenZip: sevenZip)
            (game, _) = try journal.recordAddedROM(file, checksum: checksum, on: folder.platformId, reusing: missingRow, match: match)
        } catch {
            // Never in the journal: what was put in place goes again, and the picked files were never touched.
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        if !keepingOriginals { trashOriginals(of: source) }
        if let rom = try journal.romID(named: name, on: folder.platformId) {
            try? await BoxArtImport(journal: journal, libretro: libretro).lookUp([rom])
        }
        return game
    }

    /// Adds several ROMs at once, one after another, without Matching them: each goes into its ROM folder as `add` puts
    /// it, and the next Import reads it as a new ROM, Matching it automatically or sending it to the Review queue. One
    /// that can't go in is left as it was, and the rest still go in; then it throws, saying which and why.
    public func add(
        _ roms: [(source: ROMSource, folder: ROMFolder)], keepingOriginals: Bool,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        var failures: [String] = []
        for (i, rom) in roms.enumerated() {
            try Task.checkCancellation()
            let done = Double(i) / Double(roms.count)
            do {
                try await check(rom.source, fits: rom.folder)
                _ = try await put(rom.source, in: rom.folder) { progress(done + $0 / Double(roms.count)) }
            } catch {
                // Cancelled, not failed, even when 7-Zip was stopped with an error of its own.
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                failures.append("\(rom.source.romName): \(error.localizedDescription)")
                continue
            }
            if !keepingOriginals { trashOriginals(of: rom.source) }
        }
        if !failures.isEmpty { throw AddROMError.notAllAdded(failures, of: roms.count) }
    }

    /// Throws, touching nothing, when the ROM folder won't read it or already has a ROM of its name.
    private func check(_ source: ROMSource, fits folder: ROMFolder) async throws {
        let platformName = ROMPlatform.all[folder.platformId]?.name ?? "Platform \(folder.platformId)"
        guard try await source.platforms(sevenZip: sevenZip).contains(folder.platformId) else {
            throw AddROMError.platformWontReadIt(platformName)
        }
        try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
        if try folder.scan().contains(where: { $0.name == source.romName }) { throw AddROMError.alreadyInROMFolder(source.romName) }
    }

    /// Makes the ROM in a work folder and moves it into place, then checks the ROM folder reads it as a Playable ROM in
    /// one form, taking it out again if not.
    private func put(
        _ source: ROMSource, in folder: ROMFolder, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (destination: URL, file: FolderROMFile) {
        let name = source.romName
        let work = folder.url.appending(path: ROMArchiver.workFolderName, directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let made = try await make(source, named: name, in: folder, work: work, progress: progress)
        try Task.checkCancellation()

        let destination = folder.url.appending(path: made.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            throw AddROMError.alreadyInROMFolder(destination.lastPathComponent)
        }
        try FileManager.default.moveItem(at: made, to: destination)
        do {
            guard let file = try folder.scan().first(where: { $0.name == name }), !file.archived, !file.inBothForms else {
                throw AddROMError.notReadAfterward(destination.lastPathComponent)
            }
            return (destination, file)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// The journal's row for a missing ROM of this name, which the new file brings back. Throws when the ROM is present
    /// (its file gone from the folder only since the last Import), or the row is another Game's.
    private func missingROM(named name: String, on platformId: Int64, for match: AddROMMatch) throws -> Int64? {
        guard
            let row = try journal.db.read({ db in
                try Row.fetchOne(
                    db, sql: "SELECT id, gameId, missing FROM rom WHERE platformId = ? AND folderName = ?", arguments: [platformId, name])
            })
        else { return nil }
        guard row["missing"] else { throw AddROMError.alreadyInROMFolder(name) }
        guard let rowGame = row["gameId"] as GameID? else { return row["id"] }
        let target: GameID? =
            switch match {
            case .igdb(let gameId, _, let platform): try journal.gameID(igdbGameId: gameId, platformId: platform.id)
            case .game(let game, _): game
            case .byHand: nil
            }
        guard rowGame == target else { throw AddROMError.missingROMIsAnotherGames(name) }
        return row["id"]
    }

    /// Makes the ROM's file or subfolder in `work`, named as it will be in the ROM folder.
    private func make(
        _ source: ROMSource, named name: String, in folder: ROMFolder, work: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        // Already the archive its Emulator opens: it goes in as it is.
        if let archive = source.archive, let compact = folder.compactExtension, archive.pathExtension.lowercased() == compact {
            let copy = work.appending(path: "\(name).\(compact)")
            try FileManager.default.copyItem(at: archive, to: copy)
            return copy
        }
        // Everything picked, unpacked if it's an archive, in a folder named after the ROM. Copies are clones on APFS.
        let staged = work.appending(path: name, directoryHint: .isDirectory)
        if source.isFolder {
            try FileManager.default.copyItem(at: source.urls[0], to: staged)
        } else if let archive = source.archive {
            guard let sevenZip else { throw ArchiveError.noSevenZip }
            let packs = folder.compactExtension != nil
            try await sevenZip.extract(archive, paths: [], to: staged) { progress(packs ? $0 / 2 : $0) }
        } else {
            try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
            for file in source.urls.flatMap(ROMFiles.files(of:))
            where !FileManager.default.fileExists(atPath: staged.appending(path: file.lastPathComponent).path(percentEncoded: false)) {
                try FileManager.default.copyItem(at: file, to: staged.appending(path: file.lastPathComponent))
            }
        }
        let files = ROMSource.files(in: staged)

        if folder.archiving == .intoFolder {
            guard let game = folder.game(among: files) else {
                let images = files.filter { folder.readyExtensions.contains($0.pathExtension.lowercased()) }
                throw images.isEmpty ? AddROMError.noImage : AddROMError.ambiguous(images.map(\.lastPathComponent))
            }
            if !game.discsWithoutPlaylist.isEmpty { try writePlaylist(named: name, for: game.discsWithoutPlaylist, in: staged) }
            return staged
        }

        // One file: the game's one image, named after the ROM.
        let readable = ROMPlatform.all[folder.platformId]?.readyExtensions ?? []
        let images = files.filter { readable.contains($0.pathExtension.lowercased()) }
        guard let image = images.first else { throw AddROMError.noImage }
        guard images.count == 1 else { throw AddROMError.ambiguous(images.map(\.lastPathComponent).sorted()) }
        let named = work.appending(path: "\(name).\(image.pathExtension.lowercased())")
        try FileManager.default.moveItem(at: image, to: named)
        guard let format = folder.compactExtension else { return named }
        guard let sevenZip else { throw ArchiveError.noSevenZip }
        let packed = staged.appending(path: "\(name).\(format)")
        let unpacked = source.archive != nil
        try await sevenZip.create(packed, format: format, files: [named.lastPathComponent], in: work) {
            progress(unpacked ? 0.5 + $0 / 2 : $0)
        }
        try await sevenZip.test(packed)
        let size = Int64(try named.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard try await sevenZip.list(packed).map(\.size) == [size] else { throw ArchiveError.checkFailed(packed.lastPathComponent) }
        return packed
    }

    /// Writes `<name>.m3u` into the subfolder, naming its Discs in order.
    private func writePlaylist(named name: String, for discs: [URL], in subfolder: URL) throws {
        let base = subfolder.standardizedFileURL.pathComponents.count
        let lines = discs.map { $0.standardizedFileURL.pathComponents.dropFirst(base).joined(separator: "/") }
        try Data((lines.joined(separator: "\n") + "\n").utf8)
            .write(to: subfolder.appending(path: "\(name).m3u", directoryHint: .notDirectory), options: .withoutOverwriting)
    }

    /// Sends the picked files to the Trash, once the ROM made of them is in.
    private func trashOriginals(of source: ROMSource) {
        for original in Self.originals(of: source) { try? moveToTrash(original) }
    }

    /// What was picked, with the cue sheets' tracks and the playlists' Discs it brought along.
    static func originals(of source: ROMSource) -> [URL] {
        if source.isFolder || source.archive != nil { return source.urls }
        var all: [URL] = []
        for file in source.urls.flatMap(ROMFiles.files(of:)) where !all.contains(file) { all.append(file) }
        return all
    }
}

extension LudeumStore {
    /// Records an Added ROM and Matches it by hand, in one transaction: a new row, or the missing one it brings back.
    func recordAddedROM(
        _ file: FolderROMFile, checksum: ROMChecksum?, on platformId: Int64, reusing missingRow: Int64?, match: AddROMMatch
    ) throws -> (game: GameID, rom: Int64) {
        let now = clock.now()
        let day = today()
        return try db.write { db in
            try ROMPlatform.ensureKnown(db, platformId)
            let rom: Int64
            if let missingRow {
                rom = missingRow
                try Self.setFolderROM(db, rom, to: file)
            } else {
                let parsed = ROMName(file.name)
                try db.execute(
                    sql: """
                        INSERT INTO rom
                            (folderName, md5, crc, archived, fileName, name, platformId, version, discNumber, discLabel, needsPlaylist,
                             inBothForms)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        file.name, checksum?.md5, checksum?.crc, file.archived, file.fileName, file.name, platformId,
                        parsed.version, parsed.disc, parsed.discLabel, file.needsPlaylist, file.inBothForms,
                    ])
                rom = db.lastInsertedRowID
            }
            let matched = try GameID.fetchOne(db, sql: "SELECT gameId FROM rom WHERE id = ?", arguments: [rom])
            let game: GameID
            switch match {
            case .igdb(let gameId, let name, let platform):
                try db.execute(
                    sql: "INSERT INTO platform (id, name) VALUES (?, ?) ON CONFLICT (id) DO NOTHING",
                    arguments: [platform.id, platform.name])
                if let matched {
                    game = matched
                } else {
                    game = try Self.matchToIGDBGame(
                        db, rom: rom, romName: file.name, igdbGameId: gameId, igdbName: name, platformId: platformId, kind: "manual",
                        day: day, now: now)
                }
            case .game(let target, let forgettingMissing):
                guard try Int64.fetchOne(db, sql: "SELECT platformId FROM game WHERE id = ?", arguments: [target]) == platformId else {
                    throw LudeumError.gameNotFound
                }
                if matched == nil { try Self.match(db, rom: rom, to: target, kind: "manual", day: day, now: now) }
                if forgettingMissing {
                    try db.execute(sql: "DELETE FROM rom WHERE gameId = ? AND missing AND id <> ?", arguments: [target, rom])
                }
                game = target
            case .byHand(let name):
                if let matched {
                    game = matched
                } else {
                    try db.execute(
                        sql: "INSERT INTO game (platformId, name) VALUES (?, ?)",
                        arguments: [platformId, name.trimmingCharacters(in: .whitespacesAndNewlines)])
                    game = db.lastInsertedRowID
                    try Self.match(db, rom: rom, to: game, kind: "manual", day: day, now: now)
                }
            }
            return (game, rom)
        }
    }

    /// The ROM of that name in the Platform's ROM folder, present or missing.
    public func romID(named name: String, on platformId: Int64) throws -> Int64? {
        try db.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM rom WHERE platformId = ? AND folderName = ?", arguments: [platformId, name])
        }
    }
}
