import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// The Box art step of each Import: libretro lookups.
@Suite struct BoxArtImportTests {
    let h: Harness
    let j: LudeumHarness
    let snes: FakeROMFolder

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        snes = try FakeROMFolder(in: h.directory, platform: 19)
        h.internet.addPlatform(19, "SNES")
        h.internet.addLibretro("Nintendo_-_Super_Nintendo_Entertainment_System", ["Super Metroid (USA)", "Super Mario World (USA)"])
    }

    func importNow() async throws {
        _ = try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil, libretro: h.libretro)
            .run(romFolders: [snes.folder])
    }

    func roms() throws -> [Row] {
        try j.journal.db.read { try Row.fetchAll($0, sql: "SELECT * FROM rom ORDER BY id") }
    }

    @Test func everyROMKeepsItsLibretroNames() async throws {
        try snes.add("Super Metroid (USA).sfc")
        try snes.add("Super Mario World (USA).sfc")
        try await importNow()

        let rows = try roms()
        let folder = "Nintendo - Super Nintendo Entertainment System"
        #expect(
            rows.map { $0["libretroBoxart"] as String? } == [
                "\(folder)/Named_Boxarts/Super Mario World (USA).png", "\(folder)/Named_Boxarts/Super Metroid (USA).png",
            ])
        #expect(rows[1]["libretroSnap"] as String? == "\(folder)/Named_Snaps/Super Metroid (USA).png")
        #expect(rows[1]["libretroTitle"] as String? == "\(folder)/Named_Titles/Super Metroid (USA).png")
    }

    @Test func aROMIsLookedUpOnceAndNewROMsAtLaterImports() async throws {
        try snes.add("Super Metroid (USA).sfc")
        try await importNow()
        try snes.add("Super Mario World (USA).sfc")
        h.internet.resetSent()

        try await importNow()

        #expect(try roms()[1]["libretroBoxart"] as String? != nil)
        #expect(h.internet.sent(to: FakeInternet.Hosts.github).isEmpty)  // the listing is cached
    }

    @Test func itSaysWhetherAnyROMsBoxArtChanged() async throws {
        try snes.add("Super Metroid (USA).sfc")
        try snes.add("Homebrew Nobody Scanned.sfc")
        _ = try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil).run(romFolders: [snes.folder])
        let boxArt = BoxArtImport(journal: j.journal, libretro: h.libretro)

        #expect(await boxArt.run())
        // Nothing left to look up.
        #expect(await boxArt.run() == false)
        // Looked up again, each ROM finds the Box art it has.
        #expect(try await boxArt.boxArtChanges(lookingUp: try roms().map { $0["id"] }) == false)
    }

    @Test func anImportSaysWhetherAnyCoverMayHaveChanged() async throws {
        try snes.add("Super Metroid (USA).sfc")
        let run = Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil, libretro: h.libretro)

        #expect(try await run.run(romFolders: [snes.folder]).coversChanged)
        // Nothing new, so every Cover is as it was.
        #expect(try await run.run(romFolders: [snes.folder]).coversChanged == false)
    }

    @Test func whenLibretroIsUnreachableTheImportStillCommitsAndTheNextOneLooksItUp() async throws {
        try snes.add("Super Metroid (USA).sfc")
        h.internet.setDown(FakeInternet.Hosts.github, true)
        try await importNow()
        #expect(try roms()[0]["libretroLookedUp"] as Bool == false)

        h.internet.setDown(FakeInternet.Hosts.github, false)
        try await importNow()

        #expect(try roms()[0]["libretroBoxart"] as String? != nil)
    }

    @Test func aFailedLookupLeavesThatROMForNextTimeAndTheRestAreStillLookedUp() async throws {
        // libretro has no listing for NES here, so its lookup fails.
        let nes = try FakeROMFolder(in: h.directory, platform: 18)
        try nes.add("Metroid (USA).nes")
        try snes.add("Super Metroid (USA).sfc")

        _ = try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil, libretro: h.libretro)
            .run(romFolders: [nes.folder, snes.folder])

        let rows = try roms()
        #expect(rows.map { $0["libretroLookedUp"] as Bool } == [false, true])
        #expect(rows[1]["libretroBoxart"] as String? != nil)
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
        try LudeumSchema.migrator.migrate(db, upTo: "v1")
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO platform VALUES (19, 'SNES');
                    INSERT INTO game (id, platformId, name) VALUES (1, 19, 'Carried'), (2, 19, 'Uploaded');
                    INSERT INTO cover VALUES (1, x'00', 1, 1, 'carried', 'a'), (2, x'01', 2, 3, 'uploaded', 'b');
                    """)
        }
        try db.close()

        let journal = try LudeumStore(directory: directory)

        #expect(try journal.uploadedCover(1) == nil)
        #expect(try journal.uploadedCover(2) == NormalisedCover(jpeg: Data([1]), width: 2, height: 3, sha256: "b"))
    }
}
