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

    @Test func aGamesGameBoyModelIsKept() throws {
        let h = try LudeumHarness()
        let game = try h.addGame("Tetris")

        try h.journal.setEmulatorSettings(game, EmulatorSettings(gameBoyModel: .superGameBoy))
        try h.reopen()
        #expect(try h.journal.emulatorSettings(game) == EmulatorSettings(gameBoyModel: .superGameBoy))
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

@Test func everyDolphinPlayLowersInputLatencyAndSwapsDiscsForThatLaunchOnly() throws {
    let rom = URL(filePath: "/Games/GameCube/Pikmin (USA).rvz")

    #expect(
        try Emulator.dolphin.arguments(rom: rom, platformId: 21, settings: EmulatorSettings())
            == [
                "-C", "Main.Core.RushFramePresentation=True", "-C", "Main.Core.SmoothEarlyPresentation=True", "-C",
                "Main.Core.AutoDiscChange=True", "-e", "/Games/GameCube/Pikmin (USA).rvz",
            ])
}

@Test func aMultiDiscGameCubeROMPlaysFromItsPlaylist() throws {
    let rom = URL(filePath: "/Games/GameCube/Resident Evil (USA)/Resident Evil (USA).m3u")

    #expect(try Emulator.dolphin.arguments(rom: rom, platformId: 21, settings: EmulatorSettings()).suffix(2) == ["-e", rom.path])
}

@Test func aWiiWareWADPlaysInDolphinLikeADisc() throws {
    let rom = URL(filePath: "/Games/Wii/World of Goo (USA) (WiiWare).wad")

    #expect(try Emulator.dolphin.arguments(rom: rom, platformId: 5, settings: EmulatorSettings()).suffix(2) == ["-e", rom.path])
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

/// The PCSX2 Ludeum installs and its Standing settings (ADR 0032).
@Suite struct PCSX2Tests {
    let root = FileManager.default.temporaryDirectory.appending(path: "pcsx2 \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var settings: PCSX2Settings { PCSX2Settings(ludeum: ludeum) }
    var ini: URL { ludeum.pcsx2Folder.appending(path: "inis/PCSX2.ini") }
    let rom = URL(filePath: "/Games/PS2/Okami (USA).iso")

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    func value(_ key: String, in section: String) throws -> String? {
        Ini.value(key, in: section, of: try String(contentsOf: ini, encoding: .utf8))
    }

    @Test func ps2GamesArePlayedInPCSX2() {
        #expect(Emulator.of(platformId: 8) == .pcsx2)
        #expect(Emulator.pcsx2.isLudeums)
    }

    @Test func aPlayPointsPCSX2AtItsFoldersInTheDataFolderAndQuitsWithTheGame() throws {
        let arguments = try Emulator.pcsx2.arguments(rom: rom, platformId: 8, settings: EmulatorSettings(), pcsx2: settings)

        #expect(arguments == ["-batch", "--", "/Games/PS2/Okami (USA).iso"])
        let data = ludeum.data.path(percentEncoded: false)
        #expect(try value("Savestates", in: "Folders") == "\(data)Emulators/PCSX2/Save States")
        #expect(try value("MemoryCards", in: "Folders") == "\(data)Emulators/PCSX2/Memory Cards")
        #expect(try value("Bios", in: "Folders") == "\(data)Emulators/PCSX2/BIOS")
        #expect(try value("GameSettings", in: "Folders") == "\(data)Emulators/PCSX2/Game Settings")
        #expect(try value("Snapshots", in: "Folders") == "\(data)Emulators/PCSX2/Screenshots")
        #expect(try value("Textures", in: "Folders") == "\(data)Emulators/PCSX2/Textures")
        #expect(try value("VsyncQueueSize", in: "EmuCore/GS") == "0")
        #expect(try value("EnableFastBoot", in: "EmuCore") == "true")
        #expect(try value("SaveStateOnShutdown", in: "EmuCore") == "true")
        #expect(try value("CheckAtStartup", in: "AutoUpdater") == "false")
        #expect(try value("SettingsVersion", in: "UI") == "1")
        for folder in PCSX2Folder.allCases {
            #expect(FileManager.default.fileExists(atPath: ludeum.pcsx2(folder).path(percentEncoded: false)), "\(folder.name)")
        }
    }

    @Test func aFilePCSX2HasntMadeYetGetsItsOwnFirstRunControlsAndHotkeys() throws {
        try settings.writeStanding()

        #expect(try value("Type", in: "Pad1") == "DualShock2")
        #expect(try value("Cross", in: "Pad1") == "Keyboard/K")
        #expect(try value("LUp", in: "Pad1") == "Keyboard/W")
        #expect(try value("SaveStateToSlot", in: "Hotkeys") == "Keyboard/F1")
        #expect(try value("LoadStateFromSlot", in: "Hotkeys") == "Keyboard/F3")
        #expect(try value("HoldTurbo", in: "Hotkeys") == "Keyboard/Period")
    }

    @Test func everythingElseInItsSettingsStaysItsOwnAndAFileItMadeGetsNoControlsFromLudeum() throws {
        try FileManager.default.createDirectory(at: ini.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        [UI]
        SettingsVersion = 1
        MainWindowGeometry = abc

        [Folders]
        Logs = logs
        Savestates = sstates

        [Pad1]
        Type = DualShock2
        Cross = SDL-0/A

        [EmuCore/GS]
        Renderer = 17
        VsyncQueueSize = 2

        """.write(to: ini, atomically: true, encoding: .utf8)

        try settings.writeStanding()

        #expect(try value("MainWindowGeometry", in: "UI") == "abc")
        #expect(try value("Logs", in: "Folders") == "logs")
        #expect(try value("Savestates", in: "Folders") == "\(ludeum.data.path(percentEncoded: false))Emulators/PCSX2/Save States")
        #expect(try value("Cross", in: "Pad1") == "SDL-0/A")
        #expect(try value("Up", in: "Pad1") == nil)
        #expect(try value("SaveStateToSlot", in: "Hotkeys") == nil)
        #expect(try value("Renderer", in: "EmuCore/GS") == "17")
        #expect(try value("VsyncQueueSize", in: "EmuCore/GS") == "0")
        // Written once: the same again leaves the file alone.
        let modified = try FileManager.default.attributesOfItem(atPath: ini.path(percentEncoded: false))[.modificationDate] as? Date
        try settings.writeStanding()
        #expect(try FileManager.default.attributesOfItem(atPath: ini.path(percentEncoded: false))[.modificationDate] as? Date == modified)
    }

    @Test func playFromASaveStateLoadsItOnceTheGameHasBooted() throws {
        let state = ludeum.pcsx2SaveStates.appending(path: "SLUS-20062 (2C9A8B3F).01.p2s")

        let arguments = try Emulator.pcsx2.arguments(
            rom: rom, platformId: 8, settings: EmulatorSettings(), saveState: state, pcsx2: settings)

        #expect(arguments == ["-batch", "-statefile", state.path(percentEncoded: false), "--", "/Games/PS2/Okami (USA).iso"])
    }

    @Test func itsTwoDefaultMemoryCardsAreMadeAsFolderCardsUnlessACardIsThereAlready() throws {
        let cards = ludeum.pcsx2MemoryCards
        try FileManager.default.createDirectory(at: cards, withIntermediateDirectories: true)
        try Data(repeating: 0xFF, count: 16).write(to: cards.appending(path: "Mcd002.ps2"))

        try settings.writeStanding()

        var isDirectory: ObjCBool = false
        #expect(
            FileManager.default.fileExists(
                atPath: cards.appending(path: "Mcd001.ps2").path(percentEncoded: false), isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(
            FileManager.default.fileExists(
                atPath: cards.appending(path: "Mcd002.ps2").path(percentEncoded: false), isDirectory: &isDirectory))
        #expect(!isDirectory.boolValue)
    }

    @Test func itKnowsWhetherTheresABIOSToBootWith() throws {
        #expect(!settings.hasBIOS)
        try FileManager.default.createDirectory(at: ludeum.pcsx2BIOS, withIntermediateDirectories: true)
        try Data().write(to: ludeum.pcsx2BIOS.appending(path: ".DS_Store"))
        #expect(!settings.hasBIOS)
        try Data(repeating: 0, count: 64).write(to: ludeum.pcsx2BIOS.appending(path: "SCPH-39001.bin"))
        #expect(settings.hasBIOS)
    }

    @Test func itsRefusedWithoutTheDataFolder() throws {
        let elsewhere = LudeumFolder(url: root.appending(path: "Nowhere", directoryHint: .isDirectory))

        #expect(throws: DataFolderMissing.self) { try PCSX2Settings(ludeum: elsewhere).writeStanding() }
        #expect(!FileManager.default.fileExists(atPath: elsewhere.pcsx2Folder.path(percentEncoded: false)))
    }

    @Test func playIsRefusedUntilPCSX2IsInstalledAndHasABIOS() throws {
        let folder = try FakeROMFolder(in: root.appending(path: "ROMs", directoryHint: .isDirectory))
        try folder.add("Okami (USA).iso")
        let play = Play(platformId: 8, platformName: "PlayStation 2", roms: [folderROM("Okami (USA)")], settings: EmulatorSettings())
        let locator = ROMLocator(romFolders: [folder.folder])

        #expect(play.prepare(locator: locator, version: .ok, app: { _ in nil }, pcsx2: settings).refusal == .notInstalled(.pcsx2))

        let executable = ludeum.pcsx2App.appending(path: "Contents/MacOS/PCSX2")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
        #expect(
            play.prepare(locator: locator, version: .ok, app: { _ in nil }, pcsx2: settings, running: { _ in true }).refusal
                == .running(.pcsx2))
        #expect(
            play.prepare(locator: locator, version: .ok, app: { _ in nil }, pcsx2: settings).refusal
                == .noBIOS(ludeum.pcsx2BIOS.path(percentEncoded: false)))

        try FileManager.default.createDirectory(at: ludeum.pcsx2BIOS, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 64).write(to: ludeum.pcsx2BIOS.appending(path: "SCPH-39001.bin"))
        let outcome = play.prepare(locator: locator, version: .ok, app: { _ in nil }, pcsx2: settings)
        #expect(outcome.refusal == nil)
        #expect(outcome.arguments == ["-batch", "--", folder.url.appending(path: "Okami (USA).iso").path(percentEncoded: false)])
    }
}
