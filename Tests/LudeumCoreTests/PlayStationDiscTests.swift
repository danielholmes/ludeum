import Foundation
import Testing

@testable import LudeumCore

/// A PlayStation disc's Serial, as DuckStation names it from what its `SYSTEM.CNF` boots.
@Suite struct PlayStationDiscTests {
    func serial(_ disc: FakeDisc, _ sectors: FakeDisc.Sectors = .raw(mode: 2)) throws -> String? {
        let image = disc.image(sectors)
        return try PlayStationDisc.serial { range in image.subdata(in: range.clamped(to: 0..<image.count)) }
    }

    @Test func theSerialIsTheExecutableSYSTEMCNFBootsWithoutItsDotsAndWithADash() throws {
        #expect(try serial(.booting(#"cdrom:\SLUS_005.51;1"#, executable: "SLUS_005.51")) == "SLUS-00551")
    }

    @Test func itsReadFromRawSectorsOfEitherModeAndFromAnISO() throws {
        let disc = FakeDisc.booting(#"cdrom:\SCUS_949.00;1"#, executable: "SCUS_949.00")
        #expect(try serial(disc, .raw(mode: 1)) == "SCUS-94900")
        #expect(try serial(disc, .raw(mode: 2)) == "SCUS-94900")
        #expect(try serial(disc, .cooked) == "SCUS-94900")
    }

    @Test func theBootLineIsReadAsDuckStationReadsIt() {
        func executable(_ systemCNF: String) -> String { PlayStationDisc.executable(systemCNF: Data(systemCNF.utf8)) }
        // Resident Evil – Director's Cut has no backslash.
        #expect(executable("BOOT = cdrom:SLUS_005.51;1\r\n") == "SLUS_005.51")
        #expect(executable("BOOT=cdrom:\\\\SLES_012.34;1") == "SLES_012.34")
        #expect(executable("TCB = 4\nboot = cdrom:\\DATA\\GAME.EXE;1\n") == #"DATA\GAME.EXE"#)
        // Whitespace anywhere is dropped, and an unknown prefix kept.
        #expect(executable("BOOT = cdrom: \\ SLPS_000.01 ; 1") == "SLPS_000.01")
        #expect(executable("BOOT = CDROM:\\SLPS_000.01;1") == #"CDROM:\SLPS_000.01"#)
        // No BOOT line boots PSX.EXE.
        #expect(executable("TCB = 4\n") == "PSX.EXE")
    }

    @Test func theSerialIsTheExecutablesFileNameUpperCased() {
        #expect(PlayStationDisc.serial(booting: "slus_005.51") == "SLUS-00551")
        #expect(PlayStationDisc.serial(booting: #"DATA\GAME.EXE"#) == "GAMEEXE")
        #expect(PlayStationDisc.serial(booting: "MAIN.EXE") == "MAINEXE")
        // DuckStation names a disc booting PSX.EXE by a hash of it, which Ludeum doesn't work out.
        #expect(PlayStationDisc.serial(booting: "PSX.EXE") == nil)
    }

    @Test func anExecutableInASubdirectoryIsFound() throws {
        #expect(try serial(.booting(#"cdrom:\DATA\GAME.EXE;1"#, executable: #"DATA\GAME.EXE"#)) == "GAMEEXE")
    }

    @Test func aDiscWhoseExecutableIsntOnItHasNoSerial() throws {
        // DuckStation can't read the executable, so names the disc nothing.
        #expect(try serial(.booting(#"cdrom:\SLUS_005.51;1"#)) == nil)
        #expect(try serial(.booting(#"CDROM:\SLUS_005.51;1"#, executable: "SLUS_005.51")) == nil)
    }

    @Test func aDiscWithNoSYSTEMCNFOrBootingPSXEXEHasNoSerial() throws {
        #expect(try serial(FakeDisc(["PSX.EXE": "PS-X EXE"])) == nil)
        #expect(try serial(.booting(#"cdrom:\PSX.EXE;1"#, executable: "PSX.EXE")) == nil)
    }

    @Test func somethingThatIsntADataTrackHasNoSerial() throws {
        let noise = Data((0..<200_000).map { UInt8($0 % 251) })
        #expect(try PlayStationDisc.serial { noise.subdata(in: $0.clamped(to: 0..<noise.count)) } == nil)
    }

    @Test func readingPastWhatsBeenReadAsksForMore() throws {
        let image = FakeDisc.booting(#"cdrom:\SLUS_005.51;1"#, executable: "SLUS_005.51").image()
        let read = image.prefix(16 * 2352)
        #expect(throws: PlayStationDisc.NeedsMore.self) {
            try PlayStationDisc.serial { range in
                guard range.upperBound <= read.count else { throw PlayStationDisc.NeedsMore(range: range) }
                return read.subdata(in: range)
            }
        }
    }
}
