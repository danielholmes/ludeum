import Foundation
import Testing

@testable import LudeumCore

/// A ROM as Game detail has it.
func folderROM(_ name: String, fileName: String? = nil, archived: Bool = false, missing: Bool = false, id: Int64 = 1) -> LudeumROM {
    LudeumROM(
        id: id, folderName: name, platformId: ROMPlatform.ps2, fileName: fileName ?? "\(name).iso", name: name,
        version: "", disc: nil, missing: missing, archived: archived)
}

@Suite struct ROMLocatorTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "rom locator \(UUID().uuidString)")

    @Test func aFolderROMsReadyFileIsWhatPlayOpens() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let iso = try ps2.add("Okami (USA).iso")
        let locator = ROMLocator(romFolders: [ps2.folder])

        #expect(try locator.file(of: folderROM("Okami (USA)"), ready: true) == iso)
    }

    @Test func anArchivedROMHasNoFileToPlay() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let archive = try ps2.add("Okami (USA).7z")
        let locator = ROMLocator(romFolders: [ps2.folder])
        let rom = folderROM("Okami (USA)", fileName: "Okami (USA).7z", archived: true)

        #expect(try locator.file(of: rom, ready: true) == nil)
        #expect(try locator.file(of: rom) == archive)
    }

    @Test func aSubfolderROMsFilesAreNamedFromItsSubfolder() throws {
        let ps2 = try FakeROMFolder(in: directory)
        try ps2.add("Okami (USA)/Okami (USA).cue")
        try ps2.add("Okami (USA)/Okami (USA).bin", "12345")
        try ps2.add("Okami (USA)/Extras/readme.txt")
        let locator = ROMLocator(romFolders: [ps2.folder])

        let files = locator.files(of: folderROM("Okami (USA)", fileName: "Okami (USA)/Okami (USA).cue"))

        #expect(Set(files.map(\.name)) == ["Okami (USA).bin", "Okami (USA).cue", "Extras/readme.txt"])
        #expect(files.first { $0.name == "Okami (USA).bin" }?.size == 5)
    }

    @Test func aSubfolderROMsArchiveBesideItKeepsItsNameInTheROMFolder() throws {
        let ps2 = try FakeROMFolder(in: directory)
        try ps2.add("Okami (USA)/Okami (USA).iso")
        try ps2.add("Okami (USA).7z")
        let locator = ROMLocator(romFolders: [ps2.folder])

        let files = locator.files(of: folderROM("Okami (USA)", fileName: "Okami (USA)/Okami (USA).iso"))

        #expect(Set(files.map(\.name)) == ["Okami (USA).iso", "Okami (USA).7z"])
    }

    @Test func aSubfolderROMIsHeadedByItsSubfolderAndAFileROMByItsFile() {
        #expect(folderROM("Okami (USA)", fileName: "Okami (USA)/Okami (USA).cue").subfolder == "Okami (USA)")
        #expect(folderROM("Okami (USA)", fileName: "Okami (USA)/Disc 1/Okami (USA).cue").subfolder == "Okami (USA)")
        #expect(folderROM("Okami (USA)", fileName: "Okami (USA).iso").subfolder == nil)
        #expect(folderROM("Okami (USA)", fileName: "Okami (USA).7z", archived: true).subfolder == nil)
    }

    @Test func anArchivedOrCompactedROMsFileIsAnArchiveButAPlayableROMsImageIsNot() throws {
        let ps2 = try FakeROMFolder(in: directory)
        try ps2.add("ICO (USA).7z")
        let n64 = try FakeROMFolder(in: directory, platform: 4)
        try n64.add("Mario Kart 64 (USA).ZIP")
        try ps2.add("Okami (USA).iso")
        let locator = ROMLocator(romFolders: [ps2.folder, n64.folder])

        let archived = locator.files(of: folderROM("ICO (USA)", fileName: "ICO (USA).7z", archived: true))
        let compacted = locator.files(
            of: LudeumROM(
                id: 2, folderName: "Mario Kart 64 (USA)", platformId: 4, fileName: "Mario Kart 64 (USA).ZIP", name: "Mario Kart 64 (USA)",
                version: "", disc: nil, missing: false, archived: false))
        let loose = locator.files(of: folderROM("Okami (USA)"))

        #expect(archived.map(\.isArchive) == [true])
        #expect(compacted.map(\.isArchive) == [true])
        #expect(loose.map(\.isArchive) == [false])
    }

    @Test func aROMWithNoROMFolderSetIsNotFound() throws {
        let locator = ROMLocator(romFolders: [])

        #expect(try locator.file(of: folderROM("Okami (USA)"), ready: true) == nil)
        #expect(locator.files(of: folderROM("Okami (USA)")).isEmpty)
    }
}

@Suite struct ROMArchiveSavingTests {
    func file(_ name: String, _ size: Int64?) -> ROMFileInfo {
        ROMFileInfo(url: URL(filePath: "/ROMs/\(name)"), name: name, size: size, created: nil, modified: nil)
    }

    @Test func aROMsArchiveSavesWhatsInsideItLessItsOwnSize() {
        let saving = SevenZip.saving(
            files: [file("ICO.7z", 250)],
            contents: [
                URL(filePath: "/ROMs/ICO.7z"): [SevenZip.Entry(path: "ICO.bin", size: 600), SevenZip.Entry(path: "readme", size: 400)]
            ])

        #expect(saving == 0.75)
    }

    @Test func aROMWithALooseFileBesideItsArchiveHasNoSaving() {
        let saving = SevenZip.saving(
            files: [file("ICO/ICO.bin", 1000), file("ICO.7z", 250)],
            contents: [URL(filePath: "/ROMs/ICO.7z"): [SevenZip.Entry(path: "ICO.bin", size: 1000)]])

        #expect(saving == nil)
    }

    @Test func anArchiveNotListedYetOrWithNoSizeHasNoSaving() {
        let contents = [URL(filePath: "/ROMs/ICO.7z"): [SevenZip.Entry(path: "ICO.bin", size: 1000)]]

        #expect(SevenZip.saving(files: [file("Okami.7z", 250)], contents: contents) == nil)
        #expect(SevenZip.saving(files: [file("ICO.7z", nil)], contents: contents) == nil)
        #expect(SevenZip.saving(files: [], contents: contents) == nil)
    }
}
