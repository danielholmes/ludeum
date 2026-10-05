import Testing

@testable import LudeumCore

@Suite struct VersionsTests {
    func rom(_ id: Int, _ name: String, playlist: Bool = false, present: Bool = true) -> GameROM {
        GameROM(id: id, name: name, isPlaylist: playlist, isPresent: present)
    }

    func ids(_ versions: [[GameROM]]) -> [[Int]] { versions.map { $0.map(\.id) } }

    @Test func oneROMIsOneVersion() {
        #expect(ids(versions(of: [rom(1, "Super Metroid (Japan, USA) (En,Ja)")])) == [[1]])
        #expect(!hasDuplicateVersions([rom(1, "Super Metroid (Japan, USA) (En,Ja)")]))
    }

    @Test func twoROMsAreDuplicateVersions() {
        let roms = [rom(1, "Double Dragon III (Japan)"), rom(2, "Double Dragon III (USA)")]
        #expect(ids(versions(of: roms)) == [[1], [2]])
        #expect(hasDuplicateVersions(roms))
    }

    @Test func missingROMsNeverCount() {
        #expect(!hasDuplicateVersions([rom(1, "Double Dragon III (Japan)", present: false), rom(2, "Double Dragon III (USA)")]))
    }

    @Test func discsWithDistinctNumbersAreOneVersionWithTheirPlaylist() {
        let roms = [
            rom(1, "Gran Turismo 2 (USA) (Disc 1) (Arcade Mode)"),
            rom(2, "Gran Turismo 2 (USA) (Disc 2) (Simulation Mode) (Rev 1)"),
            rom(3, "Gran Turismo 2", playlist: true),
        ]
        #expect(ids(versions(of: roms)) == [[1, 2, 3]])
        #expect(!hasDuplicateVersions(roms))
    }

    @Test func aRepeatedDiscNumberIsNotOneSetOfDiscs() {
        let roms = [rom(1, "Final Fantasy VII (USA) (Disc 1)"), rom(2, "Final Fantasy VII (Europe) (Disc 1)")]
        #expect(hasDuplicateVersions(roms))
    }

    @Test func aDisclessROMNextToDiscsIsAnotherVersion() {
        let roms = [
            rom(1, "Resident Evil 2 (USA) (Disc 1) (Leon)"), rom(2, "Resident Evil 2 (USA) (Disc 2) (Claire)"),
            rom(3, "Resident Evil 2 (USA)"),
        ]
        #expect(ids(versions(of: roms)) == [[1, 2], [3]])
    }
}
