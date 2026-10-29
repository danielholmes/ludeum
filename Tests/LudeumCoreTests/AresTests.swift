import CryptoKit
import Foundation
import Testing

@testable import LudeumCore

/// The ares Ludeum keeps (ADR 0028): its Standing settings and Play's command line.
@Suite struct AresSettingsTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ares \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var settings: AresSettings { AresSettings(ludeum: ludeum) }
    var saves: String { ludeum.data.appending(path: "Emulators/ares/Saves/").path(percentEncoded: false) }
    var screenshots: String { ludeum.data.appending(path: "Emulators/ares/Screenshots/").path(percentEncoded: false) }

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    func written() throws -> String { try String(contentsOf: settings.settingsFile, encoding: .utf8) }

    @Test func aPlayPointsAresAtItsFoldersInTheDataFolder() throws {
        let rom = URL(filePath: "/Games/Mega Drive/Sonic the Hedgehog (USA, Europe).zip")

        let arguments = try Emulator.ares.arguments(rom: rom, platformId: 29, settings: EmulatorSettings(runAheadFrames: 2), ares: settings)

        #expect(
            arguments == [
                "--system", "Mega Drive", "--setting", "General/RunAhead=true", "/Games/Mega Drive/Sonic the Hedgehog (USA, Europe).zip",
            ])
        #expect(try written() == "Paths\n  Saves: \(saves)\n  Screenshots: \(screenshots)\nGeneral\n  AutoSaveMemory: true\n")
        #expect(FileManager.default.fileExists(atPath: saves))
        #expect(FileManager.default.fileExists(atPath: screenshots))
    }

    @Test func runAheadIsOnOrOffForThisLaunchOnly() throws {
        let rom = URL(filePath: "/Games/Mega Drive/Sonic the Hedgehog (USA, Europe).md")
        func runAhead(_ frames: Int?) throws -> [String] {
            try Emulator.ares.arguments(rom: rom, platformId: 29, settings: EmulatorSettings(runAheadFrames: frames), ares: settings)
        }

        #expect(try runAhead(nil).contains("General/RunAhead=false"))
        #expect(try runAhead(0).contains("General/RunAhead=false"))
        #expect(try runAhead(1).contains("General/RunAhead=true"))
    }

    @Test func eachPlatformPlaysAsItsSystem() throws {
        func system(_ platformId: Int64) throws -> [String] {
            Array(
                try Emulator.ares.arguments(rom: URL(filePath: "/Games/x"), platformId: platformId, settings: .init(), ares: settings)
                    .prefix(2))
        }

        #expect(try system(4) == ["--system", "Nintendo 64"])
        #expect(try system(29) == ["--system", "Mega Drive"])
        #expect(try system(78) == ["--system", "Mega CD"])
    }

    @Test func playFromASaveStateLoadsItsSlot() throws {
        let rom = URL(filePath: "/Games/N64/Super Mario 64 (USA).zip")
        let state = URL(filePath: "/Data/Emulators/ares/Saves/Nintendo 64/Super Mario 64 (USA).bs3")

        let arguments = try Emulator.ares.arguments(rom: rom, platformId: 4, settings: .init(), saveState: state, ares: settings)

        #expect(arguments.suffix(3) == ["--save-state", "3", "/Games/N64/Super Mario 64 (USA).zip"])
    }

    @Test func everythingElseInItsSettingsStaysItsOwn() throws {
        try FileManager.default.createDirectory(at: settings.settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let mine = """
            Video
              Driver: Metal
            General
              ShowStatusBar: true
              RunAhead: false
              AutoSaveMemory: false
            Paths
              Home
              Firmware
              Saves
              Screenshots: /Users/me/Pictures/
              Debugging
              SuperFamicom
                GameBoy
                Saves: /not/this/one/
            MegaDrive
              Path: /Users/me/ROMs/Mega Drive/

            """
        try mine.write(to: settings.settingsFile, atomically: true, encoding: .utf8)

        try settings.writeStanding()

        #expect(
            try written() == """
                Video
                  Driver: Metal
                General
                  ShowStatusBar: true
                  RunAhead: false
                  AutoSaveMemory: true
                Paths
                  Home
                  Firmware
                  Saves: \(saves)
                  Screenshots: \(screenshots)
                  Debugging
                  SuperFamicom
                    GameBoy
                    Saves: /not/this/one/
                MegaDrive
                  Path: /Users/me/ROMs/Mega Drive/

                """)

        // Said already, so it's left alone.
        let path = settings.settingsFile.path(percentEncoded: false)
        let before = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
        try settings.writeStanding()
        #expect(try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date == before)
    }

    @Test func aKeyMissingFromItsSectionGoesAtTheSectionsEnd() {
        let bml = "General\n  ShowStatusBar: true\nPaths\n  Home\nAudio\n  Mute: false\n"

        #expect(
            BML.setting("Paths/Saves", to: "/S/", in: bml)
                == "General\n  ShowStatusBar: true\nPaths\n  Home\n  Saves: /S/\nAudio\n  Mute: false\n")
        #expect(BML.setting("Input/Driver", to: "SDL", in: bml) == bml + "Input\n  Driver: SDL\n")
    }

    @Test func settingsThatCantBeReadAreRefusedNotWrittenOver() throws {
        try FileManager.default.createDirectory(at: settings.settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let unreadable = Data([0x49, 0x6E, 0xFF, 0xFE, 0x0A])
        try unreadable.write(to: settings.settingsFile)

        #expect(throws: (any Error).self) { try settings.writeStanding() }
        #expect(try Data(contentsOf: settings.settingsFile) == unreadable)
    }

    @Test func itsRefusedWithoutTheDataFolder() throws {
        let away = AresSettings(ludeum: LudeumFolder(url: root.appending(path: "Nowhere", directoryHint: .isDirectory)))

        #expect(throws: DataFolderMissing.self) { try away.writeStanding() }
    }
}

/// A Game's ares Save states and Game saves, in its system's folder (ADR 0028).
@Suite struct AresSavesTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ares saves \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root, data: root.appending(path: "Data", directoryHint: .isDirectory)) }

    @discardableResult
    func put(_ path: String, in folder: URL? = nil, date: Date = Date(timeIntervalSince1970: 1_000)) throws -> URL {
        let url = (folder ?? ludeum.aresSaves).appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(path.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path(percentEncoded: false))
        return url
    }

    @Test func aROMsStatesAreItsNineSlots() throws {
        try put("Nintendo 64/Super Mario 64 (USA).bs2")
        try put("Nintendo 64/Super Mario 64 (USA).bs1")
        try put("Nintendo 64/Super Mario 64 (USA).bsu")
        try put("Nintendo 64/Super Mario 64 (USA).blu")
        try put("Nintendo 64/Super Mario 64 (USA) (Rev 1).bs1")
        try put("Nintendo 64/Super Mario 64 (USA).eeprom")
        try put("Mega Drive/Super Mario 64 (USA).bs4")

        let states = try #require(AresSaves(ludeum: ludeum, platformId: 4)).states(of: "Super Mario 64 (USA)")

        #expect(states.map(\.title) == ["Slot 1", "Slot 2"])
        #expect(states.first?.saved == Date(timeIntervalSince1970: 1_000))
    }

    @Test func aROMsGameSavesAreItsMemoryAndControllerPaks() throws {
        try put("Nintendo 64/Mario Kart 64 (USA).eeprom")
        try put("Nintendo 64/Mario Kart 64 (USA).pak")
        try put("Nintendo 64/Mario Kart 64 (USA).2.pak")
        try put("Nintendo 64/Mario Kart 64 (USA).bs1")
        try put("Nintendo 64/Mario Kart 64 (USA) (Rev A).eeprom")
        try put("Mega Drive/The Curse of Illmoore Bay.ram")

        let n64 = try #require(AresSaves(ludeum: ludeum, platformId: 4))
        let megaDrive = try #require(AresSaves(ludeum: ludeum, platformId: 29))

        #expect(
            n64.gameSaves(of: "Mario Kart 64 (USA)").map(\.fileName) == [
                "Mario Kart 64 (USA).2.pak", "Mario Kart 64 (USA).eeprom", "Mario Kart 64 (USA).pak",
            ])
        #expect(megaDrive.gameSaves(of: "The Curse of Illmoore Bay").map(\.fileName) == ["The Curse of Illmoore Bay.ram"])
    }

    @Test func aSegaCDGamesStatesAreTheMegaDrives() throws {
        try put("Mega Drive/Sonic CD (USA).bs1")

        #expect(try #require(AresSaves(ludeum: ludeum, platformId: 78)).states(of: "Sonic CD (USA)").map(\.title) == ["Slot 1"])
        #expect(AresSaves(ludeum: ludeum, platformId: 7) == nil)
    }

    @Test func deletingOneSendsItToTheTrash() throws {
        let file = try put("Mega Drive/Sonic 2 (World).bs1")
        let saves = try #require(AresSaves(ludeum: ludeum, platformId: 29))
        var trashed: [URL] = []

        try saves.delete(try #require(saves.states(of: "Sonic 2 (World)").first)) { trashed.append($0) }

        #expect(trashed == [file])
    }
}

/// Rename of an ares ROM moves what ares keeps by its name (ADR 0028).
@Suite struct AresRenameTests {
    let h: LudeumHarness
    let game: GameID
    var ludeum: LudeumFolder { LudeumFolder(url: h.directory, data: h.directory.appending(path: "Data", directoryHint: .isDirectory)) }

    init() throws {
        h = try LudeumHarness()
        try h.journal.addPlatform(id: 29, name: "Sega Mega Drive/Genesis")
        game = try h.journal.addGame(platformId: 29, name: "Sonic the Hedgehog")
    }

    func record(_ fileName: String, in folder: FakeROMFolder, game: GameID? = nil) throws -> LudeumROM {
        let game = game ?? self.game
        try h.journal.recordROM(game: game, fileName: fileName, missing: false)
        let rom = try #require(try h.journal.roms(of: game).first)
        try h.journal.checkROMAgain(rom.id, in: folder.folder)
        return try #require(try h.journal.rom(rom.id))
    }

    func put(_ path: String, in folder: URL? = nil) throws {
        let url = (folder ?? ludeum.aresSaves).appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(path.utf8).write(to: url)
    }

    func names(_ system: String, in folder: URL? = nil) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            atPath: (folder ?? ludeum.aresSaves).appending(path: system).path(percentEncoded: false)
        )
        .sorted()
    }

    @Test func aROMsSavesFollowItsName() throws {
        let megaDrive = try FakeROMFolder(in: h.directory, platform: 29)
        try megaDrive.add("Sonic (U).zip", "rom")
        let rom = try record("Sonic (U).zip", in: megaDrive)
        try put("Mega Drive/Sonic (U).bs1")
        try put("Mega Drive/Sonic (U).ram")
        try put("Mega Drive/Sonic (U) [h1].bs1")
        try put("Mega Drive/Sonic (U) 2026-10-29 11-32-05.png", in: ludeum.aresScreenshots)

        try h.journal.renameAresROM(rom.id, from: "Sonic (U)", to: "Sonic the Hedgehog (USA, Europe)", in: megaDrive.folder, ludeum: ludeum)

        #expect(try h.journal.rom(rom.id)?.fileName == "Sonic the Hedgehog (USA, Europe).zip")
        #expect(
            try names("Mega Drive") == [
                "Sonic (U) [h1].bs1", "Sonic the Hedgehog (USA, Europe).bs1", "Sonic the Hedgehog (USA, Europe).ram",
            ])
        #expect(try names("Mega Drive", in: ludeum.aresScreenshots) == ["Sonic the Hedgehog (USA, Europe) 2026-10-29 11-32-05.png"])
    }

    @Test func anArchivedROMsSavesFollowItsNameForWhenItsUnarchived() throws {
        let megaDrive = try FakeROMFolder(in: h.directory, platform: 29)
        try megaDrive.add("Sonic (U).7z", "archive")
        let rom = try record("Sonic (U).7z", in: megaDrive)
        try put("Mega Drive/Sonic (U).ram")

        try h.journal.renameAresROM(rom.id, from: "Sonic (U)", to: "Sonic the Hedgehog (USA, Europe)", in: megaDrive.folder, ludeum: ludeum)

        #expect(try h.journal.rom(rom.id)?.fileName == "Sonic the Hedgehog (USA, Europe).7z")
        #expect(try names("Mega Drive") == ["Sonic the Hedgehog (USA, Europe).ram"])
    }

    @Test func itsRefusedWhenAresKeepsAFileUnderTheNewName() throws {
        let megaDrive = try FakeROMFolder(in: h.directory, platform: 29)
        try megaDrive.add("Sonic (U).zip", "rom")
        let rom = try record("Sonic (U).zip", in: megaDrive)
        try put("Mega Drive/Sonic (U).bs1")
        try put("Mega Drive/Sonic the Hedgehog (USA, Europe).ram")

        #expect(throws: AresRenameError.savesInTheWay("Sonic the Hedgehog (USA, Europe).ram")) {
            try h.journal.renameAresROM(
                rom.id, from: "Sonic (U)", to: "Sonic the Hedgehog (USA, Europe)", in: megaDrive.folder, ludeum: ludeum)
        }
        #expect(try h.journal.rom(rom.id)?.fileName == "Sonic (U).zip")
        #expect(try names("Mega Drive") == ["Sonic (U).bs1", "Sonic the Hedgehog (USA, Europe).ram"])
    }

    @Test func aDiscROMsCueSheetKeepsItsNameAndSoDoItsStates() throws {
        try h.journal.addPlatform(id: 78, name: "Sega CD")
        let cd = try h.journal.addGame(platformId: 78, name: "Sonic CD")
        let segaCD = try FakeROMFolder(in: h.directory, platform: 78)
        try segaCD.add("Sonic CD (U)/Sonic CD (U).cue", "cue")
        let rom = try record("Sonic CD (U).cue", in: segaCD, game: cd)
        try put("Mega Drive/Sonic CD (U).bs1")

        try h.journal.renameAresROM(rom.id, from: "Sonic CD (U)", to: "Sonic CD (USA)", in: segaCD.folder, ludeum: ludeum)

        #expect(try h.journal.rom(rom.id)?.folderName == "Sonic CD (USA)")
        #expect(try names("Mega Drive") == ["Sonic CD (U).bs1"])
    }
}

/// Installing the ares Ludeum keeps (ADR 0028).
@Suite struct AresInstallTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ares install \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var settings: AresSettings { AresSettings(ludeum: ludeum) }
    var existing: URL { root.appending(path: "Application Support/ares/settings.bml") }

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    /// Where the fake ares notes it was run: ares writes its settings whenever it starts, so Install mustn't run it.
    var ran: URL { root.appending(path: "ares ran") }

    /// A fake ares.app in an `ares-v<version>` folder, zipped as the release zips it, and the release that names it. Its
    /// app says it's `appVersion`.
    func release(appVersion: String = "v148", version: String = "148") throws -> (zip: Data, release: AresRelease) {
        let staging = root.appending(path: "staging \(UUID().uuidString)", directoryHint: .isDirectory)
        let top = staging.appending(path: "ares-v\(version)", directoryHint: .isDirectory)
        let app = top.appending(path: "ares.app", directoryHint: .isDirectory)
        let macOS = app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleShortVersionString": appVersion, "CFBundleExecutable": "ares"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(
            to: app.appending(path: "Contents/Info.plist"))
        let executable = macOS.appending(path: "ares")
        try "#!/bin/sh\ntouch '\(ran.path(percentEncoded: false))'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
        let zipFile = staging.appending(path: "ares-macos-universal.zip")
        let ditto = Process()
        ditto.executableURL = URL(filePath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", top.path(percentEncoded: false), zipFile.path(percentEncoded: false)]
        try ditto.run()
        ditto.waitUntilExit()
        let zip = try Data(contentsOf: zipFile)
        let digest = SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
        return (zip, AresRelease(version: version, sha256: digest))
    }

    func installer(_ release: AresRelease, zip: Data) -> AresInstaller {
        AresInstaller(ludeum: ludeum, release: release, transport: FakeReleases([release.url: zip]), existing: existing)
    }

    @Test func installingPutsAPortableAresInTheLudeumFolderWithMySettings() async throws {
        let (zip, release) = try release()
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Input\n  Driver: SDL\n".write(to: existing, atomically: true, encoding: .utf8)

        try await installer(release, zip: zip).install()

        #expect(settings.isInstalled)
        #expect(settings.isPortable)
        #expect(settings.app == ludeum.emulators.appending(path: "ares/ares.app", directoryHint: .isDirectory))
        let written = try String(contentsOf: settings.settingsFile, encoding: .utf8)
        #expect(written.hasPrefix("Input\n  Driver: SDL\nPaths\n  Saves: "))
        #expect(written.contains("AutoSaveMemory: true"))
        #expect(!exists(ludeum.emulators.appending(path: ".installing ares")))
        #expect(!exists(ran))
    }

    @Test func aReinstallKeepsItsOwnSettings() async throws {
        let (zip, release) = try release()
        try await installer(release, zip: zip).install()
        try "Video\n  Driver: Metal\n".write(to: settings.settingsFile, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Input\n  Driver: SDL\n".write(to: existing, atomically: true, encoding: .utf8)

        try await installer(release, zip: zip).install()

        #expect(try String(contentsOf: settings.settingsFile, encoding: .utf8).hasPrefix("Video\n  Driver: Metal\nPaths\n"))
        #expect(!exists(ludeum.aresFolder.appending(path: "ares (replaced).app")))
    }

    @Test func aDownloadThatIsntTheReleaseIsRefused() async throws {
        let (zip, release) = try release()
        let wrong = AresRelease(version: release.version, sha256: String(repeating: "0", count: 64))

        await #expect(throws: AresInstallError.badChecksum(expected: wrong.sha256, found: release.sha256)) {
            try await installer(wrong, zip: zip).install()
        }
        #expect(!exists(settings.app))
    }

    @Test func aBuildThatSaysItsAnotherVersionIsRefused() async throws {
        let (zip, release) = try release(appVersion: "v147")

        await #expect(throws: AresInstallError.wrongBuild(found: "147")) { try await installer(release, zip: zip).install() }
        #expect(!exists(settings.app))
    }

    @Test func thePinnedReleaseIsTheUniversalZip() {
        #expect(
            AresRelease.pinned.url.absoluteString == "https://github.com/ares-emulator/ares/releases/download/v148/ares-macos-universal.zip"
        )
        #expect(AresRelease.pinned.sha256.count == 64)
        #expect(Emulator.ares.expectedVersion == "148")
    }
}

/// Play in the ares Ludeum installs (ADR 0028).
@Suite struct AresPlayTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "ares play \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: directory.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var ares: AresSettings { AresSettings(ludeum: ludeum) }

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
        let executable = ludeum.aresApp.appending(path: "Contents/MacOS/ares")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
    }

    func press(running: Bool = false, saveState: URL? = nil) throws -> (Play.Outcome, URL) {
        let megaDrive = try FakeROMFolder(in: directory, platform: 29)
        let zip = try megaDrive.add("Sonic 2 (World).zip")
        let rom = LudeumROM(
            id: 1, folderName: "Sonic 2 (World)", platformId: 29, fileName: "Sonic 2 (World).zip", name: "Sonic 2 (World)", version: "",
            disc: nil, missing: false, archived: false)
        let outcome = Play(platformId: 29, platformName: "Sega Mega Drive/Genesis", roms: [rom], settings: .init())
            .prepare(
                locator: ROMLocator(romFolders: [megaDrive.folder]), version: .ok, app: { _ in URL(filePath: "/Applications/ares.app") },
                saveState: saveState, ares: ares, running: { _ in running })
        return (outcome, zip)
    }

    @Test func itOpensLudeumsCopyAndNotAnotherOne() throws {
        let (outcome, zip) = try press()

        #expect(
            outcome
                == .open(
                    app: ludeum.aresApp,
                    arguments: ["--system", "Mega Drive", "--setting", "General/RunAhead=false", zip.path(percentEncoded: false)],
                    warning: nil))
        #expect(ares.isPortable)
    }

    @Test func aSaveStateStartsThePlayFromItsSlot() throws {
        let (outcome, _) = try press(saveState: ludeum.aresSaves.appending(path: "Mega Drive/Sonic 2 (World).bs7"))

        #expect(outcome.arguments?.contains("--save-state") == true)
        #expect(outcome.arguments?.dropLast().last == "7")
    }

    @Test func withoutTheAresLudeumInstallsPlayIsRefused() throws {
        try FileManager.default.removeItem(at: ludeum.aresApp)

        let (outcome, _) = try press()

        #expect(outcome == .refused(.notInstalled(.ares)))
        #expect(outcome.refusal?.message == "ares isn't installed. Install it from Ludeum ▸ Emulators…")
    }

    @Test func playIsRefusedWhileAnyAresIsOpenAsItWouldWriteOverItsSettings() throws {
        let (outcome, _) = try press(running: true)

        #expect(outcome == .refused(.running(.ares)))
        #expect(outcome.refusal?.message.hasPrefix("ares is open. Quit it, then Play") == true)
        #expect(!ares.isPortable)
    }
}
