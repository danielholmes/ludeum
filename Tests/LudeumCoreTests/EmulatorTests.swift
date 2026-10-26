import Foundation
import Testing

@testable import LudeumCore

@Suite struct EmulatorTests {
    @Test func nesAndSNESGamesArePlayedInMesenCE() {
        for platform: Int64 in [18, 99, 19, 58, 33, 22, 24, 64, 35, 86, 150] { #expect(Emulator.of(platformId: platform) == .mesenCE) }
        #expect(Emulator.of(platformId: 7) == .duckStation)  // PlayStation
        #expect(Emulator.of(platformId: 21) == .dolphin)  // GameCube
        #expect(Emulator.of(platformId: 5) == .dolphin)  // Wii
        #expect(Emulator.of(platformId: 29) == .ares)  // Mega Drive/Genesis
        #expect(Emulator.of(platformId: 4) == .ares)  // Nintendo 64
        #expect(Emulator.of(platformId: 20) == .melonDS)  // Nintendo DS
        #expect(Emulator.of(platformId: 78) == .ares)  // Sega CD
        #expect(Emulator.of(platformId: 32) == .ymir)  // Saturn
        #expect(Emulator.of(platformId: 11) == .xemu)  // Xbox
    }

    @Test func everyPlaySetsAllTheSettingsWithoutSavingThem() throws {
        let rom = URL(filePath: "/Games/roms/NES/Super Mario Bros. 3 (USA).nes")

        #expect(
            try Emulator.mesenCE.arguments(rom: rom, platformId: 18, settings: EmulatorSettings())
                == ["--doNotSaveSettings", "--emulation.runAheadFrames=0", "/Games/roms/NES/Super Mario Bros. 3 (USA).nes"])
        #expect(
            try Emulator.mesenCE.arguments(rom: rom, platformId: 18, settings: EmulatorSettings(runAheadFrames: 2))
                == ["--doNotSaveSettings", "--emulation.runAheadFrames=2", "/Games/roms/NES/Super Mario Bros. 3 (USA).nes"])
    }

    @Test func gameBoyPlaysSetTheGameBoyModelAutoByDefault() throws {
        let rom = URL(filePath: "/Games/GB/Tetris (World).gb")
        func play(_ platformId: Int64, _ model: GameBoyModel?) throws -> [String] {
            try Emulator.mesenCE.arguments(rom: rom, platformId: platformId, settings: EmulatorSettings(gameBoyModel: model))
        }

        #expect(
            try play(33, nil)
                == ["--doNotSaveSettings", "--emulation.runAheadFrames=0", "--gameboy.model=AutoFavorGbc", "/Games/GB/Tetris (World).gb"])
        #expect(try play(33, .gameBoy).contains("--gameboy.model=Gameboy"))
        #expect(try play(22, .gameBoyColor).contains("--gameboy.model=GameboyColor"))
        #expect(try play(33, .superGameBoy).contains("--gameboy.model=SuperGameboy"))
        #expect(!(try play(18, .superGameBoy)).contains { $0.hasPrefix("--gameboy.model") })  // NES
    }

    @Test func aGamesGameBoyModelIsKept() throws {
        let h = try LudeumHarness()
        let game = try h.addGame("Tetris")

        try h.journal.setEmulatorSettings(game, EmulatorSettings(gameBoyModel: .superGameBoy))
        try h.reopen()
        #expect(try h.journal.emulatorSettings(game) == EmulatorSettings(gameBoyModel: .superGameBoy))
    }

    @Test func aresRunAheadIsOnOrOff() throws {
        let rom = URL(filePath: "/Games/Genesis/Sonic the Hedgehog (USA, Europe).md")
        func runAhead(_ frames: Int?) throws -> [String] {
            try Emulator.ares.arguments(rom: rom, platformId: 29, settings: EmulatorSettings(runAheadFrames: frames))
        }

        #expect(
            try runAhead(nil)
                == ["--system", "Mega Drive", "--setting", "General/RunAhead=false", "/Games/Genesis/Sonic the Hedgehog (USA, Europe).md"])
        #expect(try runAhead(0).contains("General/RunAhead=false"))
        #expect(try runAhead(1).contains("General/RunAhead=true"))
    }

    @Test func aGamesSettingsAreKeptAndCanBeClearedBackToTheDefault() throws {
        let h = try LudeumHarness()
        let game = try h.addGame("Super Mario Bros. 3")
        #expect(try h.journal.emulatorSettings(game) == EmulatorSettings())

        try h.journal.setEmulatorSettings(game, EmulatorSettings(runAheadFrames: 1))
        try h.reopen()
        #expect(try h.journal.emulatorSettings(game) == EmulatorSettings(runAheadFrames: 1))

        try h.journal.setEmulatorSettings(game, EmulatorSettings())
        #expect(try h.journal.emulatorSettings(game).runAheadFrames == nil)
    }

    @Test func runAheadIsZeroToTenFrames() throws {
        let h = try LudeumHarness()
        let game = try h.addGame("Super Mario Bros. 3")

        #expect(throws: LudeumError.runAheadOutOfRange) { try h.journal.setEmulatorSettings(game, EmulatorSettings(runAheadFrames: 11)) }
        #expect(throws: LudeumError.runAheadOutOfRange) { try h.journal.setEmulatorSettings(game, EmulatorSettings(runAheadFrames: -1)) }
        try h.journal.setEmulatorSettings(game, EmulatorSettings(runAheadFrames: 10))
    }
}

@Test func everyDolphinPlayLowersInputLatencyForThatLaunchOnly() throws {
    let rom = URL(filePath: "/Games/GameCube/Pikmin (USA).rvz")

    #expect(
        try Emulator.dolphin.arguments(rom: rom, platformId: 21, settings: EmulatorSettings())
            == [
                "-C", "Main.Core.RushFramePresentation=True", "-C", "Main.Core.SmoothEarlyPresentation=True", "-e",
                "/Games/GameCube/Pikmin (USA).rvz",
            ])
}

@Test func aWiiWareWADPlaysInDolphinLikeADisc() throws {
    let rom = URL(filePath: "/Games/Wii/World of Goo (USA) (WiiWare).wad")

    #expect(try Emulator.dolphin.arguments(rom: rom, platformId: 5, settings: EmulatorSettings()).suffix(2) == ["-e", rom.path])
}

@Test func aresPlaysNintendo64GamesAsNintendo64() throws {
    #expect(
        try Emulator.ares.arguments(
            rom: URL(filePath: "/Games/N64/Super Mario 64 (USA).z64"), platformId: 4, settings: EmulatorSettings(runAheadFrames: 1))
            == ["--system", "Nintendo 64", "--setting", "General/RunAhead=true", "/Games/N64/Super Mario 64 (USA).z64"])
}

@Test func aresPlaysSegaCDGamesAsMegaCD() throws {
    let rom = URL(filePath: "/Games/SegaCD/Sonic CD (USA).cue")
    #expect(try Emulator.ares.arguments(rom: rom, platformId: 78, settings: EmulatorSettings()).prefix(2) == ["--system", "Mega CD"])
}

@Test func ymirJustOpensTheDisc() throws {
    let rom = URL(filePath: "/Games/Saturn/Panzer Dragoon Saga (USA) (Disc 1).cue")
    #expect(try Emulator.ymir.arguments(rom: rom, platformId: 32, settings: EmulatorSettings()) == [rom.path(percentEncoded: false)])
}

@Test func melonDSJustOpensTheGame() throws {
    let rom = URL(filePath: "/Games/DS/Advance Wars - Dual Strike (USA).nds")
    #expect(
        try Emulator.melonDS.arguments(rom: rom, platformId: 20, settings: EmulatorSettings()) == [
            "/Games/DS/Advance Wars - Dual Strike (USA).nds"
        ])
}

@Test func xemuJustBootsTheDisc() throws {
    let rom = URL(filePath: "/Games/Xbox/Halo - Combat Evolved (USA).iso")
    #expect(
        try Emulator.xemu.arguments(rom: rom, platformId: 11, settings: EmulatorSettings()) == [
            "-dvd_path", "/Games/Xbox/Halo - Combat Evolved (USA).iso",
        ])
}

@Suite struct DuckStationSettingsTests {
    let folder = FileManager.default.temporaryDirectory.appending(
        path: "duckstation tests \(UUID().uuidString)", directoryHint: .isDirectory)
    var settings: DuckStationSettings { DuckStationSettings(dataFolder: folder, oldCopy: folder.appending(path: "old copy.ini")) }

    func gameSettings(_ serial: String) -> URL { folder.appending(path: "gamesettings/\(serial).ini") }
    /// What every Play writes, the Game's own settings or none.
    let fastBoot = "[BIOS]\nFastForwardBoot = true\nPatchFastBoot = true\n\n"

    func write(_ text: String, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    func contents(_ file: URL) -> String? { try? String(contentsOf: file, encoding: .utf8) }

    @Test func aPlayMergesTheGamesSettingsIntoDuckStationsPerGameFileForItsSerial() throws {
        try write("[Main]\nRewindEnable = false\n\n[Pad1]\nUp = Keyboard/Up\n", to: folder.appending(path: "settings.ini"))
        try write("[Main]\nRunaheadFrameCount = 0\n\n[GPU]\nResolutionScale = 4\n", to: gameSettings("SLUS-00551"))
        let rom = URL(filePath: "/Games/PSX/Resident Evil - Director's Cut (USA)/Resident Evil - Director's Cut (USA).cue")

        let arguments = try Emulator.duckStation.arguments(
            rom: rom, platformId: 7, settings: EmulatorSettings(runAheadFrames: 2, cdReadSpeedup: 4, cdSeekSpeedup: 0),
            serials: .read(["SLUS-00551"]),
            duckStation: settings)

        #expect(arguments == ["--", rom.path(percentEncoded: false)])
        #expect(
            contents(gameSettings("SLUS-00551"))
                == fastBoot + "[CDROM]\nSeekSpeedup = 0\nReadSpeedup = 4\n\n[Main]\nRunaheadFrameCount = 2\n\n[GPU]\nResolutionScale = 4\n")
        // DuckStation's own settings are left alone.
        #expect(contents(folder.appending(path: "settings.ini")) == "[Main]\nRewindEnable = false\n\n[Pad1]\nUp = Keyboard/Up\n")
    }

    @Test func aSettingTheGameHasntGotIsTakenOutSoDuckStationsOwnApplies() {
        let ini = """
            [Main]
            RunaheadFrameCount = 3
            RewindEnable = false

            [CDROM]
            ReadSpeedup = 4
            SeekSpeedup = 2

            [BIOS]
            PatchFastBoot = true
            FastForwardBoot = true

            [GPU]
            ResolutionScale = 4

            """
        #expect(
            DuckStationSettings.applying(EmulatorSettings(), to: ini)
                == "[Main]\nRewindEnable = false\n\n[BIOS]\nPatchFastBoot = true\nFastForwardBoot = true\n\n[GPU]\nResolutionScale = 4\n")
        #expect(
            DuckStationSettings.applying(EmulatorSettings(runAheadFrames: 0, cdSeekSpeedup: 1), to: ini)
                == "[Main]\nRunaheadFrameCount = 0\nRewindEnable = false\n\n[CDROM]\nSeekSpeedup = 1\n\n[BIOS]\nPatchFastBoot = true\n"
                + "FastForwardBoot = true\n\n[GPU]\nResolutionScale = 4\n")
    }

    @Test func aFileWithCRLFLineEndingsIsMergedLineByLine() {
        let ini =
            "[BIOS]\r\nPatchFastBoot = false\r\n\r\n[Main]\r\nRunaheadFrameCount = 3\r\nRewindEnable = false\r\n\r\n[CDROM]\r\nReadSpeedup = 4\r\n"
        #expect(
            DuckStationSettings.applying(EmulatorSettings(runAheadFrames: 1), to: ini)
                == "[BIOS]\r\nFastForwardBoot = true\nPatchFastBoot = true\n\r\n[Main]\r\nRunaheadFrameCount = 1\nRewindEnable = false\r\n\r\n"
        )
        #expect(Ini.value("ReadSpeedup", in: "CDROM", of: ini) == "4")
    }

    @Test func everyGameFastBootsEvenWithNoSettingsOfItsOwn() throws {
        try settings.write(EmulatorSettings(), serials: .read(["SLUS-00551"]))
        #expect(contents(gameSettings("SLUS-00551")) == fastBoot)

        try write("[Main]\nRunaheadFrameCount = 1\n", to: gameSettings("SCUS-94900"))
        try settings.write(EmulatorSettings(), serials: .read(["SCUS-94900"]))
        #expect(contents(gameSettings("SCUS-94900")) == fastBoot)
    }

    @Test func aMultiDiscVersionsSettingsAreDisc1sUnlessItKeepsEachDiscApart() throws {
        let serials = Serials.read(["SCUS-94163", "SCUS-94164", nil])
        try settings.write(EmulatorSettings(runAheadFrames: 1), serials: serials)
        #expect(contents(gameSettings("SCUS-94163")) == fastBoot + "[Main]\nRunaheadFrameCount = 1\n\n")
        #expect(contents(gameSettings("SCUS-94164")) == nil)

        try write("[Main]\nUseSeparateConfigForDiscSet = true\n", to: gameSettings("SCUS-94163"))
        try settings.write(EmulatorSettings(runAheadFrames: 1), serials: serials)
        #expect(
            contents(gameSettings("SCUS-94163"))
                == fastBoot + "[Main]\nRunaheadFrameCount = 1\nUseSeparateConfigForDiscSet = true\n")
        #expect(contents(gameSettings("SCUS-94164")) == fastBoot + "[Main]\nRunaheadFrameCount = 1\n\n")
    }

    @Test func withoutDisc1sSerialNothingIsWritten() throws {
        try settings.write(EmulatorSettings(runAheadFrames: 1), serials: .notRead)
        try settings.write(EmulatorSettings(runAheadFrames: 1), serials: .read([nil, "SCUS-94164"]))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "gamesettings").path(percentEncoded: false)))
    }

    @Test func perGameFilesAreWhereDuckStationsSettingsPutThem() throws {
        try write("[Folders]\nGameSettings = per game\n", to: folder.appending(path: "settings.ini"))
        #expect(settings.gameSettingsFolder == folder.appending(path: "per game", directoryHint: .isDirectory))
        try write("[Folders]\nGameSettings = /Volumes/Games/settings\n", to: folder.appending(path: "settings.ini"))
        #expect(settings.gameSettingsFolder == URL(filePath: "/Volumes/Games/settings", directoryHint: .isDirectory))
    }

    @Test func theCopyAPlayUsedToWriteGoes() throws {
        try write("[Main]\n", to: folder.appending(path: "old copy.ini"))
        try settings.write(EmulatorSettings(), serials: .notRead)
        #expect(contents(folder.appending(path: "old copy.ini")) == nil)
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
}

@Suite struct PPSSPPSettingsTests {
    let folder = FileManager.default.temporaryDirectory.appending(
        path: "ppsspp tests \(UUID().uuidString)", directoryHint: .isDirectory)

    @Test func pspGamesArePlayedInPPSSPP() {
        #expect(Emulator.of(platformId: 38) == .ppsspp)
    }

    @Test func aPlayStartsFromACopyOfPPSSPPsOwnSettingsWithLowLatencyDisplay() throws {
        let base = folder.appending(path: "ppsspp.ini")
        let copy = folder.appending(path: "copy.ini")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "[Graphics]\nInflightFrames = 2\nVerticalSync = True\n\n[Sound]\nEnable = True\n".write(
            to: base, atomically: true, encoding: .utf8)
        let rom = URL(filePath: "/Games/PSP/Patapon (USA).iso")

        let arguments = try Emulator.ppsspp.arguments(
            rom: rom, platformId: 38, settings: EmulatorSettings(), ppsspp: PPSSPPSettings(base: base, copy: copy))

        #expect(arguments == ["--config=\(copy.path(percentEncoded: false))", "/Games/PSP/Patapon (USA).iso"])
        #expect(
            try String(contentsOf: copy, encoding: .utf8)
                == "[Graphics]\nFrameSkip = 0\nLowLatencyPresent = True\nInflightFrames = 1\nVerticalSync = True\n\n[Sound]\nEnable = True\n"
        )
        #expect(try String(contentsOf: base, encoding: .utf8).contains("InflightFrames = 2"))
    }

    @Test func withNoPPSSPPSettingsYetTheCopyHasJustTheLatencySettings() {
        #expect(PPSSPPSettings.applying(to: "") == "[Graphics]\nFrameSkip = 0\nLowLatencyPresent = True\nInflightFrames = 1\n\n")
    }
}

@Suite struct PCSX2Tests {
    @Test func ps2GamesArePlayedInPCSX2() {
        #expect(Emulator.of(platformId: 8) == .pcsx2)
    }

    @Test func aPlayBootsTheGameWithOptimalFramePacingFromAGameSettingsFile() throws {
        let copy = FileManager.default.temporaryDirectory.appending(path: "pcsx2 \(UUID().uuidString)/game.ini")
        let rom = URL(filePath: "/Games/PS2/Okami (USA).iso")

        let arguments = try Emulator.pcsx2.arguments(
            rom: rom, platformId: 8, settings: EmulatorSettings(), pcsx2: PCSX2GameSettings(file: copy))

        #expect(arguments == ["-batch", "-fastboot", "-gamecfg", copy.path(percentEncoded: false), "--", "/Games/PS2/Okami (USA).iso"])
        #expect(try String(contentsOf: copy, encoding: .utf8) == "[EmuCore/GS]\nVsyncQueueSize = 0\n")
    }
}
