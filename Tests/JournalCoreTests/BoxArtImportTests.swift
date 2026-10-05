import Foundation
import GRDB
import Testing

@testable import JournalCore

/// The Box art step of each Import: libretro lookups and OpenEmu's Box art copied into the cache.
@Suite struct BoxArtImportTests {
    let h: Harness
    let j: JournalHarness
    let oe: FakeOpenEmu

    init() throws {
        h = try Harness()
        j = try JournalHarness()
        oe = try FakeOpenEmu(in: h.directory)
        let snes: [String: Any] = ["id": 19, "name": "SNES"]
        h.internet.addPlatform(19, "SNES")
        h.internet.addGame(1103, "Super Metroid", fields: ["platforms": [snes]])
        h.internet.addHash(md5: "aa", game: 1103, platform: 19)
        h.internet.addLibretro("Nintendo_-_Super_Nintendo_Entertainment_System", ["Super Metroid (USA)", "Super Mario World (USA)"])
    }

    func firstImport() async throws {
        let run = FirstImport(
            igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil, draftFolder: h.directory.appending(path: "draft"),
            libretro: h.libretro)
        try await run.commit(try await run.start(library: oe.folder) { _, _ in })
    }

    func ongoingImport() async throws {
        _ = try await OngoingImport(
            igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil, snapshotFile: h.directory.appending(path: "s.sqlite"),
            libretro: h.libretro
        ).run(library: oe.folder)
    }

    func roms() throws -> [Row] {
        try j.journal.db.read { try Row.fetchAll($0, sql: "SELECT * FROM rom ORDER BY id") }
    }

    @Test func everyROMKeepsItsLibretroNamesUnmatchedOnesToo() async throws {
        try oe.addROM("Super Metroid (USA)", md5: "aa")
        try oe.addROM("Super Mario World (USA)", md5: "zz")  // to the Review queue
        try await firstImport()

        let rows = try roms()
        let folder = "Nintendo - Super Nintendo Entertainment System"
        #expect(
            rows.map { $0["libretroBoxart"] as String? } == [
                "\(folder)/Named_Boxarts/Super Metroid (USA).png", "\(folder)/Named_Boxarts/Super Mario World (USA).png",
            ])
        #expect(rows[0]["libretroSnap"] as String? == "\(folder)/Named_Snaps/Super Metroid (USA).png")
        #expect(rows[0]["libretroTitle"] as String? == "\(folder)/Named_Titles/Super Metroid (USA).png")
    }

    @Test func aROMIsLookedUpOnceAndNewROMsAtLaterImports() async throws {
        try oe.addROM("Super Metroid (USA)", md5: "aa")
        try await firstImport()
        try oe.addROM("Super Mario World (USA)", md5: "zz")
        h.internet.resetSent()

        try await ongoingImport()

        #expect(try roms()[1]["libretroBoxart"] as String? != nil)
        #expect(h.internet.sent(to: FakeInternet.Hosts.github).isEmpty)  // the listing is cached
    }

    @Test func whenLibretroIsUnreachableTheImportStillCommitsAndTheNextOneLooksItUp() async throws {
        try oe.addROM("Super Metroid (USA)", md5: "aa")
        h.internet.setDown(FakeInternet.Hosts.github, true)
        try await firstImport()
        #expect(try roms()[0]["libretroLookedUp"] as Bool == false)

        h.internet.setDown(FakeInternet.Hosts.github, false)
        try await ongoingImport()

        #expect(try roms()[0]["libretroBoxart"] as String? != nil)
    }

    @Test func openEmusBoxArtIsCopiedAtEveryImportAndComesBackAfterAWipedCache() async throws {
        try oe.addROM("Super Metroid (USA)", md5: "aa")
        try await firstImport()
        let art = testImage(width: 30, height: 40)
        let pk = try oe.addROM("Super Mario World (USA)", md5: "zz", boxArt: art)

        try await ongoingImport()
        #expect(try roms()[1]["openEmuBoxArt"] as String? == "ART-\(pk)")
        let cached = try #require(h.cache.cachedImage(at: "openemu/ART-\(pk)"))
        #expect(try Data(contentsOf: cached) == art)

        try FileManager.default.removeItem(at: cached)
        try await ongoingImport()
        #expect(h.cache.cachedImage(at: "openemu/ART-\(pk)") != nil)
    }
}

/// The migration that ships box-art Covers, on a journal written by the first spec.
@Suite struct BoxArtMigrationTests {
    @Test func carriedOverCoversAreDeletedAndUploadsKept() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "migration \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let db = try DatabaseQueue(path: directory.appending(path: "journal.sqlite").path(percentEncoded: false))
        try JournalSchema.migrator.migrate(db, upTo: "v1")
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO platform VALUES (19, 'SNES');
                    INSERT INTO game (id, platformId, name) VALUES (1, 19, 'Carried'), (2, 19, 'Uploaded');
                    INSERT INTO cover VALUES (1, x'00', 1, 1, 'carried', 'a'), (2, x'01', 2, 3, 'uploaded', 'b');
                    """)
        }
        try db.close()

        let journal = try JournalStore(directory: directory)

        #expect(try journal.uploadedCover(1) == nil)
        #expect(try journal.uploadedCover(2) == NormalisedCover(jpeg: Data([1]), width: 2, height: 3, sha256: "b"))
    }
}
