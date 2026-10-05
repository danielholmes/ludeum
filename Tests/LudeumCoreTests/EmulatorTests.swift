import Foundation
import Testing

@testable import LudeumCore

@Suite struct EmulatorTests {
    @Test func nesAndSNESGamesArePlayedInMesenCE() {
        for platform: Int64 in [18, 99, 19, 58, 33, 22, 24] { #expect(Emulator.of(platformId: platform) == .mesenCE) }
        #expect(Emulator.of(platformId: 7) == .duckStation)  // PlayStation
        #expect(Emulator.of(platformId: 21) == .dolphin)  // GameCube
        #expect(Emulator.of(platformId: 4) == nil)  // Nintendo 64
    }

    @Test func everyPlaySetsAllTheSettingsWithoutSavingThem() throws {
        let rom = URL(filePath: "/Games/roms/NES/Super Mario Bros. 3 (USA).nes")

        #expect(
            try Emulator.mesenCE.arguments(rom: rom, settings: EmulatorSettings())
                == ["--doNotSaveSettings", "--emulation.runAheadFrames=0", "/Games/roms/NES/Super Mario Bros. 3 (USA).nes"])
        #expect(
            try Emulator.mesenCE.arguments(rom: rom, settings: EmulatorSettings(runAheadFrames: 2))
                == ["--doNotSaveSettings", "--emulation.runAheadFrames=2", "/Games/roms/NES/Super Mario Bros. 3 (USA).nes"])
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
        try Emulator.dolphin.arguments(rom: rom, settings: EmulatorSettings())
            == [
                "-C", "Main.Core.RushFramePresentation=True", "-C", "Main.Core.SmoothEarlyPresentation=True", "-e",
                "/Games/GameCube/Pikmin (USA).rvz",
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
            rom: rom, settings: EmulatorSettings(runAheadFrames: 2), duckStation: DuckStationSettings(base: base, copy: copy))

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
