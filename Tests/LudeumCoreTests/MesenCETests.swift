import CryptoKit
import Foundation
import Testing

@testable import LudeumCore

/// A MesenCE save state's header, as MesenCE 2.2.1 writes one: no picture to speak of, and the ROM's file name.
func mesenState(romName: String, console: UInt32 = 2) -> Data {
    func u32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    let picture = Data([1, 2, 3])
    var state = Data("MSS".utf8)
    // Version 2.2.1, format 4, the console, then the picture's size, width, height and scale, and the picture.
    for value: UInt32 in [0x0002_0201, 4, console, 512, 256, 240, 100, UInt32(picture.count)] { state += u32(value) }
    state += picture
    state += u32(UInt32(romName.utf8.count))
    state += Data(romName.utf8)
    return state + Data([9, 9, 9])
}

/// The MesenCE Ludeum keeps (ADR 0027): its Standing settings, Play's command line, and Play from a Save state.
@Suite struct MesenSettingsTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "mesence \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var settings: MesenSettings { MesenSettings(ludeum: ludeum) }

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    func json() throws -> [String: Any] {
        try #require(MesenSettings.object(try Data(contentsOf: settings.settingsFile)))
    }

    func preferences() throws -> [String: Any] { try #require(try json()["Preferences"] as? [String: Any]) }

    @Test func aPlayPointsMesenCEAtItsPlatformsFoldersInTheDataFolder() throws {
        let rom = URL(filePath: "/Games/NES/DuckTales (USA).7z")

        let arguments = try Emulator.mesenCE.arguments(
            rom: rom, platformId: 18, settings: EmulatorSettings(runAheadFrames: 2), mesen: settings)

        #expect(arguments == ["--emulation.runAheadFrames=2", "/Games/NES/DuckTales (USA).7z"])
        let written = try preferences()
        let nes = ludeum.data.appending(path: "Emulators/MesenCE/NES").path(percentEncoded: false)
        #expect(written["OverrideSaveStateFolder"] as? Bool == true)
        #expect(written["SaveStateFolder"] as? String == nes + "/Save States")
        #expect(written["OverrideSaveDataFolder"] as? Bool == true)
        #expect(written["SaveDataFolder"] as? String == nes + "/Saves")
        #expect(written["ScreenshotFolder"] as? String == nes + "/Screenshots")
        #expect(written["AutomaticallyCheckForUpdates"] as? Bool == false)
        #expect(written["GameSelectionScreenMode"] as? String == "Disabled")
        #expect(written["EnableAutoSaveState"] as? Bool == true)
        #expect(written["AutoSaveStateDelay"] as? Int == 1)
        for folder in MesenFolder.allCases {
            #expect(FileManager.default.fileExists(atPath: try #require(ludeum.mesen(folder, platform: 18)).path(percentEncoded: false)))
        }

        // Another Platform's Play points it at that Platform's, so a ROM of the same name on each keeps its own.
        _ = try Emulator.mesenCE.arguments(rom: rom, platformId: 33, settings: EmulatorSettings(), mesen: settings)
        #expect(
            try preferences()["SaveStateFolder"] as? String
                == ludeum.data.appending(path: "Emulators/MesenCE/Game Boy/Save States").path(percentEncoded: false))
    }

    @Test func runAheadAndTheGameBoyModelGoOnTheCommandLine() throws {
        let rom = URL(filePath: "/Games/GB/Tetris (World).gb")
        func play(_ platformId: Int64, _ model: GameBoyModel?) throws -> [String] {
            try Emulator.mesenCE.arguments(
                rom: rom, platformId: platformId, settings: EmulatorSettings(gameBoyModel: model), mesen: settings)
        }

        #expect(try play(33, nil) == ["--emulation.runAheadFrames=0", "--gameboy.model=AutoFavorGbc", "/Games/GB/Tetris (World).gb"])
        #expect(try play(33, .gameBoy).contains("--gameboy.model=Gameboy"))
        #expect(try play(22, .gameBoyColor).contains("--gameboy.model=GameboyColor"))
        #expect(try play(33, .superGameBoy).contains("--gameboy.model=SuperGameboy"))
        #expect(!(try play(18, .superGameBoy)).contains { $0.hasPrefix("--gameboy.model") })  // NES
    }

    @Test func everythingElseInItsSettingsStaysItsOwn() throws {
        try FileManager.default.createDirectory(at: settings.dataFolder, withIntermediateDirectories: true)
        // As MesenCE writes it: a byte order mark first.
        let mine = #"{ "Version": "2.2.1", "Video": { "Scale": 1.5 }, "Preferences": { "SingleInstance": true, "AutoSaveStateDelay": 5 } }"#
        try (Data([0xEF, 0xBB, 0xBF]) + Data(mine.utf8)).write(to: settings.settingsFile)

        try settings.writeStanding(platform: 19)

        let json = try json()
        #expect(json["Version"] as? String == "2.2.1")
        #expect((json["Video"] as? [String: Any])?["Scale"] as? Double == 1.5)
        #expect(try preferences()["SingleInstance"] as? Bool == true)
        #expect(try preferences()["AutoSaveStateDelay"] as? Int == 1)

        // Said already, so it's left alone.
        let written = try FileManager.default.attributesOfItem(atPath: settings.settingsFile.path(percentEncoded: false))[.modificationDate]
        try settings.writeStanding(platform: 19)
        #expect(
            try FileManager.default.attributesOfItem(atPath: settings.settingsFile.path(percentEncoded: false))[.modificationDate] as? Date
                == written as? Date)
    }

    @Test func withNoSettingsItStartsFromItsFirstRuns() throws {
        try settings.writeStanding()

        #expect(try json()["ConfigUpgrade"] as? Int == 1)
        #expect(try preferences()["SaveStateFolder"] == nil)
    }

    @Test func itsRefusedWithoutTheDataFolder() throws {
        let away = MesenSettings(ludeum: LudeumFolder(url: root.appending(path: "Nowhere", directoryHint: .isDirectory)))

        #expect(throws: DataFolderMissing.self) { try away.writeStanding(platform: 18) }
    }

    @Test func playFromASaveStateWritesTheResumeFileItLoads() throws {
        let state = root.appending(path: "DuckTales (USA)_3.mss")
        let contents = mesenState(romName: "DuckTales (USA).nes")
        try contents.write(to: state)
        let rom = URL(filePath: "/Games/NES/DuckTales (USA).7z")

        let arguments = try Emulator.mesenCE.arguments(
            rom: rom, platformId: 18, settings: EmulatorSettings(), saveState: state, mesen: settings)

        #expect(arguments == ["--emulation.runAheadFrames=0", "/Games/NES/DuckTales (USA).7z", "--loadLastSession"])
        let resume = settings.recentGames.appending(path: "DuckTales (USA).rgd")
        #expect(try unzipped("Savestate.mss", from: resume) == contents)
        #expect(
            try unzipped("RomInfo.txt", from: resume)
                == Data("DuckTales (USA).nes\n/Games/NES/DuckTales (USA).7z\u{1}DuckTales (USA).nes\n\n".utf8))

        // A loose ROM's path is its own.
        _ = try Emulator.mesenCE.arguments(
            rom: URL(filePath: "/Games/NES/DuckTales (USA).nes"), platformId: 18, settings: EmulatorSettings(), saveState: state,
            mesen: settings)
        #expect(try unzipped("RomInfo.txt", from: resume) == Data("DuckTales (USA).nes\n/Games/NES/DuckTales (USA).nes\n\n".utf8))
    }

    @Test func aFileThatIsntAStateCantBePlayedFrom() throws {
        let state = root.appending(path: "Not a state_1.mss")
        try Data("nope".utf8).write(to: state)

        #expect(throws: MesenResumeError.self) {
            try Emulator.mesenCE.arguments(
                rom: URL(filePath: "/Games/NES/Nope.nes"), platformId: 18, settings: EmulatorSettings(), saveState: state, mesen: settings)
        }
    }

    @Test func aStatesROMNameIsReadFromItsHeader() {
        #expect(MesenSaveStates.romName(inState: mesenState(romName: "Tetris (World).gb", console: 1)) == "Tetris (World).gb")
        #expect(MesenSaveStates.romName(inState: Data("MSS".utf8)) == nil)
        #expect(MesenSaveStates.romName(inState: Data()) == nil)
    }

    /// A file out of a zip, as `unzip` reads it.
    func unzipped(_ name: String, from zip: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/unzip")
        process.arguments = ["-p", zip.path(percentEncoded: false), name]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return data
    }
}

/// A Game's MesenCE Save states and Game saves, in its Platform's folders (ADR 0027).
@Suite struct MesenSaveStatesTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "mesence saves \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root, data: root.appending(path: "Data", directoryHint: .isDirectory)) }

    @discardableResult
    func put(_ name: String, in folder: MesenFolder, platform: Int64 = 18, date: Date = Date(timeIntervalSince1970: 1_000)) throws -> URL {
        let url = try #require(ludeum.mesen(folder, platform: platform)).appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(name.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path(percentEncoded: false))
        return url
    }

    @Test func aROMsStatesAreItsSlotsWithTheAutomaticOneAsResume() throws {
        try put("DuckTales (USA)_2.mss", in: .saveStates)
        try put("DuckTales (USA)_11.mss", in: .saveStates)
        try put("DuckTales (USA)_1.mss", in: .saveStates)
        try put("DuckTales 2 (USA)_1.mss", in: .saveStates)
        try put("DuckTales (USA)_1.png", in: .saveStates)
        try put("DuckTales (USA)_4.mss", in: .saveStates, platform: 33)

        let states = try #require(MesenSaveStates(ludeum: ludeum, platformId: 18)).states(of: "DuckTales (USA)")

        #expect(states.map(\.title) == ["Resume", "Slot 1", "Slot 2"])
        #expect(states.first?.saved == Date(timeIntervalSince1970: 1_000))
    }

    @Test func aROMsGameSavesAreTheFilesOfItsName() throws {
        try put("Pokemon - Crystal Version (USA).srm", in: .saves, platform: 22)
        try put("Pokemon - Crystal Version (USA).rtc", in: .saves, platform: 22)
        try put("Pokemon - Crystal Version (USA) (Rev 1).srm", in: .saves, platform: 22)

        let saves = try #require(MesenSaveStates(ludeum: ludeum, platformId: 22)).gameSaves(of: "Pokemon - Crystal Version (USA)")

        #expect(saves.map(\.fileName) == ["Pokemon - Crystal Version (USA).rtc", "Pokemon - Crystal Version (USA).srm"])
    }

    @Test func onlyMesenCEsPlatformsHaveFolders() {
        #expect(MesenSaveStates(ludeum: ludeum, platformId: 7) == nil)
        #expect(ludeum.mesen(.saves, platform: 86)?.path(percentEncoded: false).hasSuffix("Emulators/MesenCE/PC Engine/Saves/") == true)
        #expect(ludeum.mesen(.saves, platform: 99)?.path(percentEncoded: false).hasSuffix("Emulators/MesenCE/Famicom/Saves/") == true)
    }

    @Test func deletingOneSendsItToTheTrash() throws {
        let file = try put("DuckTales (USA)_1.mss", in: .saveStates)
        let saves = try #require(MesenSaveStates(ludeum: ludeum, platformId: 18))
        var trashed: [URL] = []

        try saves.delete(try #require(saves.states(of: "DuckTales (USA)").first)) { trashed.append($0) }

        #expect(trashed == [file])
    }

    @Test func aROMsNameIsItsFilesOrTheOneInsideItsArchive() async throws {
        #expect(
            await MesenROMName.of(URL(filePath: "/Games/NES/DuckTales (USA).nes"), platformId: 18)
                == MesenROMName(name: "DuckTales (USA)", inArchive: nil))
        guard let sevenZip = SevenZip.find() else { return }
        let archive = try archive("Duck Tales.7z", holding: ["readme.txt", "DuckTales (USA).nes"], sevenZip: sevenZip)

        #expect(await MesenROMName.of(archive, platformId: 18) == MesenROMName(name: "DuckTales (USA)", inArchive: "DuckTales (USA).nes"))
    }

    /// A `.7z` of files of these names, made with 7-Zip.
    func archive(_ name: String, holding files: [String], sevenZip: SevenZip) throws -> URL {
        let staging = root.appending(path: "staging \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        for file in files { try Data(file.utf8).write(to: staging.appending(path: file)) }
        let archive = root.appending(path: name)
        let process = Process()
        process.executableURL = sevenZip.executable
        process.arguments = ["a", archive.path(percentEncoded: false)] + files
        process.currentDirectoryURL = staging
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return archive
    }
}

/// Rename of a MesenCE ROM follows what MesenCE keys it by (ADR 0027).
@Suite struct MesenRenameTests {
    let h: LudeumHarness
    let game: GameID
    var ludeum: LudeumFolder { LudeumFolder(url: h.directory, data: h.directory.appending(path: "Data", directoryHint: .isDirectory)) }

    init() throws {
        h = try LudeumHarness()
        try h.journal.addPlatform(id: 18, name: "Nintendo Entertainment System")
        game = try h.journal.addGame(platformId: 18, name: "DuckTales")
    }

    func record(_ fileName: String, in folder: FakeROMFolder) throws -> LudeumROM {
        try h.journal.recordROM(game: game, fileName: fileName, missing: false)
        let rom = try #require(try h.journal.roms(of: game).first)
        try h.journal.checkROMAgain(rom.id, in: folder.folder)
        return try #require(try h.journal.rom(rom.id))
    }

    func put(_ name: String, in folder: MesenFolder) throws {
        let url = try #require(ludeum.mesen(folder, platform: 18)).appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(name.utf8).write(to: url)
    }

    func names(in folder: MesenFolder) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: try #require(ludeum.mesen(folder, platform: 18)).path(percentEncoded: false))
            .sorted()
    }

    @Test func aLooseROMsSavesFollowItsName() async throws {
        let nes = try FakeROMFolder(in: h.directory, platform: 18)
        try nes.add("Duck Tales (U).nes", "rom")
        let rom = try record("Duck Tales (U).nes", in: nes)
        try put("Duck Tales (U)_1.mss", in: .saveStates)
        try put("Duck Tales (U)_11.mss", in: .saveStates)
        try put("Duck Tales (U).sav", in: .saves)
        try put("Duck Tales (U)_002.png", in: .screenshots)
        try put("Duck Tales 2 (U)_1.mss", in: .saveStates)

        try await h.journal.renameMesenROM(rom.id, from: "Duck Tales (U)", to: "DuckTales (USA)", in: nes.folder, ludeum: ludeum)

        #expect(try h.journal.rom(rom.id)?.fileName == "DuckTales (USA).nes")
        #expect(try names(in: .saveStates) == ["Duck Tales 2 (U)_1.mss", "DuckTales (USA)_1.mss", "DuckTales (USA)_11.mss"])
        #expect(try names(in: .saves) == ["DuckTales (USA).sav"])
        #expect(try names(in: .screenshots) == ["DuckTales (USA)_002.png"])
    }

    @Test func itsRefusedWhenMesenCEKeepsAFileUnderTheNewName() async throws {
        let nes = try FakeROMFolder(in: h.directory, platform: 18)
        try nes.add("Duck Tales (U).nes", "rom")
        let rom = try record("Duck Tales (U).nes", in: nes)
        try put("Duck Tales (U)_1.mss", in: .saveStates)
        try put("DuckTales (USA).sav", in: .saves)

        await #expect(throws: MesenRenameError.savesInTheWay("DuckTales (USA).sav")) {
            try await h.journal.renameMesenROM(rom.id, from: "Duck Tales (U)", to: "DuckTales (USA)", in: nes.folder, ludeum: ludeum)
        }
        #expect(try h.journal.rom(rom.id)?.fileName == "Duck Tales (U).nes")
        #expect(try names(in: .saveStates) == ["Duck Tales (U)_1.mss"])
    }

    @Test func aCompactedROMsFileInsideIsRenamedToo() async throws {
        guard let sevenZip = SevenZip.find() else { return }
        let nes = try FakeROMFolder(in: h.directory, platform: 18)
        let staging = h.directory.appending(path: "staging", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("rom".utf8).write(to: staging.appending(path: "Duck Tales (U).nes"))
        let make = Process()
        make.executableURL = sevenZip.executable
        make.arguments = ["a", nes.url.appending(path: "Duck Tales (U).7z").path(percentEncoded: false), "Duck Tales (U).nes"]
        make.currentDirectoryURL = staging
        make.standardOutput = FileHandle.nullDevice
        try make.run()
        make.waitUntilExit()
        let rom = try record("Duck Tales (U).7z", in: nes)
        try put("Duck Tales (U)_1.mss", in: .saveStates)

        try await h.journal.renameMesenROM(rom.id, from: "Duck Tales (U)", to: "DuckTales (USA)", in: nes.folder, ludeum: ludeum)

        let archive = nes.url.appending(path: "DuckTales (USA).7z")
        #expect(try await sevenZip.list(archive).map(\.path) == ["DuckTales (USA).nes"])
        #expect(try names(in: .saveStates) == ["DuckTales (USA)_1.mss"])
    }

    @Test func aFileInsideOfAnotherNameKeepsItsSaves() async throws {
        guard let sevenZip = SevenZip.find() else { return }
        let nes = try FakeROMFolder(in: h.directory, platform: 18)
        let staging = h.directory.appending(path: "staging", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("rom".utf8).write(to: staging.appending(path: "ducktales.nes"))
        let make = Process()
        make.executableURL = sevenZip.executable
        make.arguments = ["a", nes.url.appending(path: "Duck Tales (U).7z").path(percentEncoded: false), "ducktales.nes"]
        make.currentDirectoryURL = staging
        make.standardOutput = FileHandle.nullDevice
        try make.run()
        make.waitUntilExit()
        let rom = try record("Duck Tales (U).7z", in: nes)
        try put("ducktales_1.mss", in: .saveStates)

        try await h.journal.renameMesenROM(rom.id, from: "Duck Tales (U)", to: "DuckTales (USA)", in: nes.folder, ludeum: ludeum)

        #expect(try await sevenZip.list(nes.url.appending(path: "DuckTales (USA).7z")).map(\.path) == ["ducktales.nes"])
        #expect(try names(in: .saveStates) == ["ducktales_1.mss"])
    }
}

/// Installing the MesenCE Ludeum keeps (ADR 0027).
@Suite struct MesenInstallTests {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "mesence install \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var installed: URL { ludeum.mesenApp }
    var dataRoot: URL { installed.appending(path: "Contents/MacOS", directoryHint: .isDirectory) }
    var existing: URL { root.appending(path: "Application Support/MesenCE/settings.json") }

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    /// A fake Mesen.app zipped as the release zips it, a zip inside a zip, and the release that names it.
    func release(needs: HomebrewLibrary? = nil) throws -> (zip: Data, release: MesenRelease) {
        let staging = root.appending(path: "staging \(UUID().uuidString)", directoryHint: .isDirectory)
        let app = staging.appending(path: "Mesen.app", directoryHint: .isDirectory)
        let macOS = app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let executable = macOS.appending(path: "Mesen")
        try "#!/bin/sh\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
        try Data().write(to: macOS.appending(path: "libSkiaSharp.dylib"))
        func zip(_ item: URL, keepParent: Bool, to file: URL) throws {
            let ditto = Process()
            ditto.executableURL = URL(filePath: "/usr/bin/ditto")
            ditto.arguments =
                ["-c", "-k"] + (keepParent ? ["--keepParent"] : []) + [item.path(percentEncoded: false), file.path(percentEncoded: false)]
            try ditto.run()
            ditto.waitUntilExit()
        }
        let outer = staging.appending(path: "outer", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outer, withIntermediateDirectories: true)
        try zip(app, keepParent: true, to: outer.appending(path: "Mesen.app.zip"))
        let file = staging.appending(path: "Mesen.zip")
        try zip(outer, keepParent: false, to: file)
        let data = try Data(contentsOf: file)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return (data, MesenRelease(version: "2.2.1", sha256: digest, needs: needs))
    }

    func installer(_ release: MesenRelease, zip: Data) -> MesenInstaller {
        MesenInstaller(ludeum: ludeum, release: release, transport: FakeReleases([release.url: zip]), existing: existing)
    }

    @Test func installingPutsAPortableMesenCEInTheLudeumFolderWithMySettings() async throws {
        let (zip, release) = try release()
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{ "Version": "2.2.1", "Input": { "Mine": true } }"#.write(to: existing, atomically: true, encoding: .utf8)

        try await installer(release, zip: zip).install()

        let settings = MesenSettings(ludeum: ludeum)
        #expect(settings.isInstalled)
        #expect(settings.isPortable)
        #expect(settings.installed == MesenRelease.Installed(version: "2.2.1", sha256: release.sha256))
        let json = try #require(MesenSettings.object(try Data(contentsOf: settings.settingsFile)))
        #expect((json["Input"] as? [String: Any])?["Mine"] as? Bool == true)
        #expect((json["Preferences"] as? [String: Any])?["AutomaticallyCheckForUpdates"] as? Bool == false)
        #expect(!exists(ludeum.emulators.appending(path: ".installing MesenCE")))
    }

    @Test func aReinstallCarriesAcrossWhatItKeptButItsNativeCode() async throws {
        let (zip, release) = try release()
        try await installer(release, zip: zip).install()
        try FileManager.default.createDirectory(at: dataRoot.appending(path: "Firmware"), withIntermediateDirectories: true)
        try Data("bios".utf8).write(to: dataRoot.appending(path: "Firmware/SGB2.sfc"))
        try Data("old core".utf8).write(to: dataRoot.appending(path: "MesenCore.dylib"))
        try #"{ "Kept": true }"#.write(to: dataRoot.appending(path: "settings.json"), atomically: true, encoding: .utf8)

        try await installer(release, zip: zip).install()

        #expect(try Data(contentsOf: dataRoot.appending(path: "Firmware/SGB2.sfc")) == Data("bios".utf8))
        #expect(!exists(dataRoot.appending(path: "MesenCore.dylib")))
        #expect(MesenSettings.object(try Data(contentsOf: dataRoot.appending(path: "settings.json")))?["Kept"] as? Bool == true)
        #expect(!exists(ludeum.emulators.appending(path: "MesenCE (replaced).app")))
    }

    @Test func aDownloadThatIsntTheReleaseIsRefused() async throws {
        let (zip, release) = try release()
        let wrong = MesenRelease(version: release.version, sha256: String(repeating: "0", count: 64), needs: nil)

        await #expect(throws: MesenInstallError.badChecksum(expected: wrong.sha256, found: release.sha256)) {
            try await installer(wrong, zip: zip).install()
        }
        #expect(!exists(installed))
    }

    @Test func itsRefusedWithoutALibraryTheReleaseNeeds() async throws {
        let missing = HomebrewLibrary(
            name: "SDL2", path: root.appending(path: "nowhere.dylib").path(percentEncoded: false), install: "brew install sdl2")
        let (zip, release) = try release(needs: missing)

        await #expect(throws: MesenInstallError.needs(missing)) { try await installer(release, zip: zip).install() }
        #expect(!exists(installed))
    }

    @Test func thePinnedReleaseIsTheAppleSiliconZip() {
        #expect(
            MesenRelease.pinned.url.absoluteString
                == "https://github.com/nesdev-org/MesenCE/releases/download/2.2.1/Mesen_2.2.1_macOS_ARM64_AppleSilicon.zip")
        #expect(MesenRelease.pinned.sha256.count == 64)
    }
}

/// Moving what MesenCE kept for itself over, once (ADR 0027).
@Suite struct MesenMigrationTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "mesence migration \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var old: URL { root.appending(path: "MesenCE", directoryHint: .isDirectory) }

    func put(_ path: String, in folder: URL, _ data: Data = Data("x".utf8)) throws {
        let url = folder.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    @Test func eachFileGoesToThePlatformOfTheOneROMOfItsName() async throws {
        guard let sevenZip = SevenZip.find() else { return }
        try put("NES/DuckTales (USA).nes", in: ludeum.roms)
        try put("Game Boy/DuckTales (USA).gb", in: ludeum.roms)
        try put("Game Boy/Tetris (World).gb", in: ludeum.roms)
        // A state says which console it's from, so the Game Boy's DuckTales.
        try put("SaveStates/DuckTales (USA)_1.mss", in: old, mesenState(romName: "DuckTales (USA).gb", console: 1))
        try put("Saves/Tetris (World).srm", in: old)
        try put("Saves/game.srm", in: old)
        try put("Screenshots/Tetris (World)_000.png", in: old)
        try put("Firmware/SGB2.sfc", in: old)
        let migration = MesenMigration(ludeum: ludeum, old: old, sevenZip: sevenZip)

        let plan = try await migration.plan()

        let gameBoy = ludeum.data.appending(path: "Emulators/MesenCE/Game Boy", directoryHint: .isDirectory)
        #expect(
            Set(plan.moves.map(\.to.path)) == [
                gameBoy.appending(path: "Save States/DuckTales (USA)_1.mss").path, gameBoy.appending(path: "Saves/Tetris (World).srm").path,
                gameBoy.appending(path: "Screenshots/Tetris (World)_000.png").path,
            ])
        #expect(plan.left.map(\.file) == ["game.srm"])
        #expect(plan.firmware.map(\.to.lastPathComponent) == ["SGB2.sfc"])

        _ = try await migration.run(plan)
        #expect(FileManager.default.fileExists(atPath: gameBoy.appending(path: "Saves/Tetris (World).srm").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: old.appending(path: "Saves/game.srm").path(percentEncoded: false)))
    }
}
