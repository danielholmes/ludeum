import Foundation
import Testing

@testable import LudeumCore

@Suite struct PlayAvailabilityTests {
    @Test func aPlatformWithNoEmulatorSaysSo() {
        let play = Play(
            platformId: ROMPlatform.vita, platformName: "PlayStation Vita", roms: [folderROM("Gravity Rush")], settings: EmulatorSettings())

        #expect(play.availability == .refused(.noEmulator("PlayStation Vita")))
        #expect(play.availability.refusal?.message == "No PlayStation Vita emulator yet")
    }

    @Test func aGameWhosePresentROMsAreAllArchivedHasToBeUnarchivedFirst() {
        let play = Play(
            platformId: 8, platformName: "PlayStation 2",
            roms: [folderROM("Okami (USA)", archived: true), folderROM("Okami (Japan)", missing: true, id: 2)], settings: EmulatorSettings()
        )

        #expect(play.availability == .refused(.archived))
        #expect(play.availability.refusal?.message == "Archived: unarchive to play")
    }

    @Test func aGameWhoseROMsAreAllMissingHasNothingToPlay() {
        let play = Play(
            platformId: 8, platformName: "PlayStation 2",
            roms: [folderROM("Okami (USA)", missing: true), folderROM("Okami (Japan)", missing: true, id: 2)], settings: EmulatorSettings()
        )

        #expect(play.availability == .refused(.noROM))
        #expect(play.availability.refusal?.message == "No ROM in its ROM folder")
    }

    @Test func aGameWaitsWhileABackgroundTaskWorksOnOneOfItsROMs() {
        let play = Play(
            platformId: 8, platformName: "PlayStation 2", roms: [folderROM("Okami (USA)", id: 4)], settings: EmulatorSettings(),
            busyROMs: [4])

        #expect(play.availability == .refused(.busy))
        #expect(play.availability.refusal?.message == "Waiting for Archive, Unarchive or Compact to finish")
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
        installed: Bool = true, platformId: Int64 = 18
    ) -> Play.Outcome {
        let mesen = mesen
        return Play(platformId: platformId, platformName: "NES", roms: roms, settings: settings)
            .prepare(
                locator: ROMLocator(romFolders: [folder.folder]), version: version,
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
        // Sega CD, in ares, whose settings are all on the command line too.
        let segaCD = try FakeROMFolder(in: directory, platform: 78)
        try segaCD.add("Game (Disc 1).cue")
        let playlist = try segaCD.add("Game.m3u")
        func rom(_ id: Int64, _ fileName: String) -> LudeumROM {
            let name = (fileName as NSString).deletingPathExtension
            return LudeumROM(
                id: id, folderName: name, platformId: 78, fileName: fileName, name: name, version: "", disc: nil, missing: false,
                archived: false)
        }

        let outcome = Play(
            platformId: 78, platformName: "Sega CD", roms: [rom(1, "Game (Disc 1).cue"), rom(2, "Game.m3u")], settings: .init()
        )
        .prepare(locator: ROMLocator(romFolders: [segaCD.folder]), version: .ok, app: { _ in mesen })

        #expect(outcome.arguments?.last == playlist.path(percentEncoded: false))
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

        // PC Engine CD: MesenCE, which can't open a `.7z` disc.
        #expect(press([folderROM("Zelda", fileName: "Zelda.7z", archived: true)], in: ps2, platformId: 150) == .refused(.archived))
    }
}

/// Plays in xemu, which boots only an XISO.
@Suite struct XboxPlayTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "xbox play \(UUID().uuidString)")
    let xemu = URL(filePath: "/Applications/Xemu.app")

    func press(_ file: URL, in folder: FakeROMFolder) -> Play.Outcome {
        let name = file.deletingPathExtension().lastPathComponent
        let rom = LudeumROM(
            id: 1, folderName: name, platformId: ROMPlatform.xbox, fileName: file.lastPathComponent, name: name, version: "", disc: nil,
            missing: false, archived: false)
        let xemu = xemu
        return Play(platformId: ROMPlatform.xbox, platformName: "Xbox", roms: [rom], settings: EmulatorSettings())
            .prepare(
                locator: ROMLocator(romFolders: [folder.folder]), version: .ok, app: { $0 == Emulator.xemu.bundleIdentifier ? xemu : nil })
    }

    @Test func anXISOBootsInXemu() throws {
        let xbox = try FakeROMFolder(in: directory, platform: ROMPlatform.xbox)
        let file = try XboxHeader.write(into: xbox.add("Halo (USA).iso"), at: XboxHeader.xiso)

        #expect(press(file, in: xbox) == .open(app: xemu, arguments: ["-dvd_path", file.path(percentEncoded: false)], warning: nil))
    }

    @Test func aFullRedumpImageIsRefusedAsXemuCantBootIt() throws {
        let xbox = try FakeROMFolder(in: directory, platform: ROMPlatform.xbox)
        let file = try XboxHeader.write(into: xbox.add("Halo (USA).iso"), at: XboxHeader.redump)

        let outcome = press(file, in: xbox)

        #expect(outcome == .refused(.needsXISO))
        #expect(
            outcome.refusal?.message
                == "It's a full Redump image, and xemu boots only an XISO: make one with `xdvdfs pack`, then put it in its place.")
    }

    @Test func anImageThatsNeitherGoesAheadAsXemuMayKnowBetter() throws {
        let xbox = try FakeROMFolder(in: directory, platform: ROMPlatform.xbox)
        let file = try xbox.add("Halo (USA).iso", "not an Xbox disc")

        #expect(press(file, in: xbox).arguments == ["-dvd_path", file.path(percentEncoded: false)])
    }
}

/// Plays in DuckStation, whose settings go into its per-game file for the disc's Serial.
@Suite struct PlayStationPlayTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "playstation play \(UUID().uuidString)")
    let duckStation = URL(filePath: "/Applications/DuckStation.app")
    var data: URL { directory.appending(path: "DuckStation", directoryHint: .isDirectory) }

    func rom(_ fileName: String, serials: Serials) -> LudeumROM {
        let name = (fileName as NSString).deletingPathExtension
        return LudeumROM(
            id: 1, folderName: name, platformId: ROMPlatform.ps1, fileName: fileName, name: name, version: "", disc: nil,
            missing: false, archived: false, serials: serials)
    }

    func press(_ rom: LudeumROM, settings: EmulatorSettings, in folder: FakeROMFolder) -> Play.Outcome {
        let duckStation = duckStation
        return Play(platformId: ROMPlatform.ps1, platformName: "PlayStation", roms: [rom], settings: settings)
            .prepare(
                locator: ROMLocator(romFolders: [folder.folder]), version: .ok, app: { _ in duckStation },
                duckStation: DuckStationSettings(dataFolder: data, oldCopy: directory.appending(path: "old.ini")))
    }

    @Test func aGamesSettingsGoIntoThePerGameFileOfItsSerialAndDuckStationOpensTheROM() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: ROMPlatform.ps1)
        let cue = try ps1.add("Resident Evil - Director's Cut (USA).cue")

        let outcome = press(
            rom("Resident Evil - Director's Cut (USA).cue", serials: .read(["SLUS-00551"])), settings: EmulatorSettings(runAheadFrames: 1),
            in: ps1)

        #expect(outcome == .open(app: duckStation, arguments: ["--", cue.path(percentEncoded: false)], warning: nil))
        #expect(
            try String(contentsOf: data.appending(path: "gamesettings/SLUS-00551.ini"), encoding: .utf8)
                == "[Main]\nRunaheadFrameCount = 1\n\n")
    }

    @Test func aGameWithSettingsOfItsOwnIsRefusedWithoutItsSerial() {
        func refusal(_ fileName: String, _ serials: Serials) -> Play.Refusal? {
            Play(
                platformId: ROMPlatform.ps1, platformName: "PlayStation", roms: [rom(fileName, serials: serials)],
                settings: EmulatorSettings(cdReadSpeedup: 4)
            ).availability.refusal
        }

        #expect(
            refusal("Ape Escape (USA).cue", .notRead)?.message
                == "Its Serial hasn't been read yet, and DuckStation needs it for this Game's settings: it's read at the next Import.")
        #expect(
            refusal("Ape Escape (USA).cue", .read([nil]))?.message
                == "Its Disc has no Serial DuckStation can use, so this Game's settings can't be applied: set them back to Default to Play it."
        )
        // DuckStation goes by Disc 1's.
        #expect(refusal("Final Fantasy VII (USA).m3u", .read([nil, "SCUS-94164"])) == .noSerial(.noneOnDisc))
        #expect(
            refusal("Ape Escape (USA).chd", .notRead)?.message
                == "Its Serial can't be read from a .chd yet, and DuckStation needs it for this Game's settings: set them back to Default to Play it."
        )
        #expect(refusal("Ape Escape (USA).cue", .read(["SCUS-94423"])) == nil)
    }

    @Test func aPlaylistOfDiscsInAFormNotReadYetSaysSoWhenPressed() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: ROMPlatform.ps1)
        try ps1.add("Final Fantasy IX (USA)/Final Fantasy IX (USA) (Disc 1).chd")
        try ps1.add("Final Fantasy IX (USA)/Final Fantasy IX (USA).m3u", "Final Fantasy IX (USA) (Disc 1).chd\n")
        let rom = LudeumROM(
            id: 1, folderName: "Final Fantasy IX (USA)", platformId: ROMPlatform.ps1,
            fileName: "Final Fantasy IX (USA)/Final Fantasy IX (USA).m3u", name: "Final Fantasy IX (USA)", version: "", disc: nil,
            missing: false, archived: false)

        #expect(press(rom, settings: EmulatorSettings(runAheadFrames: 1), in: ps1) == .refused(.noSerial(.unreadForm("chd"))))
    }

    @Test func aGameWithNoSettingsOfItsOwnPlaysWithoutItsSerial() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: ROMPlatform.ps1)
        let cue = try ps1.add("Ape Escape (USA).cue")

        #expect(
            press(rom("Ape Escape (USA).cue", serials: .notRead), settings: EmulatorSettings(), in: ps1)
                == .open(app: duckStation, arguments: ["--", cue.path(percentEncoded: false)], warning: nil))
        #expect(!FileManager.default.fileExists(atPath: data.path(percentEncoded: false)))
    }
}
