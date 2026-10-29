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

/// Plays in Dolphin (GameCube), whose settings are all on the command line, so nothing is written outside the test.
@Suite struct PlayPressTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "play \(UUID().uuidString)")
    let dolphin = URL(filePath: "/Applications/Dolphin.app")

    func press(
        _ roms: [LudeumROM], in folder: FakeROMFolder, version: Play.VersionStatus = .ok, settings: EmulatorSettings = EmulatorSettings(),
        installed: Bool = true, platformId: Int64 = 21
    ) -> Play.Outcome {
        let dolphin = dolphin
        return Play(platformId: platformId, platformName: "Nintendo GameCube", roms: roms, settings: settings)
            .prepare(
                locator: ROMLocator(romFolders: [folder.folder]), version: version,
                app: { installed && $0 == Emulator.dolphin.bundleIdentifier ? dolphin : nil })
    }

    @Test func itOpensTheROMInTheEmulatorWithEverySetting() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let rom = try ps2.add("Zelda.iso")

        #expect(
            press([folderROM("Zelda")], in: ps2, settings: EmulatorSettings(runAheadFrames: 2))
                == .open(
                    app: dolphin,
                    arguments: [
                        "-C", "Main.Core.RushFramePresentation=True", "-C", "Main.Core.SmoothEarlyPresentation=True", "-e",
                        rom.path(percentEncoded: false),
                    ],
                    warning: nil))
    }
    @Test func aMultiDiscVersionOpensItsPlaylist() throws {
        // Saturn, in Ymir, which takes no settings at all.
        let saturn = try FakeROMFolder(in: directory, platform: 32)
        try saturn.add("Game (Disc 1).cue")
        let playlist = try saturn.add("Game.m3u")
        func rom(_ id: Int64, _ fileName: String) -> LudeumROM {
            let name = (fileName as NSString).deletingPathExtension
            return LudeumROM(
                id: id, folderName: name, platformId: 32, fileName: fileName, name: name, version: "", disc: nil, missing: false,
                archived: false)
        }

        let outcome = Play(
            platformId: 32, platformName: "Sega Saturn", roms: [rom(1, "Game (Disc 1).cue"), rom(2, "Game.m3u")], settings: .init()
        )
        .prepare(locator: ROMLocator(romFolders: [saturn.folder]), version: .ok, app: { _ in URL(filePath: "/Applications/Ymir.app") })

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

        #expect(press([folderROM("Zelda")], in: ps2, version: .tooOld("Dolphin 1 is too old")) == .refused(.tooOld("Dolphin 1 is too old")))
    }

    @Test func anEmulatorNotInstalledIsRefused() throws {
        let ps2 = try FakeROMFolder(in: directory)
        try ps2.add("Zelda.iso")

        let outcome = press([folderROM("Zelda")], in: ps2, installed: false)

        #expect(outcome == .refused(.notInstalled(.dolphin)))
        #expect(outcome.refusal?.message == "Dolphin isn't installed.")
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

/// Plays in the DuckStation Ludeum installs (ADR 0024), whose Standing settings are written first and whose per-game
/// file for the disc's Serial takes the Game's own settings.
@Suite struct PlayStationPlayTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "playstation play \(UUID().uuidString)")
    var ludeum: LudeumFolder { LudeumFolder(url: directory.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    /// The managed copy, `Emulators/DuckStation.app` in the Ludeum folder, whose data root is its `Contents/MacOS`.
    var duckStation: URL { ludeum.duckStationApp }
    var data: URL { duckStation.appending(path: "Contents/MacOS", directoryHint: .isDirectory) }

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
        try install()
    }

    /// A fake DuckStation: just its executable.
    func install() throws {
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let executable = data.appending(path: "DuckStation")
        try "#!/bin/sh\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
    }

    func rom(_ fileName: String, serials: Serials) -> LudeumROM {
        let name = (fileName as NSString).deletingPathExtension
        return LudeumROM(
            id: 1, folderName: name, platformId: ROMPlatform.ps1, fileName: fileName, name: name, version: "", disc: nil,
            missing: false, archived: false, serials: serials)
    }

    /// `running`: DuckStation is open.
    func press(_ rom: LudeumROM, settings: EmulatorSettings, in folder: FakeROMFolder, running: Bool = false) -> Play.Outcome {
        Play(platformId: ROMPlatform.ps1, platformName: "PlayStation", roms: [rom], settings: settings)
            .prepare(
                locator: ROMLocator(romFolders: [folder.folder]), version: .ok, app: { _ in nil },
                duckStation: DuckStationSettings(ludeum: ludeum), running: { _ in running })
    }

    @Test func aPlayWritesTheStandingSettingsAndTheGamesOwnIntoItsPerGameFileThenOpensTheROM() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: ROMPlatform.ps1)
        let cue = try ps1.add("Resident Evil - Director's Cut (USA).cue")

        let outcome = press(
            rom("Resident Evil - Director's Cut (USA).cue", serials: .read(["SLUS-00551"])), settings: EmulatorSettings(runAheadFrames: 1),
            in: ps1)

        #expect(outcome == .open(app: duckStation, arguments: ["--", cue.path(percentEncoded: false)], warning: nil))
        let standing = try String(contentsOf: data.appending(path: "settings.ini"), encoding: .utf8)
        #expect(
            Ini.value("SaveStates", in: "Folders", of: standing)
                == String(ludeum.duckStationSaveStates.path(percentEncoded: false).dropLast()))
        #expect(Ini.value("CheckAtStartup", in: "AutoUpdater", of: standing) == "false")
        // The per-game file is where the Standing settings keep them: in the Data folder.
        #expect(
            try String(contentsOf: ludeum.duckStation(.gameSettings).appending(path: "SLUS-00551.ini"), encoding: .utf8)
                == "[Main]\nRunaheadFrameCount = 1\n\n")
    }

    @Test func aGameWithNoSettingsOfItsOwnPlaysWithoutItsSerial() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: ROMPlatform.ps1)
        let cue = try ps1.add("Ape Escape (USA).cue")

        let outcome = press(rom("Ape Escape (USA).cue", serials: .notRead), settings: EmulatorSettings(), in: ps1)

        #expect(outcome == .open(app: duckStation, arguments: ["--", cue.path(percentEncoded: false)], warning: nil))
        #expect(!FileManager.default.fileExists(atPath: ludeum.duckStation(.gameSettings).appending(path: "Ape Escape (USA).ini").path()))
    }

    @Test func aGameWithSettingsOfItsOwnIsRefusedWithoutItsSerial() {
        func refusal(_ fileName: String, _ serials: Serials, _ settings: EmulatorSettings = EmulatorSettings(runAheadFrames: 1)) -> Play
            .Refusal?
        {
            Play(
                platformId: ROMPlatform.ps1, platformName: "PlayStation", roms: [rom(fileName, serials: serials)], settings: settings
            ).availability.refusal
        }

        #expect(
            refusal("Ape Escape (USA).cue", .notRead)?.message
                == "Its Serial hasn't been read yet, and its own DuckStation settings need it: it's read at the next Import. "
                + "Set them back to Default to Play meanwhile.")
        #expect(
            refusal("Ape Escape (USA).cue", .read([nil]), EmulatorSettings(cdReadSpeedup: 4))?.message
                == "Its Disc has no Serial DuckStation can use, so it can't have DuckStation settings of its own: set them back to Default to Play."
        )
        // DuckStation goes by Disc 1's.
        #expect(refusal("Final Fantasy VII (USA).m3u", .read([nil, "SCUS-94164"])) == .noSerial(.noneOnDisc))
        #expect(
            refusal("Ape Escape (USA).chd", .notRead)?.message
                == "Its Serial can't be read from a .chd yet, so it can't have DuckStation settings of its own: set them back to Default to Play."
        )
        #expect(refusal("Ape Escape (USA).cue", .read(["SCUS-94423"])) == nil)
        #expect(refusal("Ape Escape (USA).cue", .notRead, EmulatorSettings()) == nil)
    }

    @Test func withoutTheDuckStationLudeumInstallsPlayIsRefused() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: ROMPlatform.ps1)
        try ps1.add("Ape Escape (USA).cue")
        try FileManager.default.removeItem(at: duckStation)

        let outcome = press(rom("Ape Escape (USA).cue", serials: .read(["SCUS-94423"])), settings: EmulatorSettings(), in: ps1)

        #expect(outcome == .refused(.notInstalled(.duckStation)))
        #expect(outcome.refusal?.message == "DuckStation isn't installed. Install it from Ludeum ▸ Emulators…")
    }

    @Test func playIsRefusedWhileDuckStationIsOpenAsItWouldWriteOverItsSettings() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: ROMPlatform.ps1)
        try ps1.add("Ape Escape (USA).cue")
        let outcome = press(
            rom("Ape Escape (USA).cue", serials: .read(["SCUS-94423"])), settings: EmulatorSettings(), in: ps1, running: true)

        #expect(outcome == .refused(.running(.duckStation)))
        #expect(outcome.refusal?.message.hasPrefix("DuckStation is open. Quit it, then Play") == true)
        #expect(!FileManager.default.fileExists(atPath: data.appending(path: "settings.ini").path()))
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

    // MARK: Starting on a Disc (ADR 0026)

    static let gt2 = "Gran Turismo 2 (Europe)"
    static let gt2Discs = [
        "Gran Turismo 2 (Europe) (Disc 1) (Arcade Mode Disc).cue",
        "Gran Turismo 2 (Europe) (En,Fr,De,Es,It) (Disc 2) (Gran Turismo Mode).cue",
    ]

    /// Gran Turismo 2's folder ROM: its two Discs and its playlist. Returns the playlist and each Disc's cue sheet.
    func addGT2(to ps1: FakeROMFolder) throws -> (playlist: URL, discs: [URL]) {
        let discs = try Self.gt2Discs.map { try ps1.add("\(Self.gt2)/\($0)") }
        let playlist = try ps1.add("\(Self.gt2)/\(Self.gt2).m3u", Self.gt2Discs.joined(separator: "\n") + "\n")
        return (playlist, discs)
    }

    func gt2ROM(lastDisc: Int? = nil) -> LudeumROM {
        var rom = LudeumROM(
            id: 7, folderName: Self.gt2, platformId: ROMPlatform.ps1, fileName: "\(Self.gt2)/\(Self.gt2).m3u", name: Self.gt2,
            version: "", disc: nil, missing: false, archived: false, serials: .read(["SCES-02380", "SCES-12380"]))
        rom.lastDisc = lastDisc
        return rom
    }

    func play(_ rom: LudeumROM) -> Play {
        Play(platformId: ROMPlatform.ps1, platformName: "PlayStation", roms: [rom], settings: EmulatorSettings())
    }

    func press(_ rom: LudeumROM, in folder: FakeROMFolder, disc: Int? = nil, saveState: URL? = nil) -> Play.Outcome {
        play(rom).prepare(
            locator: ROMLocator(romFolders: [folder.folder]), version: .ok, app: { _ in nil }, saveState: saveState, disc: disc,
            duckStation: DuckStationSettings(ludeum: ludeum))
    }

    @Test func aMultiDiscROMsDiscsAreItsPlaylistsWithTheirLabels() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: ROMPlatform.ps1)
        let gt2 = try addGT2(to: ps1)
        let mgs = "Metal Gear Solid (USA) (v1.1)"
        try ps1.add("\(mgs)/\(mgs).m3u", "Metal Gear Solid (USA) (Disc 1) (v1.1).cue\nMetal Gear Solid (USA) (Disc 2) (v1.1).cue\n")
        let mgsROM = LudeumROM(
            id: 8, folderName: mgs, platformId: ROMPlatform.ps1, fileName: "\(mgs)/\(mgs).m3u", name: mgs, version: "", disc: nil,
            missing: false, archived: false)
        let locator = ROMLocator(romFolders: [ps1.folder])

        let discs = play(gt2ROM()).discs(locator: locator)

        #expect(discs.map(\.labelOrNumber) == ["Arcade Mode Disc", "Gran Turismo Mode"])
        #expect(discs.map(\.serial) == ["SCES-02380", "SCES-12380"])
        #expect(discs.map(\.numberAndLabel) == ["Disc 1 · Arcade Mode Disc", "Disc 2 · Gran Turismo Mode"])
        #expect(discs.map(\.file) == gt2.discs)
        // A Version's tag is never a Disc label.
        #expect(play(mgsROM).discs(locator: locator).map(\.numberAndLabel) == ["Disc 1", "Disc 2"])
    }

    @Test func aROMOfOneDiscHasNoDiscsToChooseFrom() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: ROMPlatform.ps1)
        try ps1.add("Ape Escape (USA).cue")

        #expect(play(rom("Ape Escape (USA).cue", serials: .notRead)).discs(locator: ROMLocator(romFolders: [ps1.folder])).isEmpty)
        #expect(press(rom("Ape Escape (USA).cue", serials: .notRead), in: ps1).startsOn == nil)
    }

    @Test func atFirstAMultiDiscROMStartsOnDisc1ThroughItsPlaylist() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: ROMPlatform.ps1)
        let gt2 = try addGT2(to: ps1)

        let outcome = press(gt2ROM(), in: ps1)

        #expect(outcome.arguments == ["--", gt2.playlist.path(percentEncoded: false)])
        #expect(outcome.startsOn == Play.DiscStart(rom: 7, disc: 1))
        #expect(play(gt2ROM()).startingDisc(among: play(gt2ROM()).discs(locator: ROMLocator(romFolders: [ps1.folder])))?.number == 1)
    }

    @Test func aChosenDiscOpensAsItsOwnCueSheet() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: ROMPlatform.ps1)
        let gt2 = try addGT2(to: ps1)

        let outcome = press(gt2ROM(), in: ps1, disc: 2)

        // DuckStation can't be told which of a playlist's Discs to boot.
        #expect(outcome.arguments == ["--", gt2.discs[1].path(percentEncoded: false)])
        #expect(outcome.startsOn == Play.DiscStart(rom: 7, disc: 2))
        // Disc 1 chosen is the playlist, so a Disc set DuckStation doesn't know still swaps.
        #expect(press(gt2ROM(lastDisc: 2), in: ps1, disc: 1).arguments == ["--", gt2.playlist.path(percentEncoded: false)])
    }

    @Test func itStartsOnTheDiscItLastStartedOn() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: ROMPlatform.ps1)
        let gt2 = try addGT2(to: ps1)

        let outcome = press(gt2ROM(lastDisc: 2), in: ps1)

        #expect(outcome.arguments == ["--", gt2.discs[1].path(percentEncoded: false)])
        #expect(outcome.startsOn == Play.DiscStart(rom: 7, disc: 2))
        #expect(
            play(gt2ROM(lastDisc: 2)).startingDisc(among: play(gt2ROM()).discs(locator: ROMLocator(romFolders: [ps1.folder])))?.number == 2)
    }

    @Test func aLastDiscItNoLongerHasStartsOnDisc1() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: ROMPlatform.ps1)
        let gt2 = try addGT2(to: ps1)

        let outcome = press(gt2ROM(lastDisc: 3), in: ps1)

        #expect(outcome.arguments == ["--", gt2.playlist.path(percentEncoded: false)])
        #expect(outcome.startsOn == Play.DiscStart(rom: 7, disc: 1))
        #expect(press(gt2ROM(), in: ps1, disc: 5).startsOn == Play.DiscStart(rom: 7, disc: 1))
        // Nor one whose file is gone, unless it's chosen.
        try FileManager.default.removeItem(at: gt2.discs[1])
        #expect(press(gt2ROM(lastDisc: 2), in: ps1).startsOn == Play.DiscStart(rom: 7, disc: 1))
        #expect(press(gt2ROM(), in: ps1, disc: 2) == .refused(.fileNotFound(gt2.discs[1].lastPathComponent)))
    }

    @Test func aSaveStateStartsOnItsOwnDisc() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: ROMPlatform.ps1)
        let gt2 = try addGT2(to: ps1)
        let state = ludeum.duckStationSaveStates.appending(path: "SCES-12380_3.sav")

        let outcome = press(gt2ROM(), in: ps1, saveState: state)

        // DuckStation boots the disc the state was saved with; its own Disc is what it falls back to.
        #expect(outcome.arguments == ["-statefile", state.path(percentEncoded: false), "--", gt2.discs[1].path(percentEncoded: false)])
        #expect(outcome.startsOn == Play.DiscStart(rom: 7, disc: 2))
        #expect(
            press(gt2ROM(lastDisc: 2), in: ps1, saveState: state.deletingLastPathComponent().appending(path: "SCES-02380_resume.sav"))
                .startsOn == Play.DiscStart(rom: 7, disc: 1))
        // One whose Disc can't be told opens the playlist, and nothing's remembered.
        let unknown = press(gt2ROM(lastDisc: 2), in: ps1, saveState: state.deletingLastPathComponent().appending(path: "SLUS-00551_1.sav"))
        #expect(unknown.arguments?.last == gt2.playlist.path(percentEncoded: false))
        #expect(unknown.startsOn == nil)
    }
}

/// The Disc a multi-disc ROM last started on, kept on the ROM and nothing else about the Play (ADR 0026).
@Suite struct LastDiscTests {
    let h: LudeumHarness

    init() throws { h = try LudeumHarness() }

    @Test func aROMRemembersTheDiscItLastStartedOn() throws {
        let game = try h.addGame("Gran Turismo 2")
        let rom = try h.journal.db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO rom (folderName, fileName, name, platformId, gameId, matchKind, matchedAt)
                    VALUES ('GT2', 'GT2/GT2.m3u', 'GT2', 19, ?, 'manual', 0)
                    """, arguments: [game])
            return db.lastInsertedRowID
        }
        #expect(try h.journal.rom(rom)?.lastDisc == nil)

        #expect(try h.journal.setLastDisc(Play.DiscStart(rom: rom, disc: 2)))
        #expect(try h.journal.rom(rom)?.lastDisc == 2)
        // The same Disc again is no change.
        #expect(try !h.journal.setLastDisc(Play.DiscStart(rom: rom, disc: 2)))

        #expect(try h.journal.setLastDisc(Play.DiscStart(rom: rom, disc: 1)))
        #expect(try h.journal.rom(rom)?.lastDisc == 1)
    }
}
