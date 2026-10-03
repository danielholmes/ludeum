import Foundation

public enum ImportError: Error, Equatable {
    /// The commit waits on start dates or Duplicate Versions.
    case blocked
    /// The first Import has already been committed.
    case alreadyImported
    /// The answer is for a ROM that isn't in the draft.
    case unknownROM
}

/// The answer for a `_Current` Game: when I started it, or that I'm not playing it.
public enum StartAnswer: Codable, Sendable, Hashable {
    case started(PartialDate)
    case notPlaying
}

extension PartialDate: Codable {
    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let date = PartialDate(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a Partial date: \(text)"))
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}

/// The phases of an Import, as the Import page's timeline shows them.
public enum ImportPhase: String, Sendable, CaseIterable {
    case snapshot, lookups, matching, review
}

/// The first Import before it's committed: OpenEmu's snapshot, how each ROM matched, and my
/// answers so far. None of it is journal data until the commit.
public struct ImportDraft: Codable, Sendable, Equatable {
    public internal(set) var library: OpenEmuLibrarySnapshot
    /// By `Z_PK`.
    public internal(set) var matches: [Int64: MatchResult]
    /// The IGDB platform each Automatic Match's Game is on, by `Z_PK`.
    public internal(set) var platforms: [Int64: Int64]
    /// Start date answers for `_Current` ROMs, by `Z_PK`.
    public internal(set) var startAnswers: [Int64: StartAnswer]

    /// What the commit waits on.
    public var blockers: ImportBlockers {
        let missing = library.roms.filter { $0.collections.contains(SpecialCollection.current) && startAnswers[$0.pk] == nil }
        let duplicates = Dictionary(grouping: library.roms.filter { gameKey($0) != nil }, by: { gameKey($0)! })
            .values
            .filter { roms in
                hasDuplicateVersions(
                    roms.map { GameROM(id: Int($0.pk), name: $0.name, isPlaylist: $0.isPlaylist, isPresent: $0.isPresent) })
            }
            .map { DuplicateVersionsItem(igdbGameId: gameKey($0[0])!.igdbGameId, roms: $0.filter(\.isPresent).sorted { $0.pk < $1.pk }) }
            .sorted { $0.roms[0].pk < $1.roms[0].pk }
        return ImportBlockers(missingStartDates: missing.map { CurrentGame(rom: $0) }, duplicateVersions: duplicates)
    }

    /// What will be imported, for "Not blocking".
    public var summary: ImportSummary {
        var s = ImportSummary()
        for rom in library.roms {
            switch matches[rom.pk] {
            case .automatic: s.automatic += 1
            case .suggestion(let suggestion) where suggestion.namesAgree: s.namesAgree += 1
            case .suggestion: s.otherSuggestions += 1
            case .noSuggestion, nil: s.noSuggestion += 1
            }
            if !rom.isPresent { s.missing += 1 }
        }
        s.games = Set(library.roms.compactMap(gameKey)).count
        return s
    }

    struct GameKey: Hashable {
        let igdbGameId: Int64
        let platformId: Int64
    }

    /// The Game an Automatically matched ROM belongs to.
    func gameKey(_ rom: OpenEmuROMRecord) -> GameKey? {
        guard case .automatic(let id) = matches[rom.pk], let platform = platforms[rom.pk] else { return nil }
        return GameKey(igdbGameId: Int64(id), platformId: platform)
    }
}

public struct ImportBlockers: Sendable, Equatable {
    public let missingStartDates: [CurrentGame]
    public let duplicateVersions: [DuplicateVersionsItem]
    public var isEmpty: Bool { missingStartDates.isEmpty && duplicateVersions.isEmpty }
}

/// A `_Current` Game waiting for its start date.
public struct CurrentGame: Sendable, Equatable, Identifiable {
    public let romPK: Int64
    public let name: String
    /// OpenEmu's last-played date, shown as a hint.
    public let lastPlayedAt: Date?
    public var id: Int64 { romPK }

    init(rom: OpenEmuROMRecord) {
        romPK = rom.pk
        name = rom.name
        lastPlayedAt = rom.lastPlayedAt
    }
}

/// A Game with two or more present ROMs that aren't Discs of one Version.
public struct DuplicateVersionsItem: Sendable, Equatable, Identifiable {
    public let igdbGameId: Int64
    /// The Game, by its first ROM's cleaned name.
    public var name: String { cleanName(roms[0].name) }
    /// Its present ROMs, each with its Version text, file and OpenEmu data.
    public let roms: [OpenEmuROMRecord]
    public var id: Int64 { roms[0].pk }
}

public struct ImportSummary: Sendable, Equatable {
    public var automatic = 0
    public var namesAgree = 0
    public var otherSuggestions = 0
    public var noSuggestion = 0
    public var missing = 0
    public var games = 0
}

/// The first Import from OpenEmu, staged as a draft that's saved on disk until it's committed or discarded.
public final class FirstImport: Sendable {
    let igdb: IGDBClient
    let matcher: Matcher
    let journal: JournalStore
    let backups: Backups?
    /// Holds `draft.json` and `snapshot.sqlite`.
    let draftFolder: URL

    public init(igdb: IGDBClient, hasheous: HasheousClient, journal: JournalStore, backups: Backups?, draftFolder: URL) {
        self.igdb = igdb
        matcher = Matcher(igdb: igdb, hasheous: hasheous)
        self.journal = journal
        self.backups = backups
        self.draftFolder = draftFolder
    }

    var draftFile: URL { draftFolder.appending(path: "draft.json") }
    var snapshotFile: URL { draftFolder.appending(path: "snapshot.sqlite") }

    // MARK: The draft

    /// Snapshots OpenEmu's library, matches every ROM and saves the draft.
    public func start(library: URL, progress: @escaping @Sendable (ImportPhase, Double) -> Void) async throws -> ImportDraft {
        guard try !journal.firstImportDone() else { throw ImportError.alreadyImported }
        let snapshot = try takeSnapshot(library: library, progress: progress)
        var draft = ImportDraft(library: snapshot, matches: [:], platforms: [:], startAnswers: [:])
        try await match(snapshot.roms, into: &draft, progress: progress)
        try save(draft)
        return draft
    }

    /// The saved draft, so quitting the app resumes it.
    public func loadDraft() throws -> ImportDraft? {
        guard FileManager.default.fileExists(atPath: draftFile.path(percentEncoded: false)) else { return nil }
        return try JSONDecoder().decode(ImportDraft.self, from: Data(contentsOf: draftFile))
    }

    /// Throws the draft and my answers away; the next Import starts fresh.
    public func discardDraft() throws {
        if FileManager.default.fileExists(atPath: draftFolder.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: draftFolder)
        }
    }

    public func answer(_ draft: inout ImportDraft, start: StartAnswer, forROM pk: Int64) throws {
        guard draft.library.roms.contains(where: { $0.pk == pk }) else { throw ImportError.unknownROM }
        draft.startAnswers[pk] = start
        try save(draft)
    }

    /// Re-reads OpenEmu into the draft. Answers and matches for ROMs still present (same `Z_PK` and
    /// MD5) are kept, those for ROMs that have gone are dropped, and new ROMs go through matching.
    public func checkAgain(
        _ draft: ImportDraft, library: URL, progress: @escaping @Sendable (ImportPhase, Double) -> Void
    ) async throws -> ImportDraft {
        guard try !journal.firstImportDone() else { throw ImportError.alreadyImported }
        let snapshot = try takeSnapshot(library: library, progress: progress)
        let old = Dictionary(uniqueKeysWithValues: draft.library.roms.map { ($0.pk, $0.md5) })
        // A new store UUID is a rebuilt or replaced library: its Z_PKs mean nothing, so match it afresh.
        let sameStore = snapshot.storeUUID == draft.library.storeUUID
        let kept = sameStore ? Set(snapshot.roms.filter { old[$0.pk] == $0.md5 }.map(\.pk)) : []
        var next = ImportDraft(
            library: snapshot, matches: draft.matches.filter { kept.contains($0.key) },
            platforms: draft.platforms.filter { kept.contains($0.key) }, startAnswers: draft.startAnswers.filter { kept.contains($0.key) })
        try await match(snapshot.roms.filter { !kept.contains($0.pk) }, into: &next, progress: progress)
        try save(next)
        return next
    }

    private func takeSnapshot(library: URL, progress: @Sendable (ImportPhase, Double) -> Void) throws -> OpenEmuLibrarySnapshot {
        progress(.snapshot, 0)
        try OpenEmuLibrary.snapshot(library: library, to: snapshotFile)
        let snapshot = try OpenEmuLibrary.read(snapshot: snapshotFile, library: library)
        progress(.snapshot, 1)
        return snapshot
    }

    private func match(
        _ roms: [OpenEmuROMRecord], into draft: inout ImportDraft, progress: @escaping @Sendable (ImportPhase, Double) -> Void
    ) async throws {
        let results = try await matcher.match(roms.map(\.matcherROM)) { done, total in
            progress(.lookups, total == 0 ? 1 : Double(done) / Double(total))
        }
        progress(.matching, 0)
        let automatic = results.values.compactMap { if case .automatic(let id) = $0 { id } else { nil } }
        let records = try await igdb.games(ids: Array(Set(automatic)))
        for rom in roms {
            let result = results[Int(rom.pk)] ?? .noSuggestion
            draft.matches[rom.pk] = result
            if case .automatic(let id) = result {
                draft.platforms[rom.pk] = platform(for: rom.system, game: records[id])
            }
        }
        progress(.matching, 1)
        progress(.review, 1)
    }

    /// The Game's Platform: the first of the system's IGDB platforms the game is on, else the
    /// system's most likely one (`openemu.system.gb` covers Game Boy and Game Boy Color).
    private func platform(for system: String, game: IGDBGame?) -> Int64 {
        let candidates = openEmuSystemPlatforms[system] ?? []
        let listed = Set((game?.record["platforms"]?.array ?? []).compactMap { $0["id"]?.int ?? $0.int })
        return Int64(candidates.first(where: listed.contains) ?? candidates.first ?? 0)
    }

    func save(_ draft: ImportDraft) throws {
        try FileManager.default.createDirectory(at: draftFolder, withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: draftFile, options: .atomic)
    }

    // MARK: Committing

    /// Commits the draft in one transaction, after a backup, then deletes the draft. Refused while
    /// anything blocks it. A committed draft has no undo.
    public func commit(_ draft: ImportDraft) async throws {
        guard draft.blockers.isEmpty else { throw ImportError.blocked }
        guard try !journal.firstImportDone() else { throw ImportError.alreadyImported }
        let games = Dictionary(grouping: draft.library.roms.filter { draft.gameKey($0) != nil }, by: { draft.gameKey($0)! })
        let records = try await igdb.games(ids: games.keys.map { Int($0.igdbGameId) })
        let platformNames = Dictionary(uniqueKeysWithValues: try await igdb.platforms().map { ($0.id, $0.name) })
        var plan = FirstImportPlan(storeUUID: draft.library.storeUUID)
        for (key, roms) in games {
            let record = records[Int(key.igdbGameId)]
            let sorted = roms.sorted { $0.pk < $1.pk }
            let carried: NormalisedCover? =
                record?.record["cover"]?["image_id"]?.string != nil
                ? nil
                : sorted.lazy.compactMap { $0.boxArt.flatMap { try? CoverImage.normalise(Data(contentsOf: $0)) } }.first
            plan.games.append(
                .init(
                    igdbGameId: key.igdbGameId, platformId: key.platformId,
                    platformName: platformNames[key.platformId] ?? "Platform \(key.platformId)",
                    igdbName: record?.name ?? cleanName(sorted[0].name), name: cleanName(sorted[0].name), roms: sorted,
                    carriedCover: carried))
        }
        plan.games.sort { $0.roms[0].pk < $1.roms[0].pk }
        plan.unmatched = draft.library.roms.filter { draft.gameKey($0) == nil }.map { ($0, draft.matches[$0.pk] ?? .noSuggestion) }
        plan.startAnswers = draft.startAnswers
        try backups?.backUp(journal, operation: .beforeImport)
        try journal.commitFirstImport(plan)
        try discardDraft()
    }
}
