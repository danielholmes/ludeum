import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// `recover-openemu-renamed` after `migrate-openemu`, against a fixture OpenEmu library whose database still names files
/// that were renamed on disk after OpenEmu recorded them.
@Suite struct OpenEmuRecoveryTests {
    let h: Harness
    let j: LudeumHarness
    let openEmu: FakeOpenEmu
    /// Stands in for the Data folder: the real one is never touched.
    let data: URL
    var roms: URL { data.appending(path: "ROMs", directoryHint: .isDirectory) }
    var folder: LudeumFolder { LudeumFolder(url: j.directory, data: data) }

    init() throws {
        h = try Harness()
        j = try LudeumHarness(beforeOpenEmuMigration: true)
        openEmu = try FakeOpenEmu(in: j.directory.appending(path: "Home", directoryHint: .isDirectory))
        data = j.directory.appending(path: "Data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
    }

    /// A ROM OpenEmu recorded at `location` (under `roms/`), Matched to a Game on `platform` and already looked up in
    /// libretro, as the first Import left it: missing when there's no file there. Returns its journal id.
    @discardableResult
    func recorded(
        _ location: String, system: String, platform: Int64, archiveFileName: String? = nil, game: GameID? = nil
    ) throws -> Int64 {
        let name = ((location as NSString).lastPathComponent as NSString).deletingPathExtension
        let pk = try openEmu.addROM(name, md5: "md5-\(location)", system: system, location: location, archiveFileName: archiveFileName)
        let missing = !FileManager.default.fileExists(
            atPath: openEmu.folder.appending(path: "roms/\(location)").path(percentEncoded: false))
        try j.journal.addPlatform(id: platform, name: ROMPlatform.all[platform]?.name ?? "Platform \(platform)")
        let game = try game ?? j.journal.addGame(platformId: platform, name: name)
        return try j.journal.db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO rom (openEmuPk, md5, fileName, platformId, missing, gameId, matchKind, matchedAt, libretroLookedUp)
                    VALUES (?, ?, ?, ?, ?, ?, 'manual', 0, 1)
                    """,
                arguments: [pk, "md5-\(location)", (location as NSString).lastPathComponent, platform, missing, game])
            return db.lastInsertedRowID
        }
    }

    /// `migrate-openemu`, as already run on the live journal: it leaves a `before-migration` Backup.
    func migrateOpenEmu() async throws {
        try await OpenEmuMigration(
            journal: j.journal, library: openEmu.folder, support: openEmu.support, folder: folder, isOpenEmuRunning: { false },
            libretro: nil
        ).run()
    }

    func recovery() throws -> OpenEmuRecovery {
        let backup = try #require(try Backups(folder: folder.backups).all().first { $0.operation == .beforeMigration })
        return OpenEmuRecovery(
            journal: j.journal, library: openEmu.folder, beforeMigration: backup.url, folder: folder, isOpenEmuRunning: { false })
    }

    struct Keyed: Equatable {
        let folderName: String
        let fileName: String
        let missing: Bool
        let lookedUp: Bool
    }

    func rom(_ id: Int64) throws -> Keyed? {
        try j.journal.db.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM rom WHERE id = ?", arguments: [id]).map {
                Keyed(folderName: $0["folderName"], fileName: $0["fileName"], missing: $0["missing"], lookedUp: $0["libretroLookedUp"])
            }
        }
    }

    func exists(_ path: String, in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: path).path(percentEncoded: false))
    }

    @Test func aFileRenamedToAnotherExtensionMovesIntoItsROMFolderAndTheNextImportFindsIt() async throws {
        let tetris = try recorded("Game Boy/Tetris (World).gb", system: "openemu.system.gb", platform: 33)
        try openEmu.addFile("Game Boy/Tetris (World).7z")
        try await migrateOpenEmu()

        try await recovery().run()

        #expect(exists("Game Boy/Tetris (World).7z", in: roms))
        #expect(!exists("roms/Game Boy/Tetris (World).7z", in: openEmu.folder))
        #expect(try rom(tetris) == Keyed(folderName: "Tetris (World)", fileName: "Tetris (World).7z", missing: true, lookedUp: false))

        _ = try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil, libretro: nil)
            .run(romFolders: folder.romFolders)

        #expect(try rom(tetris)?.missing == false)
    }

    @Test func aFileThatLostOpenEmusDuplicateNumberIsFound() async throws {
        let spirit = try recorded("Game Boy/Avenging Spirit (USA, Europe) 2.7z", system: "openemu.system.gb", platform: 33)
        try openEmu.addFile("Game Boy/Avenging Spirit (USA, Europe).7z")
        try await migrateOpenEmu()

        try await recovery().run()

        #expect(exists("Game Boy/Avenging Spirit (USA, Europe).7z", in: roms))
        #expect(
            try rom(spirit)
                == Keyed(
                    folderName: "Avenging Spirit (USA, Europe)", fileName: "Avenging Spirit (USA, Europe).7z", missing: true,
                    lookedUp: false))
    }

    @Test func anArchiveUnpackedUnderTheNameOfTheFileInsideIsFound() async throws {
        let sparkster = try recorded(
            "Super Nintendo (SNES)/Sparkster.zip", system: "openemu.system.snes", platform: 19, archiveFileName: "Sparkster (USA).sfc")
        try openEmu.addFile("Super Nintendo (SNES)/Sparkster (USA).sfc")
        try await migrateOpenEmu()

        try await recovery().run()

        #expect(exists("SNES/Sparkster (USA).sfc", in: roms))
        #expect(try rom(sparkster)?.folderName == "Sparkster (USA)")
    }

    @Test func aPS1CueSheetInTheSameSubfolderOfTheOtherPlayStationFolderMovesWithItsTrack() async throws {
        let name = "Wu-Tang - Shaolin Style (USA)"
        let wuTang = try recorded("Sony PlayStation/\(name) 2/\(name).cue", system: "openemu.system.psx", platform: 7)
        // Its track named in another case, as a cue sheet may.
        let found = try openEmu.addFile("Playstation (PSX)/\(name)/\(name).cue", "FILE \"\(name).BIN\" BINARY\n")
        try openEmu.addFile("Playstation (PSX)/\(name)/\(name).bin", "track")
        // A copy in a subfolder of another name isn't one it could be.
        try openEmu.addFile("Playstation (PSX)/Wu-Tang/\(name).cue", "FILE \"\(name).bin\" BINARY\n")
        try openEmu.addFile("Playstation (PSX)/Wu-Tang/\(name).bin", "track")
        try await migrateOpenEmu()

        let result = try await recovery().run()

        #expect(result.plan.ambiguous == [])
        #expect(result.plan.roms.first?.moves.first?.from == found)
        #expect(exists("PS1/\(name).cue", in: roms))
        #expect(exists("PS1/\(name).bin", in: roms))
        #expect(try rom(wuTang) == Keyed(folderName: name, fileName: "\(name).cue", missing: true, lookedUp: false))
    }

    @Test func aROMThatCouldBeEitherOfTwoFilesIsLeftMissingWithBothInPlace() async throws {
        let tetris = try recorded("Game Boy/Tetris (World).gb", system: "openemu.system.gb", platform: 33)
        try openEmu.addFile("Game Boy/Tetris (World).gbc")
        try openEmu.addFile("Game Boy/Tetris (World).7z")
        try await migrateOpenEmu()
        let before = try rom(tetris)

        let result = try await recovery().run()

        #expect(result.plan.ambiguous == ["Game Boy/Tetris (World).gb: Game Boy/Tetris (World).7z, Game Boy/Tetris (World).gbc"])
        #expect(result.plan.roms == [])
        #expect(try rom(tetris) == before)
        #expect(exists("roms/Game Boy/Tetris (World).gbc", in: openEmu.folder))
        #expect(exists("roms/Game Boy/Tetris (World).7z", in: openEmu.folder))
    }

    @Test func aFileTwoROMsCouldBeIsNeithers() async throws {
        try recorded("Sega Mega Drive/Road Rash 2.7z", system: "openemu.system.sg", platform: 29)
        try recorded("Sega Mega Drive/Road Rash 3.7z", system: "openemu.system.sg", platform: 29)
        try openEmu.addFile("Sega Mega Drive/Road Rash.7z")
        try await migrateOpenEmu()

        let plan = try recovery().plan()

        #expect(plan.roms == [])
        #expect(
            plan.ambiguous == [
                "Sega Mega Drive/Road Rash 2.7z: Sega Mega Drive/Road Rash.7z",
                "Sega Mega Drive/Road Rash 3.7z: Sega Mega Drive/Road Rash.7z",
            ])
    }

    @Test func aFileAnotherOpenEmuROMRecordsIsntOneItCouldBe() async throws {
        try recorded("Game Boy/Wario Land (World) 2.gb", system: "openemu.system.gb", platform: 33)
        // Left in OpenEmu by migrate-openemu, with no journal entry.
        try openEmu.addROM("Wario Land", md5: "aa", system: "openemu.system.gb", location: "Game Boy/Wario Land (World).gb")
        try openEmu.addFile("Game Boy/Wario Land (World).gb")
        try await migrateOpenEmu()

        let plan = try recovery().plan()

        #expect(plan.roms == [])
        #expect(plan.unmatched == ["Game Boy/Wario Land (World) 2.gb"])
    }

    // MARK: Checks, Backup and log

    func backups() throws -> [Backup] { try Backups(folder: folder.backups).all() }

    @Test func theDryRunSaysWhatWouldMoveAndChangesNothing() async throws {
        let tetris = try recorded("Game Boy/Tetris (World).gb", system: "openemu.system.gb", platform: 33)
        try openEmu.addFile("Game Boy/Tetris (World).7z")
        try recorded("Game Boy/Gone (World).gb", system: "openemu.system.gb", platform: 33)
        try await migrateOpenEmu()
        let before = try rom(tetris)

        let plan = try recovery().plan()

        #expect(plan.isRunnable)
        #expect(plan.roms.map(\.moves.first?.to) == [roms.appending(path: "Game Boy/Tetris (World).7z")])
        #expect(plan.unmatched == ["Game Boy/Gone (World).gb"])
        #expect(exists("roms/Game Boy/Tetris (World).7z", in: openEmu.folder))
        #expect(try rom(tetris) == before)
        #expect(try backups().map(\.operation) == [.beforeMigration])
    }

    @Test func itBacksUpAndLogsEachMoveBesideTheBackup() async throws {
        try recorded("Game Boy/Tetris (World).gb", system: "openemu.system.gb", platform: 33)
        try openEmu.addFile("Game Boy/Tetris (World).7z")
        try await migrateOpenEmu()

        let result = try await recovery().run()

        let backup = try #require(try backups().first)
        #expect(backup.operation == .beforeRecovery)
        #expect(result.backup.resolvingSymlinksInPath() == backup.url.resolvingSymlinksInPath())
        #expect(result.log.lastPathComponent == backup.url.deletingPathExtension().appendingPathExtension("moves.log").lastPathComponent)
        #expect(result.log.deletingLastPathComponent().resolvingSymlinksInPath() == folder.backups.resolvingSymlinksInPath())
        let from = openEmu.folder.appending(path: "roms/Game Boy/Tetris (World).7z").path(percentEncoded: false)
        let to = roms.appending(path: "Game Boy/Tetris (World).7z").path(percentEncoded: false)
        #expect(try String(contentsOf: result.log, encoding: .utf8) == "\(from)\t\(to)\n")
    }

    @Test func aNameAnotherROMHasStopsItBeforeAnythingIsTouched() async throws {
        let tetris = try recorded("Game Boy/Tetris (World) 2.gb", system: "openemu.system.gb", platform: 33)
        try openEmu.addFile("Game Boy/Tetris (World).gb")
        try recorded("Game Boy Color/Tetris (World).gbc", system: "openemu.system.gb", platform: 33)
        try openEmu.addFile("Game Boy Color/Tetris (World).gbc")
        try await migrateOpenEmu()
        let before = try rom(tetris)

        await #expect {
            try await recovery().run()
        } throws: { error in
            guard case .blocked(let plan) = error as? OpenEmuRecoveryError else { return false }
            return plan.clashes == ["Game Boy/Tetris (World): already a ROM there"]
        }
        #expect(exists("roms/Game Boy/Tetris (World).gb", in: openEmu.folder))
        #expect(try rom(tetris) == before)
        #expect(try backups().map(\.operation) == [.beforeMigration])
    }

    @Test func aJournalStillWaitingForMigrateOpenEmuIsRefused() async throws {
        let unmigrated = OpenEmuRecovery(
            journal: j.journal, library: openEmu.folder, beforeMigration: data.appending(path: "none.sqlite"), folder: folder,
            isOpenEmuRunning: { false })

        try recorded("Game Boy/Tetris (World).gb", system: "openemu.system.gb", platform: 33)

        #expect(throws: OpenEmuRecoveryError.notMigrated) { try unmigrated.plan() }
    }

    // MARK: A playlist whose discs already moved

    /// Fear Effect 2 as OpenEmu had it: a playlist recorded under `Sony PlayStation/` but moved to `Playstation (PSX)/`
    /// with its two discs, and each disc added again later as its own ROM, with copies of the playlist's disc files.
    /// `migrate-openemu` has moved the per-disc ROMs into PS1's ROM folder and left the playlist missing.
    /// Returns the playlist's and the per-disc ROMs' journal ids, and the Game.
    func fearEffect2(disc2Bin: String = "disc 2") async throws -> (playlist: Int64, discs: [Int64], game: GameID) {
        let psx = "openemu.system.psx"
        try j.journal.addPlatform(id: 7, name: "PlayStation")
        let game = try j.journal.addGame(platformId: 7, name: "Fear Effect 2")
        func disc(_ n: Int) -> String { "Fear Effect 2 (Disc \(n))" }
        func cue(_ n: Int) -> String { "FILE \"\(disc(n)).bin\" BINARY\n" }
        let playlist = try recorded("Sony PlayStation/Fear Effect 2/Fear Effect 2.m3u", system: psx, platform: 7, game: game)
        try openEmu.addFile("Playstation (PSX)/Fear Effect 2/Fear Effect 2.m3u", "\(disc(1)).cue\n\(disc(2)).cue\n")
        var discs: [Int64] = []
        for n in 1...2 {
            try openEmu.addFile("Playstation (PSX)/Fear Effect 2/\(disc(n)).cue", cue(n))
            try openEmu.addFile("Playstation (PSX)/Fear Effect 2/\(disc(n)).bin", "disc \(n)")
            try openEmu.addFile("Sony PlayStation/\(disc(n))/\(disc(n)).cue", cue(n))
            try openEmu.addFile("Sony PlayStation/\(disc(n))/\(disc(n)).bin", n == 2 ? disc2Bin : "disc 1")
            discs.append(try recorded("Sony PlayStation/\(disc(n))/\(disc(n)).cue", system: psx, platform: 7, game: game))
        }
        try await migrateOpenEmu()
        return (playlist, discs, game)
    }

    func romIds() throws -> [Int64] { try j.journal.db.read { try Int64.fetchAll($0, sql: "SELECT id FROM rom ORDER BY id") } }

    @Test func aPlaylistWhoseDiscsAlreadyMovedJoinsThemAndTheirOwnROMsAreForgotten() async throws {
        let fearEffect = try await fearEffect2()

        let result = try await recovery().run()

        #expect(result.plan.roms.flatMap { $0.moves.map(\.to.lastPathComponent) } == ["Fear Effect 2.m3u"])
        #expect(
            result.plan.forgottenDiscs.map { "\($0.name) of \($0.playlist)" } == [
                "Fear Effect 2 (Disc 1).cue of Fear Effect 2.m3u", "Fear Effect 2 (Disc 2).cue of Fear Effect 2.m3u",
            ])
        #expect(exists("PS1/Fear Effect 2.m3u", in: roms))
        #expect(try romIds() == [fearEffect.playlist])
        #expect(
            try rom(fearEffect.playlist)
                == Keyed(folderName: "Fear Effect 2", fileName: "Fear Effect 2.m3u", missing: true, lookedUp: false))
        #expect(try j.journal.roms(of: fearEffect.game).count == 1)
        // Its own copies of the discs are left in OpenEmu.
        #expect(exists("roms/Playstation (PSX)/Fear Effect 2/Fear Effect 2 (Disc 1).bin", in: openEmu.folder))
        #expect(exists("PS1/Fear Effect 2 (Disc 1).bin", in: roms))
    }

    @Test func aPlaylistWhoseDiscsAreInASubfolderOfTheROMFolderIsLeftMissingAndTheyArentMovedAgain() async throws {
        let fearEffect = try await fearEffect2()
        let subfolder = roms.appending(path: "PS1/Fear Effect 2 (Europe)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        for n in 1...2 {
            for ext in ["cue", "bin"] {
                try FileManager.default.moveItem(
                    at: roms.appending(path: "PS1/Fear Effect 2 (Disc \(n)).\(ext)"),
                    to: subfolder.appending(path: "Fear Effect 2 (Disc \(n)).\(ext)"))
            }
        }

        let plan = try recovery().plan()

        #expect(plan.roms == [])
        #expect(plan.forgottenDiscs == [])
        #expect(
            plan.playlistsLeftMissing == [
                "Sony PlayStation/Fear Effect 2/Fear Effect 2.m3u: its discs are in PS1/Fear Effect 2 (Europe) already"
            ])
        #expect(try romIds() == [fearEffect.playlist] + fearEffect.discs)
    }

    @Test func aPlaylistWhoseDiscsInTheROMFolderDifferIsLeftMissing() async throws {
        let fearEffect = try await fearEffect2(disc2Bin: "disc 2, dumped again")
        let before = try rom(fearEffect.playlist)

        let result = try await recovery().run()

        #expect(result.plan.roms == [])
        #expect(result.plan.forgottenDiscs == [])
        #expect(result.plan.playlistsLeftMissing == ["Sony PlayStation/Fear Effect 2/Fear Effect 2.m3u: its discs in PS1 differ"])
        #expect(try romIds() == [fearEffect.playlist] + fearEffect.discs)
        #expect(try rom(fearEffect.playlist) == before)
        #expect(!exists("PS1/Fear Effect 2.m3u", in: roms))
    }
}
