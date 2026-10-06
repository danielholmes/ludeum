import Foundation
import Testing

@testable import LudeumCore

@Suite struct PlayAvailabilityTests {
    @Test func aPlatformWithNoEmulatorSaysSo() {
        let play = Play(platformId: 11, platformName: "Xbox", roms: [folderROM("Halo")], settings: EmulatorSettings())

        #expect(play.availability == .refused(.noEmulator("Xbox")))
        #expect(play.availability.refusal?.message == "No Xbox emulator yet")
    }

    @Test func aGameWhosePresentROMsAreAllArchivedHasToBeUnarchivedFirst() {
        let play = Play(
            platformId: 8, platformName: "PlayStation 2",
            roms: [folderROM("Okami (USA)", archived: true), folderROM("Okami (Japan)", missing: true, id: 2)], settings: EmulatorSettings()
        )

        #expect(play.availability == .refused(.archived))
        #expect(play.availability.refusal?.message == "Archived: unarchive to play")
    }

    @Test func aGameWaitsWhileABackgroundTaskWorksOnOneOfItsROMs() {
        let play = Play(
            platformId: 8, platformName: "PlayStation 2", roms: [folderROM("Okami (USA)", id: 4)], settings: EmulatorSettings(),
            busyROMs: [4])

        #expect(play.availability == .refused(.busy))
        #expect(play.availability.refusal?.message == "Waiting for Archive or Unarchive to finish")
    }

    @Test func otherwiseItPlaysInThePlatformsEmulator() {
        let play = Play(platformId: 8, platformName: "PlayStation 2", roms: [folderROM("Okami (USA)")], settings: EmulatorSettings())

        #expect(play.availability == .ready(.pcsx2))
    }
}

/// Plays in MesenCE (NES), whose settings are all on the command line, so nothing is written outside the test.
@Suite struct PlayPressTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "play \(UUID().uuidString)")
    let mesen = URL(filePath: "/Applications/Mesen.app")

    func press(
        _ roms: [LudeumROM], in folder: FakeROMFolder, version: Play.VersionStatus = .ok, settings: EmulatorSettings = EmulatorSettings(),
        installed: Bool = true
    ) -> Play.Outcome {
        let mesen = mesen
        return Play(platformId: 18, platformName: "NES", roms: roms, settings: settings)
            .prepare(
                locator: ROMLocator(openEmuLibrary: directory, romFolders: [folder.folder]), version: version,
                app: { installed && $0 == Emulator.mesenCE.bundleIdentifier ? mesen : nil })
    }

    @Test func itOpensTheROMInTheEmulatorWithEverySetting() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let rom = try ps2.add("Zelda.iso")

        #expect(
            press([folderROM("Zelda")], in: ps2, settings: EmulatorSettings(runAheadFrames: 2))
                == .open(
                    app: mesen,
                    arguments: ["--doNotSaveSettings", "--emulation.runAheadFrames=2", rom.path(percentEncoded: false)], warning: nil))
    }
    @Test func aMultiDiscVersionOpensItsPlaylist() throws {
        let openEmu = try FakeOpenEmu(in: directory)
        let disc = try openEmu.addROM("Disc 1", md5: "a", fileName: "Disc 1.nes")
        let playlist = try openEmu.addROM("Game", md5: "b", fileName: "Game.m3u")
        func rom(_ pk: Int64, _ fileName: String) -> LudeumROM {
            LudeumROM(
                id: pk, openEmuPk: pk, folderName: nil, platformId: 18, fileName: fileName, name: fileName,
                version: "", disc: nil, missing: false, archived: false)
        }

        let outcome = Play(
            platformId: 18, platformName: "NES", roms: [rom(disc, "Disc 1.nes"), rom(playlist, "Game.m3u")], settings: .init()
        )
        .prepare(locator: ROMLocator(openEmuLibrary: openEmu.folder, romFolders: []), version: .ok, app: { _ in mesen })

        #expect(outcome.arguments?.last?.hasSuffix("\(playlist)-Game.m3u") == true)
    }

    @Test func aWarningGoesAlongWithThePlay() throws {
        let ps2 = try FakeROMFolder(in: directory)
        try ps2.add("Zelda.iso")

        #expect(press([folderROM("Zelda")], in: ps2, version: .warn("Newer major version")).warning == "Newer major version")
    }

    @Test func anEmulatorTooOldIsRefused() throws {
        let ps2 = try FakeROMFolder(in: directory)
        try ps2.add("Zelda.iso")

        #expect(press([folderROM("Zelda")], in: ps2, version: .tooOld("MesenCE 1 is too old")) == .refused(.tooOld("MesenCE 1 is too old")))
    }

    @Test func anEmulatorNotInstalledIsRefused() throws {
        let ps2 = try FakeROMFolder(in: directory)
        try ps2.add("Zelda.iso")

        let outcome = press([folderROM("Zelda")], in: ps2, installed: false)

        #expect(outcome == .refused(.notInstalled(.mesenCE)))
        #expect(outcome.refusal?.message == "MesenCE isn't installed.")
    }

    @Test func aROMWhoseFileIsGoneIsRefused() throws {
        let ps2 = try FakeROMFolder(in: directory)

        let outcome = press([folderROM("Zelda")], in: ps2)

        #expect(outcome.refusal?.message == "Couldn't find Zelda.iso. Run an Import, then try again.")
    }

    @Test func aRefusalBeforeThePressIsARefusalOnIt() throws {
        let ps2 = try FakeROMFolder(in: directory)
        try ps2.add("Zelda.7z")

        #expect(press([folderROM("Zelda", fileName: "Zelda.7z", archived: true)], in: ps2) == .refused(.archived))
    }
}
