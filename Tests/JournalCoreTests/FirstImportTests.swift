import Foundation
import GRDB
import Testing

@testable import JournalCore

@Suite struct FirstImportTests {
    let h: Harness
    let j: JournalHarness
    let oe: FakeOpenEmu
    let backupsFolder: URL

    init() throws {
        h = try Harness()
        j = try JournalHarness()
        oe = try FakeOpenEmu(in: h.directory)
        backupsFolder = h.directory.appending(path: "backups", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: backupsFolder, withIntermediateDirectories: true)
        h.internet.addPlatform(19, "Super Nintendo Entertainment System")
        let snes: [String: Any] = ["id": 19, "name": "Super Nintendo Entertainment System"]
        h.internet.addGame(1103, "Super Metroid", fields: ["platforms": [snes], "cover": ["image_id": "co1"]])
        h.internet.addGame(1070, "Super Mario World", fields: ["platforms": [snes]])
        h.internet.addGame(3, "Double Dragon III", fields: ["platforms": [snes]])
        h.internet.addHash(md5: "aa", game: 1103, platform: 19)
        h.internet.addHash(md5: "bb", game: 1070, platform: 19)
    }

    var backups: Backups { Backups(folder: backupsFolder, fallback: backupsFolder, clock: j.clock, timeZone: j.timeZone) }

    var firstImport: FirstImport {
        FirstImport(
            igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: backups,
            draftFolder: h.directory.appending(path: "draft", directoryHint: .isDirectory))
    }

    func start() async throws -> ImportDraft { try await firstImport.start(library: oe.folder) { _, _ in } }

    func games() throws -> [(name: String, igdb: Int64?)] {
        try j.journal.db.read { db in
            try Row.fetchAll(db, sql: "SELECT COALESCE(nameOverride, igdbName, name) AS n, igdbGameId FROM game ORDER BY id").map {
                ($0["n"], $0["igdbGameId"])
            }
        }
    }

    // MARK: Reading OpenEmu

    @Test func theSnapshotCarriesWhatTheImportNeeds() async throws {
        let played = Date(timeIntervalSince1970: 1_700_000_000)
        try oe.addROM(
            "Super Metroid (Japan, USA)", md5: "aa", stars: 5, collections: ["_TODO", "Metroid"], playCount: 3, playTime: 600,
            lastPlayed: played)
        try oe.addROM("Gone (USA)", md5: "cc", fileName: nil)

        let draft = try await start()

        #expect(draft.library.storeUUID == "STORE-1")
        let metroid = draft.library.roms[0]
        #expect(metroid.md5 == "aa")
        #expect(metroid.stars == 5)
        #expect(Set(metroid.collections) == ["_TODO", "Metroid"])
        #expect(metroid.playCount == 3)
        #expect(metroid.lastPlayedAt == played)
        #expect(metroid.isPresent)
        #expect(!draft.library.roms[1].isPresent)
    }

    // MARK: The draft

    @Test func theDraftIsSavedSoQuittingResumesIt() async throws {
        try oe.addROM("Super Metroid (USA)", md5: "aa")
        let draft = try await start()

        let resumed = try #require(try firstImport.loadDraft())

        #expect(resumed.matches == draft.matches)
        try firstImport.discardDraft()
        #expect(try firstImport.loadDraft() == nil)
    }

    @Test func currentGamesNeedAStartDateOrNotPlaying() async throws {
        let metroid = try oe.addROM("Super Metroid (USA)", md5: "aa", collections: ["_Current"])
        let mario = try oe.addROM("Super Mario World (USA)", md5: "bb", collections: ["_Current"])
        var draft = try await start()
        #expect(draft.blockers.missingStartDates.map(\.romPK) == [metroid, mario])

        try firstImport.answer(&draft, start: .started(PartialDate("2026-09")!), forROM: metroid)
        try firstImport.answer(&draft, start: .notPlaying, forROM: mario)

        #expect(draft.blockers.isEmpty)
        #expect(try firstImport.loadDraft()?.blockers.isEmpty == true)
    }

    @Test func twoPresentVersionsOfOneGameBlockTheCommit() async throws {
        try oe.addROM("Super Metroid (Japan)", md5: "aa")
        h.internet.addHash(md5: "a2", game: 1103, platform: 19)
        try oe.addROM("Super Metroid (USA)", md5: "a2")

        let draft = try await start()

        #expect(draft.blockers.duplicateVersions.count == 1)
        #expect(draft.blockers.duplicateVersions[0].roms.map(\.name) == ["Super Metroid (Japan)", "Super Metroid (USA)"])
        #expect(draft.blockers.duplicateVersions[0].name == "Super Metroid")
        await #expect(throws: ImportError.blocked) { try await firstImport.commit(draft) }
    }

    @Test func checkAgainKeepsAnswersDropsRemovedROMsAndMatchesNewOnes() async throws {
        let metroid = try oe.addROM("Super Metroid (USA)", md5: "aa", collections: ["_Current"])
        let dupe = try oe.addROM("Super Metroid (Japan)", md5: "a2")
        h.internet.addHash(md5: "a2", game: 1103, platform: 19)
        var draft = try await start()
        try firstImport.answer(&draft, start: .notPlaying, forROM: metroid)
        try oe.removeROM(dupe)
        let mario = try oe.addROM("Super Mario World (USA)", md5: "bb")

        draft = try await firstImport.checkAgain(draft, library: oe.folder) { _, _ in }

        #expect(draft.blockers.isEmpty)
        #expect(draft.library.roms.map(\.pk) == [metroid, mario])
        #expect(draft.matches[mario] == .automatic(gameID: 1070))
        #expect(draft.startAnswers[metroid] == .notPlaying)
    }

    @Test func aReplacedLibraryIsMatchedAfresh() async throws {
        let metroid = try oe.addROM("Super Metroid (USA)", md5: "aa", collections: ["_Current"])
        var draft = try await start()
        try firstImport.answer(&draft, start: .notPlaying, forROM: metroid)
        try oe.replaceStore(uuid: "STORE-2")

        draft = try await firstImport.checkAgain(draft, library: oe.folder) { _, _ in }

        #expect(draft.library.storeUUID == "STORE-2")
        #expect(draft.startAnswers.isEmpty)
    }

    @Test func aGameWithTwoCurrentROMsGetsOnePlaythrough() async throws {
        let disc1 = try oe.addROM("Final Fantasy VII (USA) (Disc 1)", md5: "f1", system: "openemu.system.psx", collections: ["_Current"])
        let disc2 = try oe.addROM("Final Fantasy VII (USA) (Disc 2)", md5: "f2", system: "openemu.system.psx", collections: ["_Current"])
        h.internet.addGame(427, "Final Fantasy VII", fields: ["platforms": [["id": 7, "name": "PlayStation"]]])
        h.internet.addPlatform(7, "PlayStation")
        h.internet.addHash(md5: "f1", game: 427, platform: 7)
        h.internet.addHash(md5: "f2", game: 427, platform: 7)
        var draft = try await start()
        try firstImport.answer(&draft, start: .started(PartialDate("2026-08")!), forROM: disc1)
        try firstImport.answer(&draft, start: .started(PartialDate("2026-09")!), forROM: disc2)

        try await firstImport.commit(draft)

        let game = try #require(try j.journal.library(LibraryFilter(), sort: .name, ascending: true).first)
        #expect(try j.journal.playthroughs(game.id).map(\.draft.start) == [PartialDate("2026-08")])
    }

    // MARK: Committing

    @Test func committingCreatesTheJournal() async throws {
        let played = Date(timeIntervalSince1970: 1_700_000_000)
        let metroid = try oe.addROM(
            "Super Metroid (USA)", md5: "aa", stars: 4, collections: ["_TODO Next", "_Current", "Metroid", "_Childhood Played"],
            playCount: 3, playTime: 600, lastPlayed: played)
        try oe.addROM("Super Mario World (USA)", md5: "bb", stars: 3, collections: ["_Completed", "_TODO", "Mario"])
        var draft = try await start()
        try firstImport.answer(&draft, start: .started(PartialDate("2026-09")!), forROM: metroid)

        try await firstImport.commit(draft)

        #expect(try games().map(\.name) == ["Super Metroid", "Super Mario World"])
        let rows = try j.journal.library(LibraryFilter(), sort: .name, ascending: true)
        let sm = try #require(rows.first { $0.name == "Super Metroid" })
        let smw = try #require(rows.first { $0.name == "Super Mario World" })
        #expect(sm.intent == .upNext)
        #expect(sm.intentSetAt == nil)
        #expect(sm.childhood)
        #expect(sm.isPlaying)
        #expect(try j.journal.playthroughs(sm.id).map(\.draft.start) == [PartialDate("2026-09")])
        #expect(sm.rating == Rating(tenths: 80))
        #expect(try j.journal.ratingHistory(sm.id).first?.imported == true)
        #expect(smw.intent == .backlog)
        #expect(smw.outcomes == [.finished])
        #expect(try j.journal.playthroughs(smw.id).first?.draft == PlaythroughDraft(outcome: .finished))
        #expect(smw.rating == Rating(tenths: 60))
        #expect(Set(try j.journal.lists().map(\.name)) == ["Metroid", "Mario"])
        #expect(try j.journal.roms(of: sm.id).first?.playCount == 3)
        #expect(try j.journal.firstImportDone())
        #expect(try firstImport.loadDraft() == nil)
        #expect(try backups.all().first?.operation == .beforeImport)
    }

    @Test func unmatchedROMsCarryOverWithTheirSuggestionAndHeldData() async throws {
        h.internet.addSearch("Kirby Super Star", platform: 19, results: [7])
        h.internet.addGame(7, "Kirby Super Star", fields: ["platforms": [["id": 19, "name": "SNES"]]])
        let kirby = try oe.addROM("Kirby Super Star (USA)", md5: "kk", stars: 5, collections: ["_TODO", "Kirby"])
        try oe.addROM("Unknown Homebrew", md5: "zz")
        let draft = try await start()

        try await firstImport.commit(draft)

        #expect(try games().isEmpty)
        let rows = try j.journal.db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM rom r LEFT JOIN heldOpenEmuData h ON h.romId = r.id ORDER BY openEmuPk")
        }
        #expect(rows.count == 2)
        #expect(rows[0]["openEmuPk"] as Int64 == kirby)
        #expect(rows[0]["gameId"] as Int64? == nil)
        #expect(rows[0]["suggestedIgdbGameId"] as Int64? == 7)
        #expect(rows[0]["suggestionKind"] as String? == "name")
        #expect(rows[0]["namesAgree"] as Bool? == true)
        #expect(rows[0]["stars"] as Int == 5)
        #expect(rows[0]["collections"] as String == #"["Kirby","_TODO"]"#)
        #expect(rows[1]["suggestedIgdbGameId"] as Int64? == nil)
    }

    @Test func orphanedEntriesAreImportedAsMissingWithoutActivity() async throws {
        try oe.addROM("Super Metroid (USA)", md5: "aa", fileName: nil, stars: 5, playCount: 9)
        let draft = try await start()

        try await firstImport.commit(draft)

        let game = try #require(try j.journal.library(LibraryFilter(), sort: .name, ascending: true).first)
        #expect(game.noROMInOpenEmu)
        #expect(game.rating == Rating(tenths: 100))
        let snapshots = try await j.journal.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM activitySnapshot")! }
        #expect(snapshots == 0)
    }

    @Test func gamesWithoutAnIGDBCoverCarryOverOpenEmusBoxArt() async throws {
        try oe.addROM("Super Mario World (USA)", md5: "bb", boxArt: testImage(width: 200, height: 280))
        try oe.addROM("Super Metroid (USA)", md5: "aa", boxArt: testImage(width: 200, height: 280))
        let draft = try await start()

        try await firstImport.commit(draft)

        let rows = try j.journal.library(LibraryFilter(), sort: .name, ascending: true)
        let smw = try #require(rows.first { $0.name == "Super Mario World" })
        let sm = try #require(rows.first { $0.name == "Super Metroid" })
        #expect(try j.journal.journalCover(smw.id)?.origin == .carried)
        #expect(try j.journal.journalCover(sm.id) == nil)  // IGDB has a cover
    }

    @Test func aGameAlreadyInTheJournalGetsTheROM() async throws {
        try j.journal.addPlatform(id: 19, name: "SNES")
        let existing = try j.journal.addGame(platformId: 19, name: "Super Metroid", igdbGameId: 1103, igdbName: "Super Metroid")
        try oe.addROM("Super Metroid (USA)", md5: "aa")
        let draft = try await start()

        try await firstImport.commit(draft)

        #expect(try games().count == 1)
        #expect(try j.journal.roms(of: existing).count == 1)
    }
}
