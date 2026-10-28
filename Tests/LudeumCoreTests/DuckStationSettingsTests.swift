import Foundation
import Testing

@testable import LudeumCore

/// DuckStation's settings as Ludeum writes them (ADR 0024): the Standing settings into its own `settings.ini` before
/// every launch, and a Game's own settings into its per-game file, named by its Serial (ADR 0021).
@Suite struct DuckStationSettingsTests {
    let folder = FileManager.default.temporaryDirectory.appending(
        path: "duckstation tests \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: folder.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    /// A fake DuckStation.app whose data root, `Contents/MacOS`, is `folder`.
    var settings: DuckStationSettings {
        DuckStationSettings(app: folder.appending(path: "DuckStation.app"), dataFolder: folder, ludeum: ludeum)
    }
    var settingsFile: URL { folder.appending(path: "settings.ini") }
    let rom = URL(filePath: "/Games/PSX/Resident Evil - Director's Cut (USA)/Resident Evil - Director's Cut (USA).cue")

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// The per-game file, in the Data folder once the Standing settings are written.
    func gameSettings(_ serial: String) -> URL { ludeum.duckStation(.gameSettings).appending(path: "\(serial).ini") }

    func write(_ text: String, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    func contents(_ file: URL) -> String? { try? String(contentsOf: file, encoding: .utf8) }

    func dataFolder(_ name: String) -> String {
        ludeum.data.appending(path: "Emulators/DuckStation/\(name)", directoryHint: .notDirectory).path(percentEncoded: false)
    }

    // MARK: Standing settings

    @Test func theStandingSettingsPutEveryFolderWorthKeepingInTheDataFolder() throws {
        try write(
            "[Main]\nRewindEnable = false\n\n[Folders]\nSaveStates = elsewhere\nCache = cache\n\n[Pad1]\nUp = Keyboard/Up\n",
            to: settingsFile)

        try settings.writeStanding()

        let ini = try #require(contents(settingsFile))
        #expect(Ini.value("SaveStates", in: "Folders", of: ini) == dataFolder("Save States"))
        #expect(Ini.value("Directory", in: "MemoryCards", of: ini) == dataFolder("Memory Cards"))
        #expect(Ini.value("SearchDirectory", in: "BIOS", of: ini) == dataFolder("BIOS"))
        #expect(Ini.value("GameSettings", in: "Folders", of: ini) == dataFolder("Game Settings"))
        #expect(Ini.value("InputProfiles", in: "Folders", of: ini) == dataFolder("Input Profiles"))
        #expect(Ini.value("Screenshots", in: "Folders", of: ini) == dataFolder("Screenshots"))
        // What's rebuildable stays DuckStation's own, as does everything else in the file.
        #expect(Ini.value("Cache", in: "Folders", of: ini) == "cache")
        #expect(ini.contains("[Main]\nRewindEnable = false\n\n"))
        #expect(ini.hasSuffix("SaveStates = \(dataFolder("Save States"))\nCache = cache\n\n[Pad1]\nUp = Keyboard/Up\n"))
        // The folders are there for DuckStation to write into.
        for name in ["Save States", "Memory Cards", "BIOS", "Game Settings", "Input Profiles", "Screenshots"] {
            #expect(FileManager.default.fileExists(atPath: dataFolder(name)))
        }
    }

    @Test func theStandingSettingsFastBootWithTheLowestLatencyAndKeepDuckStationFromUpdatingItself() throws {
        try write("[BIOS]\nPatchFastBoot = false\n\n[AutoUpdater]\nCheckAtStartup = true\nUpdateTag = latest\n", to: settingsFile)

        try settings.writeStanding()

        let ini = try #require(contents(settingsFile))
        #expect(Ini.value("PatchFastBoot", in: "BIOS", of: ini) == "true")
        #expect(Ini.value("FastForwardBoot", in: "BIOS", of: ini) == "true")
        #expect(Ini.value("OptimalFramePacing", in: "Display", of: ini) == "true")
        #expect(Ini.value("PreFrameSleep", in: "Display", of: ini) == "true")
        #expect(Ini.value("CheckAtStartup", in: "AutoUpdater", of: ini) == "false")
        #expect(Ini.value("UpdateTag", in: "AutoUpdater", of: ini) == "latest")
    }

    @Test func theStandingSettingsPutThePlayStationROMFolderInDuckStationsGameList() throws {
        // A lone Disc of a set swaps to the set's others from DuckStation's game list (ADR 0026).
        try write("[GameList]\nRecursivePaths = /Games/Mine\n", to: settingsFile)
        let ps1 = String(try #require(ludeum.romFolder(platform: ROMPlatform.ps1)).path(percentEncoded: false).dropLast())

        try settings.writeStanding()

        let ini = try #require(contents(settingsFile))
        #expect(ini.contains("[GameList]\nRecursivePaths = \(ps1)\nRecursivePaths = /Games/Mine\n"))
        // Once.
        try settings.writeStanding()
        #expect(contents(settingsFile) == ini)
    }

    @Test func writingTheStandingSettingsAgainChangesNothing() throws {
        try settings.writeStanding()
        let once = contents(settingsFile)
        let modified = try settingsFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        try settings.writeStanding()

        #expect(contents(settingsFile) == once)
        #expect(try settingsFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
    }

    @Test func nothingIsWrittenWhileTheDataFolderIsMissing() throws {
        try FileManager.default.removeItem(at: ludeum.data)

        #expect(throws: DataFolderMissing.self) { try settings.writeStanding() }
        #expect(throws: DataFolderMissing.self) {
            try settings.arguments(rom: rom, settings: EmulatorSettings(), serials: .read(["SLUS-00551"]))
        }
        #expect(contents(settingsFile) == nil)
        #expect(!FileManager.default.fileExists(atPath: ludeum.data.path(percentEncoded: false)))
    }

    // MARK: A Game's own settings

    @Test func aPlayWritesTheStandingSettingsAndMergesTheGamesOwnIntoItsPerGameFile() throws {
        try write("[Main]\nRewindEnable = false\n", to: settingsFile)
        try write("[Main]\nRunaheadFrameCount = 0\n\n[GPU]\nResolutionScale = 4\n", to: gameSettings("SLUS-00551"))

        let arguments = try Emulator.duckStation.arguments(
            rom: rom, platformId: 7, settings: EmulatorSettings(runAheadFrames: 2, cdReadSpeedup: 4, cdSeekSpeedup: 0),
            serials: .read(["SLUS-00551"]), duckStation: settings)

        #expect(arguments == ["--", rom.path(percentEncoded: false)])
        #expect(
            contents(gameSettings("SLUS-00551"))
                == "[CDROM]\nSeekSpeedup = 0\nReadSpeedup = 4\n\n[Main]\nRunaheadFrameCount = 2\n\n[GPU]\nResolutionScale = 4\n")
        #expect(Ini.value("SaveStates", in: "Folders", of: contents(settingsFile) ?? "") == dataFolder("Save States"))
    }

    @Test func aSettingTheGameHasntGotIsTakenOutSoDuckStationsOwnApplies() {
        let ini = """
            [Main]
            RunaheadFrameCount = 3
            RewindEnable = false

            [CDROM]
            ReadSpeedup = 4
            SeekSpeedup = 2

            [GPU]
            ResolutionScale = 4

            """
        #expect(
            DuckStationSettings.applying(EmulatorSettings(), to: ini, serial: "SLUS-00551")
                == "[Main]\nRewindEnable = false\n\n[GPU]\nResolutionScale = 4\n")
        #expect(
            DuckStationSettings.applying(EmulatorSettings(runAheadFrames: 0, cdSeekSpeedup: 1), to: ini, serial: "SLUS-00551")
                == "[Main]\nRunaheadFrameCount = 0\nRewindEnable = false\n\n[CDROM]\nSeekSpeedup = 1\n\n[GPU]\nResolutionScale = 4\n")
    }

    @Test func whatUsedToGoIntoEveryPerGameFileIsTakenOutAsItsStandingNow() {
        let ini = """
            [MemoryCards]
            Card1Path = /Data/Emulators/DuckStation/Memory Cards/SLUS-00551.mcd
            Card1Type = Shared
            Card2Type = None

            [Display]
            PreFrameSleep = true
            OptimalFramePacing = true

            [BIOS]
            FastForwardBoot = true
            PatchFastBoot = true

            [Main]
            RunaheadFrameCount = 1

            """
        #expect(
            DuckStationSettings.applying(EmulatorSettings(runAheadFrames: 1), to: ini, serial: "SLUS-00551")
                == "[MemoryCards]\nCard2Type = None\n\n[Main]\nRunaheadFrameCount = 1\n")
        #expect(DuckStationSettings.applying(EmulatorSettings(), to: ini, serial: "SLUS-00551") == "[MemoryCards]\nCard2Type = None\n\n")

        // What's been set since in DuckStation's Game Properties is DuckStation's, and stays: a card of my own, even one
        // in the Data folder's card folder, where every card is now.
        let mine = "[MemoryCards]\nCard1Type = Shared\nCard1Path = /Volumes/Cards/mine.mcd\n\n[BIOS]\nPatchFastBoot = false\n"
        #expect(DuckStationSettings.applying(EmulatorSettings(), to: mine, serial: "SLUS-00551") == mine)
        let chosen = "[MemoryCards]\nCard1Type = Shared\nCard1Path = /Data/Emulators/DuckStation/Memory Cards/Resident Evil_1.mcd\n"
        #expect(DuckStationSettings.applying(EmulatorSettings(), to: chosen, serial: "SLUS-00551") == chosen)
    }

    @Test func aDiscSetsOtherDiscsLoseDisc1sCardTooAtTheNextPlay() throws {
        try settings.writeStanding()
        let card = "[MemoryCards]\nCard1Path = /Data/Emulators/DuckStation/Memory Cards/SCUS-94163.mcd\nCard1Type = Shared\n\n"
        try write(card + "[Main]\nRunaheadFrameCount = 1\n", to: gameSettings("SCUS-94163"))
        try write(card, to: gameSettings("SCUS-94164"))
        try write(card + "[GPU]\nResolutionScale = 4\n", to: gameSettings("SCUS-94165"))

        try settings.write(EmulatorSettings(runAheadFrames: 1), serials: .read(["SCUS-94163", "SCUS-94164", "SCUS-94165"]))

        #expect(contents(gameSettings("SCUS-94163")) == "[Main]\nRunaheadFrameCount = 1\n")
        #expect(contents(gameSettings("SCUS-94164")) == "")
        #expect(contents(gameSettings("SCUS-94165")) == "[GPU]\nResolutionScale = 4\n")
    }

    @Test func aFileWithCRLFLineEndingsIsMergedLineByLine() {
        let ini = "[Main]\r\nRunaheadFrameCount = 3\r\nRewindEnable = false\r\n\r\n[CDROM]\r\nReadSpeedup = 4\r\n"
        #expect(
            DuckStationSettings.applying(EmulatorSettings(runAheadFrames: 1), to: ini, serial: "SLUS-00551")
                == "[Main]\r\nRunaheadFrameCount = 1\nRewindEnable = false\r\n\r\n")
        #expect(Ini.value("ReadSpeedup", in: "CDROM", of: ini) == "4")
    }

    @Test func aGameWithNoSettingsOfItsOwnGetsNoPerGameFile() throws {
        try settings.writeStanding()
        try settings.write(EmulatorSettings(), serials: .read(["SLUS-00551"]))
        #expect(contents(gameSettings("SLUS-00551")) == nil)

        // One it has is left as DuckStation's Game Properties made it, less what Ludeum used to put there.
        try write("[GPU]\nResolutionScale = 4\n\n[BIOS]\nPatchFastBoot = true\n", to: gameSettings("SCUS-94900"))
        try settings.write(EmulatorSettings(), serials: .read(["SCUS-94900"]))
        #expect(contents(gameSettings("SCUS-94900")) == "[GPU]\nResolutionScale = 4\n\n")
    }

    @Test func aMultiDiscVersionsSettingsAreDisc1sUnlessItKeepsEachDiscApart() throws {
        let serials = Serials.read(["SCUS-94163", "SCUS-94164", nil])
        try settings.writeStanding()
        try settings.write(EmulatorSettings(runAheadFrames: 1), serials: serials)
        #expect(contents(gameSettings("SCUS-94163")) == "[Main]\nRunaheadFrameCount = 1\n\n")
        #expect(contents(gameSettings("SCUS-94164")) == nil)

        try write("[Main]\nUseSeparateConfigForDiscSet = true\n", to: gameSettings("SCUS-94163"))
        try settings.write(EmulatorSettings(runAheadFrames: 1), serials: serials)
        #expect(contents(gameSettings("SCUS-94163")) == "[Main]\nRunaheadFrameCount = 1\nUseSeparateConfigForDiscSet = true\n")
        #expect(contents(gameSettings("SCUS-94164")) == "[Main]\nRunaheadFrameCount = 1\n\n")
    }

    @Test func withoutDisc1sSerialNoPerGameFileIsWritten() throws {
        try settings.writeStanding()
        try settings.write(EmulatorSettings(runAheadFrames: 1), serials: .notRead)
        try settings.write(EmulatorSettings(runAheadFrames: 1), serials: .read([nil, "SCUS-94164"]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: ludeum.duckStation(.gameSettings).path(percentEncoded: false)).isEmpty)
    }

    @Test func perGameFilesAreWhereDuckStationsSettingsPutThem() throws {
        try write("[Folders]\nGameSettings = per game\n", to: settingsFile)
        #expect(settings.gameSettingsFolder == folder.appending(path: "per game", directoryHint: .isDirectory))
        try write("[Folders]\nGameSettings = /Volumes/Games/settings\n", to: settingsFile)
        #expect(settings.gameSettingsFolder == URL(filePath: "/Volumes/Games/settings", directoryHint: .isDirectory))
        // Once the Standing settings are written, that's the Data folder.
        try settings.writeStanding()
        #expect(
            settings.gameSettingsFolder == ludeum.data.appending(path: "Emulators/DuckStation/Game Settings", directoryHint: .isDirectory))
    }

    @Test func aGamesCDSpeedupsAreKeptAndChecked() throws {
        let h = try LudeumHarness()
        let game = try h.addGame("Resident Evil")

        try h.journal.setEmulatorSettings(game, EmulatorSettings(cdReadSpeedup: 0, cdSeekSpeedup: 4))
        try h.reopen()
        #expect(try h.journal.emulatorSettings(game) == EmulatorSettings(cdReadSpeedup: 0, cdSeekSpeedup: 4))
        #expect(throws: LudeumError.cdReadSpeedupOutOfRange) {
            try h.journal.setEmulatorSettings(game, EmulatorSettings(cdReadSpeedup: 7))
        }
        #expect(throws: LudeumError.cdSeekSpeedupOutOfRange) {
            try h.journal.setEmulatorSettings(game, EmulatorSettings(cdSeekSpeedup: -1))
        }
        try h.journal.setEmulatorSettings(game, EmulatorSettings())
        #expect(try h.journal.emulatorSettings(game) == EmulatorSettings())
    }

    // MARK: The DuckStation Ludeum installs

    @Test func duckStationIsLudeumsOwnCopyInTheLudeumFolderMadePortable() throws {
        let standard = DuckStationSettings(ludeum: ludeum)
        #expect(standard.app == ludeum.url.appending(path: "Emulators/DuckStation.app", directoryHint: .isDirectory))
        #expect(standard.dataFolder == standard.app.appending(path: "Contents/MacOS", directoryHint: .isDirectory))
        #expect(!standard.isInstalled)

        let executable = standard.app.appending(path: "Contents/MacOS/DuckStation")
        try write("#!/bin/sh\n", to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
        #expect(standard.isInstalled)
        #expect(!standard.isPortable)
        try write("", to: standard.app.appending(path: "Contents/MacOS/portable.txt"))
        #expect(standard.isPortable)
    }
}
