import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// `migrate-openemu` against a fixture OpenEmu library and a journal that points into it.
@Suite struct OpenEmuMigrationTests {
    let h: Harness
    let j: LudeumHarness
    let openEmu: FakeOpenEmu
    let roms: URL
    let backupFolder: URL

    init() throws {
        h = try Harness()
        j = try LudeumHarness(beforeOpenEmuMigration: true)
        // OpenEmu keeps its library inside its Application Support folder, beside each core's saves.
        let support = j.directory.appending(path: "OpenEmu", directoryHint: .isDirectory)
        openEmu = try FakeOpenEmu(in: support)
        roms = j.directory.appending(path: "games", directoryHint: .isDirectory)
        backupFolder = j.directory.appending(path: "Backups", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: roms, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
    }

    func migration(openEmuRunning: Bool = false) -> OpenEmuMigration {
        OpenEmuMigration(
            journal: j.journal, library: openEmu.folder, romFolder: { ROMPlatform.all[$0].map { roms.appending(path: $0.folderName) } },
            backups: Backups(folder: backupFolder, fallback: backupFolder, clock: j.clock, timeZone: j.timeZone),
            isOpenEmuRunning: { openEmuRunning }, libretro: h.libretro)
    }

    func game(_ name: String, platform: Int64) throws -> GameID {
        try j.journal.addPlatform(id: platform, name: ROMPlatform.all[platform]?.name ?? "Platform \(platform)")
        return try j.journal.addGame(platformId: platform, name: name)
    }

    /// An OpenEmu ROM the journal has Matched to `game`.
    @discardableResult
    func matched(_ name: String, system: String, fileName: String?, to game: GameID) throws -> Int64 {
        let pk = try openEmu.addROM(name, md5: "md5-\(name)", system: system, fileName: fileName)
        try j.journal.db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO rom (openEmuPk, md5, fileName, platformId, missing, gameId, matchKind, matchedAt)
                    SELECT ?, ?, ?, platformId, ?, id, 'manual', 0 FROM game WHERE id = ?
                    """, arguments: [pk, "md5-\(name)", "\(pk)-\(fileName ?? "missing.sfc")", fileName == nil, game])
        }
        return pk
    }

    /// An OpenEmu ROM waiting in the Review queue, as an Import leaves it.
    @discardableResult
    func unmatched(_ name: String, system: String, fileName: String) throws -> Int64 {
        let pk = try openEmu.addROM(name, md5: "md5-\(name)", system: system, fileName: fileName)
        try j.journal.db.write { db in
            let platform = ROMPlatform.defaultPlatform(system: system)!
            try ROMPlatform.ensureKnown(db, platform)
            try db.execute(
                sql: "INSERT INTO rom (openEmuPk, md5, fileName, name, platformId) VALUES (?, ?, ?, ?, ?)",
                arguments: [pk, "md5-\(name)", "\(pk)-\(fileName)", name, platform])
            try db.execute(
                sql: "INSERT INTO heldOpenEmuData (romId, collections) VALUES (?, '[]')", arguments: [db.lastInsertedRowID])
        }
        return pk
    }

    func exists(_ path: String, in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: path).path(percentEncoded: false))
    }

    @Test func aMatchedROMMovesToItsGamesPlatformFolderAndIsKnownByItsName() async throws {
        let gold = try game("Pokemon Gold", platform: 22)
        try matched("Pokemon Gold", system: "openemu.system.gb", fileName: "Pokemon Gold (USA).gbc", to: gold)

        try await migration().run()

        #expect(exists("Game Boy Color/1-Pokemon Gold (USA).gbc", in: roms))
        #expect(!exists("roms/openemu.system.gb/1-Pokemon Gold (USA).gbc", in: openEmu.folder))
        let rom = try #require(try j.journal.roms(of: gold).first)
        #expect(rom.platformId == 22)
        #expect(rom.folderName == "1-Pokemon Gold (USA)")
        #expect(rom.fileName == "1-Pokemon Gold (USA).gbc")
        #expect(!rom.missing)
        #expect(try await j.journal.db.read { try String.fetchOne($0, sql: "SELECT md5 FROM rom") } == "md5-Pokemon Gold")
    }

    @Test func anUnmatchedROMGoesToItsSystemsDefaultPlatformAndStaysInReview() async throws {
        try unmatched("Tetris", system: "openemu.system.gb", fileName: "Tetris.gb")

        try await migration().run()

        #expect(exists("Game Boy/1-Tetris.gb", in: roms))
        let item = try #require(try j.journal.reviewQueue().noSuggestion.first)
        #expect(item.platformId == 33)
        #expect(try await j.journal.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM heldOpenEmuData") } == 1)
    }

    @Test func aMissingROMIsKeyedByItsOpenEmuFileNameAndStaysMissing() async throws {
        let metroid = try game("Super Metroid", platform: 19)
        try matched("Super Metroid", system: "openemu.system.snes", fileName: nil, to: metroid)

        let result = try await migration().run()

        let rom = try #require(try j.journal.roms(of: metroid).first)
        #expect(rom.missing)
        #expect(rom.folderName == "1-missing")
        #expect(rom.platformId == 19)
        #expect(result.plan.roms.first?.moves == [])
    }

    @Test func aCueSheetMovesWithItsTracks() async throws {
        let ff = try game("Final Fantasy VII", platform: 7)
        let pk = try matched("Final Fantasy VII", system: "openemu.system.psx", fileName: "FF7.cue", to: ff)
        let folder = openEmu.folder.appending(path: "roms/openemu.system.psx")
        try "FILE \"\(pk)-FF7 (Track 1).bin\" BINARY\n".write(
            to: folder.appending(path: "\(pk)-FF7.cue"), atomically: true, encoding: .utf8)
        try Data("track".utf8).write(to: folder.appending(path: "\(pk)-FF7 (Track 1).bin"))

        try await migration().run()

        #expect(exists("PS1/1-FF7.cue", in: roms))
        #expect(exists("PS1/1-FF7 (Track 1).bin", in: roms))
    }

    @Test func theDryRunSaysWhatItWouldDoAndChangesNothing() async throws {
        let gold = try game("Pokemon Gold", platform: 22)
        try matched("Pokemon Gold", system: "openemu.system.gb", fileName: "Gold.gbc", to: gold)

        let plan = try migration().plan()

        #expect(plan.isRunnable)
        #expect(plan.roms.map(\.moves.first?.to) == [roms.appending(path: "Game Boy Color/1-Gold.gbc")])
        #expect(exists("roms/openemu.system.gb/1-Gold.gbc", in: openEmu.folder))
        #expect(try await j.journal.db.read { try Int64.fetchOne($0, sql: "SELECT openEmuPk FROM rom") } == 1)
        #expect(try Backups(folder: backupFolder, fallback: backupFolder).all().isEmpty)
    }

    @Test func itRefusesWhileOpenEmuIsRunning() async throws {
        await #expect(throws: OpenEmuMigrationError.openEmuRunning) { try await migration(openEmuRunning: true).run() }
    }

    @Test func aFileNameClashRefusesBeforeAnythingIsTouched() async throws {
        let gold = try game("Pokemon Gold", platform: 22)
        try matched("Pokemon Gold", system: "openemu.system.gb", fileName: "Gold.gbc", to: gold)
        try FileManager.default.createDirectory(at: roms.appending(path: "Game Boy Color"), withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: roms.appending(path: "Game Boy Color/1-Gold.gbc"))

        await #expect {
            try await migration().run()
        } throws: { error in
            guard case .blocked(let plan) = error as? OpenEmuMigrationError else { return false }
            return plan.clashes == ["Game Boy Color/1-Gold.gbc: a file is already there"]
        }
        #expect(exists("roms/openemu.system.gb/1-Gold.gbc", in: openEmu.folder))
        #expect(try await j.journal.db.read { try Int64.fetchOne($0, sql: "SELECT openEmuPk FROM rom") } == 1)
        #expect(try Backups(folder: backupFolder, fallback: backupFolder).all().isEmpty)
    }

    @Test func aGameOnAPlatformItsSystemCantHoldStopsTheMigration() async throws {
        let doom = try game("Doom", platform: 6)
        try matched("Doom", system: "openemu.system.snes", fileName: "Doom.sfc", to: doom)

        let plan = try migration().plan()

        #expect(!plan.isRunnable)
        #expect(plan.platformMismatches.count == 1)
    }

    @Test func itBacksUpLogsEachMoveAndDropsOpenEmusLinkTables() async throws {
        let gold = try game("Pokemon Gold", platform: 22)
        try matched("Pokemon Gold", system: "openemu.system.gb", fileName: "Gold.gbc", to: gold)

        let result = try await migration().run()

        #expect(try Backups(folder: backupFolder, fallback: backupFolder).all().map(\.operation) == [.beforeMigration])
        let log = try String(contentsOf: result.log, encoding: .utf8)
        let from = openEmu.folder.appending(path: "roms/openemu.system.gb/1-Gold.gbc").path(percentEncoded: false)
        let to = roms.appending(path: "Game Boy Color/1-Gold.gbc").path(percentEncoded: false)
        #expect(log == "\(from)\t\(to)\n")
        for table in ["syncedCollection", "syncedCover", "openEmuLibrary"] {
            #expect(try await j.journal.db.read { try $0.tableExists(table) } == false)
        }
        #expect(try await j.journal.db.read { try $0.tableExists("heldOpenEmuData") })
    }

    @Test func afterwardsTheJournalNoLongerUsesOpenEmu() async throws {
        let gold = try game("Pokemon Gold", platform: 22)
        try matched("Pokemon Gold", system: "openemu.system.gb", fileName: "Gold.gbc", to: gold)
        #expect(try j.journal.needsOpenEmuMigration())

        try await migration().run()

        #expect(try !j.journal.needsOpenEmuMigration())
        #expect(try await j.journal.db.read { try $0.columns(in: "rom").map(\.name) }.contains("openEmuPk") == false)
        try j.reopen()
        #expect(try j.journal.roms(of: gold).map(\.folderName) == ["1-Gold"])
    }

    @Test func aJournalAlreadyMigratedIsLeftAlone() async throws {
        try await migration().run()

        #expect(throws: OpenEmuMigrationError.alreadyMigrated) { try migration().plan() }
    }

    @Test func batterySavesAreCopiedUnchangedIntoAnArchive() async throws {
        let saves = openEmu.folder.deletingLastPathComponent().appending(path: "Gambatte/Battery Saves")
        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        try Data("save".utf8).write(to: saves.appending(path: "Pokemon Gold.sav"))
        let states = openEmu.folder.deletingLastPathComponent().appending(path: "Save States/Gambatte")
        try FileManager.default.createDirectory(at: states, withIntermediateDirectories: true)

        let result = try await migration().run()

        let archived = result.batterySaveArchive.appending(path: "Gambatte/Battery Saves/Pokemon Gold.sav")
        #expect(try Data(contentsOf: archived) == Data("save".utf8))
        #expect(FileManager.default.fileExists(atPath: saves.appending(path: "Pokemon Gold.sav").path(percentEncoded: false)))
        #expect(
            !FileManager.default.fileExists(atPath: result.batterySaveArchive.appending(path: "Save States").path(percentEncoded: false)))
    }

    @Test func openEmuROMsWithNoJournalEntryAreListedAndLeftInPlace() async throws {
        try openEmu.addROM("Stray", md5: "aa", system: "openemu.system.nes", fileName: "Stray.nes")

        let result = try await migration().run()

        let stray = openEmu.folder.appending(path: "roms/openemu.system.nes/1-Stray.nes")
        #expect(result.plan.leftInOpenEmu.map(\.lastPathComponent) == ["1-Stray.nes"])
        #expect(FileManager.default.fileExists(atPath: stray.path(percentEncoded: false)))
    }

    // MARK: Box art

    /// Super Metroid, Matched and already looked up in libretro, with `old` as its Box art.
    func lookedUpMetroid(old: String) throws {
        try j.journal.addPlatform(id: 19, name: "SNES")
        let metroid = try j.journal.addGame(platformId: 19, name: "Super Metroid", igdbGameId: 1103, igdbName: "Super Metroid")
        try matched("Super Metroid", system: "openemu.system.snes", fileName: "Super Metroid (USA).sfc", to: metroid)
        try j.journal.db.write { try $0.execute(sql: "UPDATE rom SET libretroLookedUp = 1, libretroBoxart = ?", arguments: [old]) }
    }

    func boxArt() throws -> String? {
        try j.journal.db.read { try String.fetchOne($0, sql: "SELECT libretroBoxart FROM rom") }
    }

    @Test func aMovedROMsNameIsItsNewFileNames() async throws {
        let gold = try game("Pokemon Gold", platform: 22)
        try matched("Pokemon Gold", system: "openemu.system.gb", fileName: "Pokemon Gold (USA).gbc", to: gold)

        try await migration().run()

        #expect(try await j.journal.db.read { try String.fetchOne($0, sql: "SELECT name FROM rom") } == "1-Pokemon Gold (USA)")
    }

    @Test func libretroIsLookedUpAgainAndANewMatchReplacesTheOld() async throws {
        h.internet.addLibretro("Nintendo_-_Super_Nintendo_Entertainment_System", ["Super Metroid (USA)"])
        try lookedUpMetroid(old: "old.png")

        try await migration().run()

        #expect(try boxArt() == "Nintendo - Super Nintendo Entertainment System/Named_Boxarts/Super Metroid (USA).png")
    }

    @Test func aLibretroMissKeepsTheOldBoxArt() async throws {
        h.internet.addLibretro("Nintendo_-_Super_Nintendo_Entertainment_System", ["Super Mario World (USA)"])
        try lookedUpMetroid(old: "old.png")

        try await migration().run()

        #expect(try boxArt() == "old.png")
    }

    func lookedUp() throws -> Bool {
        try j.journal.db.read { try Bool.fetchOne($0, sql: "SELECT libretroLookedUp FROM rom")! }
    }

    @Test func aLookupThatFailsIsLeftForTheNextImportWhichStillKeepsTheOldBoxArtOnAMiss() async throws {
        h.internet.addLibretro("Nintendo_-_Super_Nintendo_Entertainment_System", ["Super Mario World (USA)"])
        try lookedUpMetroid(old: "old.png")
        h.internet.setDown(FakeInternet.Hosts.github, true)

        try await migration().run()

        #expect(try !lookedUp())
        #expect(try boxArt() == "old.png")

        h.internet.setDown(FakeInternet.Hosts.github, false)
        _ = try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil, libretro: h.libretro)
            .run(romFolders: [])

        #expect(try lookedUp())
        #expect(try boxArt() == "old.png")
    }

    @Test func openEmusCachedBoxArtIsDeleted() async throws {
        _ = try h.cache.store(image: Data("art".utf8), at: "openemu/ART-1")

        try await migration().run()

        #expect(h.cache.cachedImage(at: "openemu/ART-1") == nil)
    }
}

/// A journal opened by this build before `migrate-openemu` has moved its OpenEmu ROMs.
@Suite struct UnmigratedJournalTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "unmigrated \(UUID().uuidString)", directoryHint: .isDirectory)

    /// A journal from the build before OpenEmu went, with `setUp` run against it, then opened by this one.
    func journal(_ setUp: (Database) throws -> Void) throws -> LudeumStore {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let db = try DatabaseQueue(path: directory.appending(path: "journal.sqlite").path(percentEncoded: false))
        try LudeumSchema.migrator.migrate(db, upTo: "v15 no openemu box art")
        try db.write(setUp)
        try db.close()
        return try LudeumStore(directory: directory)
    }

    func openEmuROM(_ db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO platform VALUES (19, 'SNES');
                INSERT INTO game (id, platformId, name) VALUES (1, 19, 'Super Metroid');
                INSERT INTO rom (openEmuPk, md5, fileName, platformId, gameId, matchKind, matchedAt)
                    VALUES (10, 'aa', 'Super Metroid.sfc', 19, 1, 'manual', 0);
                INSERT INTO syncedCollection (openEmuPk, special) VALUES (5, '_TODO');
                """)
    }

    @Test func itWaitsForMigrateOpenEmuWithItsOpenEmuROMsUntouched() throws {
        let journal = try journal(openEmuROM)

        #expect(try journal.needsOpenEmuMigration())
        #expect(try journal.db.read { try Int64.fetchOne($0, sql: "SELECT openEmuPk FROM rom WHERE gameId = 1") } == 10)
        #expect(try journal.db.read { try $0.tableExists("syncedCollection") })
        #expect(try journal.roms(of: 1).map(\.fileName) == ["Super Metroid.sfc"])
    }

    @Test func itsImportIsRefused() async throws {
        let h = try Harness()
        let journal = try journal(openEmuROM)
        let snes = try FakeROMFolder(in: directory, platform: 19)
        try snes.add("Super Metroid (USA).sfc")

        await #expect(throws: ImportError.openEmuMigrationNeeded) {
            try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: journal, backups: nil).run(romFolders: [snes.folder])
        }
        #expect(try journal.reviewQueue().count == 0)
    }

    @Test func oneWithNoOpenEmuROMsDropsOpenEmuStraightAway() throws {
        let journal = try journal { db in
            try db.execute(
                sql: """
                    INSERT INTO platform VALUES (8, 'PlayStation 2');
                    INSERT INTO rom (folderName, fileName, platformId) VALUES ('Okami (USA)', 'Okami (USA).iso', 8);
                    """)
        }

        #expect(try !journal.needsOpenEmuMigration())
        #expect(try journal.db.read { try $0.columns(in: "rom").map(\.name) }.contains("openEmuPk") == false)
        #expect(try journal.db.read { try $0.tableExists("syncedCollection") } == false)
        #expect(throws: DatabaseError.self) {
            try journal.db.write { try $0.execute(sql: "INSERT INTO rom (fileName, platformId) VALUES ('Ico.iso', 8)") }
        }
    }
}
