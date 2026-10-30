import Foundation
import Testing

@testable import LudeumCore

/// DuckStation's settings as Ludeum writes them (ADR 0024): the Standing settings into its own `settings.ini` before
/// every launch, and nothing into its per-game files, which are DuckStation's (ADR 0029).
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
            try settings.arguments(rom: rom)
        }
        #expect(contents(settingsFile) == nil)
        #expect(!FileManager.default.fileExists(atPath: ludeum.data.path(percentEncoded: false)))
    }

    // MARK: Its per-game files

    @Test func aPlayWritesTheStandingSettingsAndLeavesThePerGameFileAsDuckStationMadeIt() throws {
        try write("[Main]\nRewindEnable = false\n", to: settingsFile)
        let perGame = "[Main]\nRunaheadFrameCount = 6\n\n[CDROM]\nReadSpeedup = 0\nSeekSpeedup = 0\n"
        try write(perGame, to: gameSettings("SLUS-00551"))

        let arguments = try Emulator.duckStation.arguments(rom: rom, platformId: 7, settings: EmulatorSettings(), duckStation: settings)

        #expect(arguments == ["--", rom.path(percentEncoded: false)])
        #expect(contents(gameSettings("SLUS-00551")) == perGame)
        #expect(Ini.value("SaveStates", in: "Folders", of: contents(settingsFile) ?? "") == dataFolder("Save States"))
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
