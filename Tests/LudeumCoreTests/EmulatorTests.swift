import Foundation
import Testing

@testable import LudeumCore

@Suite struct EmulatorTests {
    @Test func nesAndSNESGamesArePlayedInMesenCE() {
        for platform: Int64 in [18, 99, 19, 58, 33, 22, 24, 64] { #expect(Emulator.of(platformId: platform) == .mesenCE) }
        #expect(Emulator.of(platformId: 7) == .duckStation)  // PlayStation
        #expect(Emulator.of(platformId: 21) == .dolphin)  // GameCube
        #expect(Emulator.of(platformId: 29) == .ares)  // Mega Drive/Genesis
        #expect(Emulator.of(platformId: 4) == .ares)  // Nintendo 64
        #expect(Emulator.of(platformId: 20) == .melonDS)  // Nintendo DS
        #expect(Emulator.of(platformId: 78) == .ares)  // Sega CD
        #expect(Emulator.of(platformId: 32) == nil)  // Saturn
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

@Test func melonDSJustOpensTheGame() throws {
    let rom = URL(filePath: "/Games/DS/Advance Wars - Dual Strike (USA).nds")
    #expect(
        try Emulator.melonDS.arguments(rom: rom, platformId: 20, settings: EmulatorSettings()) == [
            "/Games/DS/Advance Wars - Dual Strike (USA).nds"
        ])
}

@Suite struct DuckStationSettingsTests {
    let folder = FileManager.default.temporaryDirectory.appending(
        path: "duckstation tests \(UUID().uuidString)", directoryHint: .isDirectory)

    @Test func aPlayStartsFromACopyOfDuckStationsOwnSettingsWithTheGamesRunAhead() throws {
        let base = folder.appending(path: "settings.ini")
        let copy = folder.appending(path: "copy.ini")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "[Main]\nRewindEnable = false\nRunaheadFrameCount = 0\n\n[Pad1]\nUp = Keyboard/Up\n".write(
            to: base, atomically: true, encoding: .utf8)
        let rom = URL(filePath: "/Games/PSX/Parasite Eve II (USA).m3u")

        let arguments = try Emulator.duckStation.arguments(
            rom: rom, platformId: 7, settings: EmulatorSettings(runAheadFrames: 2), duckStation: DuckStationSettings(base: base, copy: copy)
        )

        #expect(arguments == ["-settings", copy.path(percentEncoded: false), "/Games/PSX/Parasite Eve II (USA).m3u"])
        #expect(
            try String(contentsOf: copy, encoding: .utf8)
                == "[Main]\nRewindEnable = false\nRunaheadFrameCount = 2\n\n[Pad1]\nUp = Keyboard/Up\n")
        #expect(try String(contentsOf: base, encoding: .utf8).contains("RunaheadFrameCount = 0"))
    }

    @Test func runAheadIsAddedWhenDuckStationsSettingsDontHaveIt() {
        #expect(DuckStationSettings.applying(EmulatorSettings(), to: "[Main]\nA = 1\n") == "[Main]\nRunaheadFrameCount = 0\nA = 1\n")
        #expect(DuckStationSettings.applying(EmulatorSettings(runAheadFrames: 1), to: "") == "[Main]\nRunaheadFrameCount = 1\n\n")
        // Only [Main]'s setting counts.
        #expect(
            DuckStationSettings.applying(EmulatorSettings(runAheadFrames: 3), to: "[Other]\nRunaheadFrameCount = 9\n[Main]\n")
                == "[Other]\nRunaheadFrameCount = 9\n[Main]\nRunaheadFrameCount = 3\n")
    }
}
