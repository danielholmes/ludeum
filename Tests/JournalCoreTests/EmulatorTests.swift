import Foundation
import Testing

@testable import JournalCore

@Suite struct EmulatorTests {
    @Test func nesAndFamicomGamesArePlayedInMesenCE() {
        #expect(Emulator.of(platformId: 18) == .mesenCE)
        #expect(Emulator.of(platformId: 99) == .mesenCE)
        #expect(Emulator.of(platformId: 19) == nil)
    }

    @Test func everyPlaySetsAllTheSettingsWithoutSavingThem() {
        let rom = URL(filePath: "/Games/roms/NES/Super Mario Bros. 3 (USA).nes")

        #expect(
            Emulator.mesenCE.arguments(rom: rom, settings: EmulatorSettings())
                == ["--doNotSaveSettings", "--emulation.runAheadFrames=0", "/Games/roms/NES/Super Mario Bros. 3 (USA).nes"])
        #expect(
            Emulator.mesenCE.arguments(rom: rom, settings: EmulatorSettings(runAheadFrames: 2))
                == ["--doNotSaveSettings", "--emulation.runAheadFrames=2", "/Games/roms/NES/Super Mario Bros. 3 (USA).nes"])
    }

    @Test func aGamesSettingsAreKeptAndCanBeClearedBackToTheDefault() throws {
        let h = try JournalHarness()
        let game = try h.addGame("Super Mario Bros. 3")
        #expect(try h.journal.emulatorSettings(game) == EmulatorSettings())

        try h.journal.setEmulatorSettings(game, EmulatorSettings(runAheadFrames: 1))
        try h.reopen()
        #expect(try h.journal.emulatorSettings(game) == EmulatorSettings(runAheadFrames: 1))

        try h.journal.setEmulatorSettings(game, EmulatorSettings())
        #expect(try h.journal.emulatorSettings(game).runAheadFrames == nil)
    }

    @Test func runAheadIsZeroToTenFrames() throws {
        let h = try JournalHarness()
        let game = try h.addGame("Super Mario Bros. 3")

        #expect(throws: JournalError.runAheadOutOfRange) { try h.journal.setEmulatorSettings(game, EmulatorSettings(runAheadFrames: 11)) }
        #expect(throws: JournalError.runAheadOutOfRange) { try h.journal.setEmulatorSettings(game, EmulatorSettings(runAheadFrames: -1)) }
        try h.journal.setEmulatorSettings(game, EmulatorSettings(runAheadFrames: 10))
    }
}
