import CryptoKit
import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// The Regions step of each Import: a ROM whose name has no region tag takes the Regions of the DAT entry its checksum
/// is.
@Suite struct RegionsImportTests {
    let h: Harness
    let j: LudeumHarness
    let snes: FakeROMFolder

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        snes = try FakeROMFolder(in: h.directory, platform: 19)
        h.internet.addPlatform(19, "SNES")
    }

    /// Puts a ROM file in the SNES folder, and has Hasheous know its checksum as the DAT entry `romName` with `country`.
    func add(_ fileName: String, known romName: String? = nil, country: [String: String] = [:]) throws {
        try snes.add(fileName, fileName)
        let md5 = Insecure.MD5.hash(data: Data(fileName.utf8)).map { String(format: "%02x", $0) }.joined()
        if romName != nil || !country.isEmpty { h.internet.addHash(md5: md5, game: 1, platform: 19, romName: romName, country: country) }
    }

    @discardableResult
    func importNow() async throws -> ImportResult {
        try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil).run(addingEveryFileIn: [snes.folder])
    }

    func regions() throws -> [String?] {
        try j.journal.db.read { try String?.fetchAll($0, sql: "SELECT regions FROM rom ORDER BY folderName") }
    }

    @Test func aNewROMWithNoRegionTagTakesItsDATEntrysRegions() async throws {
        try add("Super Metroid.sfc", known: "Super Metroid (Japan, USA) (En).sfc")
        try add("Gods.sfc", known: "Gods (1992)(Mindscape)(US)[a].bin", country: ["US": "United States"])
        try add("Super Mario World (Europe).sfc", known: "Super Mario World (USA).sfc")

        try await importNow()

        #expect(try regions() == [#"["USA"]"#, #"["Europe"]"#, #"["USA","Japan"]"#])
    }

    /// A ROM already in the journal, with a checksum and no Regions, not yet looked up: as every such ROM was after the
    /// `v37` migration.
    func romInTheJournal(md5: String, named name: String = "Super Metroid") async throws {
        let game = try j.addGame(name)
        try j.journal.recordROM(game: game, fileName: "\(name).sfc", missing: true)
        try await j.journal.db.write {
            try $0.execute(sql: "UPDATE rom SET md5 = ? WHERE folderName = ?", arguments: [md5, name])
        }
    }

    @Test func aROMAlreadyInTheJournalWithNoRegionsTakesThemAtTheNextImportAndItsCoverMayChange() async throws {
        try await romInTheJournal(md5: "aa")
        h.internet.addHash(md5: "aa", game: 1, platform: 19, romName: "Super Metroid (Europe).sfc")

        let result = try await importNow()

        #expect(try regions() == [#"["Europe"]"#])
        #expect(result.coversChanged)
    }

    @Test func aROMHasheousDoesntKnowIsLookedUpOnceNotAtEveryImport() async throws {
        try add("Homebrew.sfc")
        try await importNow()
        h.internet.resetSent()

        try await importNow()

        #expect(try regions() == [nil])
        #expect(h.internet.sent(to: FakeInternet.Hosts.hasheous).isEmpty)
    }

    @Test func aROMWhoseLookupFailsIsLookedUpAgainAtTheNextImport() async throws {
        try await romInTheJournal(md5: "aa")
        h.internet.addHash(md5: "aa", game: 1, platform: 19, romName: "Super Metroid (Europe).sfc")
        h.internet.setDown(FakeInternet.Hosts.hasheous, true)
        try await importNow()
        #expect(try regions() == [nil])

        h.internet.setDown(FakeInternet.Hosts.hasheous, false)
        try await importNow()

        #expect(try regions() == [#"["Europe"]"#])
    }

    @Test func aROMWhoseLookupKeepsFailingDoesntHoldUpTheOthers() async throws {
        try await romInTheJournal(md5: "aa", named: "Gods")
        try await romInTheJournal(md5: "bb")
        h.internet.state.withLock { $0.failingHashes = ["md5/aa"] }
        h.internet.addHash(md5: "bb", game: 1, platform: 19, romName: "Super Metroid (Europe).sfc")

        try await importNow()

        #expect(try regions() == [nil, #"["Europe"]"#])
    }

    @Test func aROMsRegionsClearedByHandStayCleared() async throws {
        try add("Super Metroid (USA).sfc", known: "Super Metroid (Europe).sfc")
        try await importNow()
        let rom = try #require(try j.journal.romID(named: "Super Metroid (USA)", on: 19))

        try j.journal.setROMDetails(rom, CopyDetails(regions: []))
        try await importNow()

        #expect(try regions() == [nil])
    }

    @Test func aROMWithRegionsOrNoChecksumIsNeverLookedUp() async throws {
        try add("Super Metroid (USA).sfc", known: "Super Metroid (Europe).sfc")
        try await importNow()
        let game = try j.journal.addGame(platformId: 19, name: "Gods")
        try j.journal.recordROM(game: game, fileName: "Gods.sfc", missing: true)
        h.internet.resetSent()

        try await importNow()

        #expect(try regions() == [nil, #"["USA"]"#])
        #expect(h.internet.sent(to: FakeInternet.Hosts.hasheous).isEmpty)
    }
}

/// The `v37` migration: every ROM with no Regions is to be looked up, unless its name has tags `v22` couldn't read
/// and the name reader now can, which give it them.
@Suite struct RegionsLookedUpMigrationTests {
    @Test func aROMWithNoRegionsIsToBeLookedUpUnlessItsNameNowSaysThem() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "migration \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let db = try DatabaseQueue(path: directory.appending(path: "journal.sqlite").path(percentEncoded: false))
        try LudeumSchema.migrator.migrate(db, upTo: "v36 stray files")
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO platform (id, name) VALUES (29, 'Genesis');
                    INSERT INTO rom (id, platformId, folderName, fileName, name, regions) VALUES
                        (1, 29, 'Altered Beast', 'Altered Beast.md', 'Altered Beast', NULL),
                        (2, 29, 'Urban Strike (UEJ) [!]', 'Urban Strike (UEJ) [!].md', 'Urban Strike (UEJ) [!]', NULL),
                        (3, 29, 'Sonic (USA)', 'Sonic (USA).md', 'Sonic (USA)', '["USA"]');
                    """)
        }
        try db.close()

        let journal = try LudeumStore(directory: directory)

        let rows = try journal.db.read { try Row.fetchAll($0, sql: "SELECT regions, regionsLookedUp FROM rom ORDER BY id") }
        #expect(rows.map { $0["regions"] as String? } == [nil, #"["Europe","USA","Japan"]"#, #"["USA"]"#])
        #expect(rows.map { $0["regionsLookedUp"] as Bool } == [false, false, false])
    }
}

/// A PlayStation ROM with no region tag takes its Regions from its Discs' Serials, ahead of Hasheous.
@Suite struct RegionsFromSerialsTests {
    let h: Harness
    let j: LudeumHarness
    let ps1: FakeROMFolder

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        ps1 = try FakeROMFolder(in: h.directory, platform: ROMPlatform.ps1)
        h.internet.addPlatform(Int(ROMPlatform.ps1), "PlayStation")
    }

    func importNow() async throws {
        _ = try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil).run(addingEveryFileIn: [ps1.folder])
    }

    func regions() throws -> [String: String?] {
        try j.journal.db.read { db in
            try Row.fetchAll(db, sql: "SELECT folderName, regions FROM rom").reduce(into: [:]) {
                $0[$1["folderName"] as String] = .some($1["regions"] as String?)
            }
        }
    }

    /// Has Hasheous know a disc's data track as the DAT entry `romName`.
    func hasheousKnows(_ track: String, as romName: String) throws {
        let data = try Data(contentsOf: ps1.url.appending(path: track))
        let md5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        h.internet.addHash(md5: md5, game: 1, platform: Int(ROMPlatform.ps1), romName: romName)
    }

    @Test func aROMWithNoRegionTagTakesItsSerialsRegionWithoutHasheousBeingAsked() async throws {
        try ps1.addDisc("Crash Bandicoot", booting: "SCUS-94900", in: "Crash Bandicoot")
        try hasheousKnows("Crash Bandicoot/Crash Bandicoot.bin", as: "Crash Bandicoot (Europe).bin")
        try await importNow()
        #expect(try regions() == ["Crash Bandicoot": #"["USA"]"#])

        // To be given Regions again, as `ludeum-import checksums` left a ROM whose checksum changed.
        try await j.journal.db.write { try $0.execute(sql: "UPDATE rom SET regions = NULL, regionsLookedUp = 0") }
        h.internet.resetSent()
        try await importNow()

        #expect(try regions() == ["Crash Bandicoot": #"["USA"]"#])
        #expect(h.internet.sent(to: FakeInternet.Hosts.hasheous).isEmpty)
    }

    @Test func aRegionTagComesFirstAsItCanSayMoreThanASerial() async throws {
        try ps1.addDisc("Brian Lara Cricket (Australia)", booting: "SLES-01576", in: "Brian Lara Cricket (Australia)")

        try await importNow()

        #expect(try regions() == ["Brian Lara Cricket (Australia)": #"["Australia"]"#])
    }

    @Test func aSerialWhosePrefixSaysNoRegionFallsBackToHasheous() async throws {
        // SCPS is Japan's, and Sony's Asian discs' too.
        try ps1.addDisc("Suikoden", booting: "SCPS-45184", in: "Suikoden")
        try hasheousKnows("Suikoden/Suikoden.bin", as: "Suikoden (Asia).bin")
        try ps1.addDisc("Demo", booting: nil, in: "Demo")
        try hasheousKnows("Demo/Demo.bin", as: "Demo (Europe).bin")

        try await importNow()

        #expect(try regions() == ["Suikoden": #"["Asia"]"#, "Demo": #"["Europe"]"#])
    }

    @Test func aMultiDiscROMTakesEachDiscsRegionOnce() async throws {
        let folder = "Game"
        for (disc, serial) in [(1, "SLUS-00101"), (2, "SLES-00102"), (3, "SCUS-00103")] {
            try ps1.addDisc("Game (Disc \(disc))", booting: serial, in: folder)
        }
        try ps1.add("\(folder)/Game.m3u", "Game (Disc 1).cue\nGame (Disc 2).cue\nGame (Disc 3).cue\n")

        try await importNow()

        #expect(try regions() == [folder: #"["Europe","USA"]"#])
    }

    /// A PlayStation ROM already in the journal, missing, with no Regions and not yet given them.
    func romInTheJournal(_ name: String, serials: String?, serialsLookedUp: Bool = true, md5: String? = nil) async throws -> Int64 {
        try j.journal.addPlatform(id: ROMPlatform.ps1, name: "PlayStation")
        let game = try j.journal.addGame(platformId: ROMPlatform.ps1, name: name)
        try j.journal.recordROM(game: game, fileName: "\(name).cue", missing: true)
        return try await j.journal.db.write { db in
            try db.execute(
                sql: "UPDATE rom SET serials = ?, serialsLookedUp = ?, md5 = ? WHERE folderName = ?",
                arguments: [serials, serialsLookedUp, md5, name])
            return try Int64.fetchOne(db, sql: "SELECT id FROM rom WHERE folderName = ?", arguments: [name])!
        }
    }

    @Test func aROMWhoseCopyDetailsIveEditedIsNeverGivenRegionsByItsSerial() async throws {
        let crash = try await romInTheJournal("Crash Bandicoot", serials: #"["SCUS-94900"]"#)
        _ = try await romInTheJournal("Spyro the Dragon", serials: #"["SCUS-94228"]"#)
        try j.journal.setROMDetails(crash, CopyDetails(regions: []))

        try await importNow()

        #expect(try regions() == ["Crash Bandicoot": nil, "Spyro the Dragon": #"["USA"]"#])
    }

    @Test func aROMWhoseSerialsArentReadYetWaitsForThemRatherThanAskingHasheous() async throws {
        _ = try await romInTheJournal("Crash Bandicoot", serials: nil, serialsLookedUp: false, md5: "aa")
        h.internet.addHash(md5: "aa", game: 1, platform: Int(ROMPlatform.ps1), romName: "Crash Bandicoot (Europe).bin")

        try await importNow()

        #expect(try regions() == ["Crash Bandicoot": nil])
        #expect(h.internet.sent(to: FakeInternet.Hosts.hasheous).isEmpty)
    }
}
