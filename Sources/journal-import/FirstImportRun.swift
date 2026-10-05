import Foundation
import GRDB
import JournalCore

/// Runs the first Import against an OpenEmu library folder (read-only) into a scratch journal
/// folder, and prints the draft's summary and blockers. With `--commit`, `_Current` Games are
/// answered "Not playing" and the draft is committed, then the journal's counts are printed.
func firstImportRun(library: URL, journalFolder: URL, commit: Bool, igdb: IGDBClient, hasheous: HasheousClient) async throws {
    let journal = try JournalStore(directory: journalFolder)
    let run = FirstImport(
        igdb: igdb, hasheous: hasheous, journal: journal, backups: nil, draftFolder: journalFolder.appending(path: "draft"),
        libretro: LibretroThumbnails(cache: try CacheStore(directory: cacheDirectory)))
    var draft = try await run.start(library: library) { phase, fraction in
        FileHandle.standardError.write(Data("\r\(phase.rawValue) \(Int(fraction * 100))%   ".utf8))
    }
    let s = draft.summary
    print(
        "\n\(draft.library.roms.count) ROMs: \(s.automatic) Automatic (\(s.games) Games), \(s.namesAgree) suggestions whose names agree, ")
    print("\(s.otherSuggestions) other suggestions, \(s.noSuggestion) with no suggestion; \(s.missing) missing")
    let blockers = draft.blockers
    print("Start dates needed: \(blockers.missingStartDates.map(\.name))")
    print("Duplicate Versions: \(blockers.duplicateVersions.map { $0.roms.map(\.name) })")
    guard commit else { return }
    for game in blockers.missingStartDates { try run.answer(&draft, start: .notPlaying, forROM: game.romPK) }
    try await run.commit(draft)
    let counts = try await DatabaseQueue(path: journalFolder.appending(path: "journal.sqlite").path(percentEncoded: false)).read { db in
        try [
            "game", "rom", "rom WHERE gameId IS NULL", "rom WHERE missing", "list", "playthrough", "ratingEntry", "cover",
            "activitySnapshot",
        ]
        .map { "\($0): \(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)")!)" }
    }
    print("Committed. " + counts.joined(separator: ", "))
}
