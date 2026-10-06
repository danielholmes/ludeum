import Foundation
import Testing

@testable import LudeumCore

/// A ROM as Game detail has it.
func folderROM(_ name: String, fileName: String? = nil, archived: Bool = false, missing: Bool = false, id: Int64 = 1) -> LudeumROM {
    LudeumROM(
        id: id, openEmuPk: nil, folderName: name, systemId: ROMFolder.ps2SystemId, fileName: fileName ?? "\(name).iso", name: name,
        version: "", disc: nil, missing: missing, archived: archived)
}

@Suite struct ROMLocatorTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "rom locator \(UUID().uuidString)")

    @Test func aFolderROMsReadyFileIsWhatPlayOpens() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let iso = try ps2.add("Okami (USA).iso")
        let locator = ROMLocator(openEmuLibrary: directory, romFolders: [ps2.folder])

        #expect(try locator.file(of: folderROM("Okami (USA)"), ready: true) == iso)
    }

    @Test func anArchivedROMHasNoFileToPlay() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let archive = try ps2.add("Okami (USA).7z")
        let locator = ROMLocator(openEmuLibrary: directory, romFolders: [ps2.folder])
        let rom = folderROM("Okami (USA)", fileName: "Okami (USA).7z", archived: true)

        #expect(try locator.file(of: rom, ready: true) == nil)
        #expect(try locator.file(of: rom) == archive)
    }

    @Test func aFolderROMsFilesAreNamedFromTheROMFolder() throws {
        let ps2 = try FakeROMFolder(in: directory)
        try ps2.add("Okami (USA)/Okami (USA).cue")
        try ps2.add("Okami (USA)/Okami (USA).bin", "12345")
        let locator = ROMLocator(openEmuLibrary: directory, romFolders: [ps2.folder])

        let files = locator.files(of: folderROM("Okami (USA)"))

        #expect(files.map(\.name) == ["Okami (USA)/Okami (USA).bin", "Okami (USA)/Okami (USA).cue"])
        #expect(files.first?.size == 5)
    }

    @Test func anOpenEmuROMIsFoundInOpenEmusLibrary() throws {
        let openEmu = try FakeOpenEmu(in: directory)
        let pk = try openEmu.addROM("Zelda", md5: "abc", fileName: "zelda.sfc")
        let locator = ROMLocator(openEmuLibrary: openEmu.folder, romFolders: [])
        let rom = LudeumROM(
            id: 1, openEmuPk: pk, folderName: nil, systemId: "openemu.system.snes", fileName: "zelda.sfc", name: "Zelda",
            version: "", disc: nil, missing: false, archived: false)

        #expect(try locator.file(of: rom, ready: true)?.lastPathComponent == "\(pk)-zelda.sfc")
        #expect(locator.files(of: rom).map(\.name) == ["\(pk)-zelda.sfc"])
    }

    @Test func aROMWithNoROMFolderSetIsNotFound() throws {
        let locator = ROMLocator(openEmuLibrary: directory, romFolders: [])

        #expect(try locator.file(of: folderROM("Okami (USA)"), ready: true) == nil)
        #expect(locator.files(of: folderROM("Okami (USA)")).isEmpty)
    }
}
