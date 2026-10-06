import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// A ROM kept in both forms at once: a scan sees every form its name has, not just the file a Play opens.
@Suite struct BothFormsScanTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "both forms \(UUID().uuidString)")

    @Test func aLooseFileBesideItsZipOnAnAresPlatformIsInBothForms() throws {
        let n64 = try FakeROMFolder(in: directory, platform: 4)
        let zip = try n64.add("Super Mario 64 (USA).zip")
        let z64 = try n64.add("Super Mario 64 (USA).z64")

        let rom = try #require(try n64.folder.scan().first)

        #expect(rom == FolderROMFile(name: "Super Mario 64 (USA)", ready: z64, archive: nil, otherForms: [zip]))
        #expect(rom.inBothForms)
    }

    @Test func aPlayableCopyBesideItsArchiveIsInBothForms() throws {
        let ps2 = try FakeROMFolder(in: directory)
        try ps2.add("Okami (USA)/Okami (USA).iso")
        try ps2.add("Okami (USA).7z")
        let megaDrive = try FakeROMFolder(in: directory, platform: 29)
        try megaDrive.add("Sonic (USA).md")
        try megaDrive.add("Sonic (USA).7z")

        #expect(try ps2.folder.scan().map(\.inBothForms) == [true])
        #expect(try megaDrive.folder.scan().map(\.inBothForms) == [true])
    }

    @Test func aLooseFileBesideItsCompacted7zIsInBothForms() throws {
        let snes = try FakeROMFolder(in: directory, platform: 19)
        let archive = try snes.add("Zelda (USA).7z")
        let sfc = try snes.add("Zelda (USA).sfc")

        let rom = try #require(try snes.folder.scan().first)

        #expect(rom == FolderROMFile(name: "Zelda (USA)", ready: sfc, archive: archive))
        #expect(rom.inBothForms)
    }

    @Test func aROMInOneFormIsnt() throws {
        let snes = try FakeROMFolder(in: directory, platform: 19)
        try snes.add("Zelda (USA).7z")
        try snes.add("Super Metroid (USA).sfc")
        let ps1 = try FakeROMFolder(in: directory, platform: 7)
        try ps1.add("Ridge Racer (USA).cue", #"FILE "Ridge Racer (USA).bin" BINARY"#)
        try ps1.add("Ridge Racer (USA).bin")
        try ps1.add("Wipeout (USA).7z")

        #expect(try snes.folder.scan().map(\.inBothForms) == [false, false])
        #expect(try ps1.folder.scan().map(\.inBothForms) == [false, false])
    }
}

/// Which copy of a ROM kept in both forms is kept, and what goes to the Trash.
@Suite struct BothFormsKeepTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "both forms keep \(UUID().uuidString)")

    @Test func aPlayableCopyIsKeptOverItsArchived7z() throws {
        let ps2 = try FakeROMFolder(in: directory)
        try ps2.add("Okami (USA)/Okami (USA).iso")
        let okami = try ps2.add("Okami (USA).7z")
        let psp = try FakeROMFolder(in: directory, platform: ROMPlatform.psp)
        let iso = try psp.add("Lumines (USA).iso")
        let lumines = try psp.add("Lumines (USA).7z")
        let megaDrive = try FakeROMFolder(in: directory, platform: 29)
        let md = try megaDrive.add("Sonic (USA).md")
        let sonic = try megaDrive.add("Sonic (USA).7z")

        #expect(
            try ps2.folder.bothForms(named: "Okami (USA)")
                == BothForms(
                    keep: ps2.url.appending(path: "Okami (USA)", directoryHint: .isDirectory), keepsCompacted: false, trash: [okami]))
        #expect(try psp.folder.bothForms(named: "Lumines (USA)") == BothForms(keep: iso, keepsCompacted: false, trash: [lumines]))
        #expect(try megaDrive.folder.bothForms(named: "Sonic (USA)") == BothForms(keep: md, keepsCompacted: false, trash: [sonic]))
    }

    @Test func theCompactedCopyIsKeptOverTheLooseFile() throws {
        let snes = try FakeROMFolder(in: directory, platform: 19)
        let archive = try snes.add("Zelda (USA).7z")
        let sfc = try snes.add("Zelda (USA).sfc")
        let n64 = try FakeROMFolder(in: directory, platform: 4)
        let zip = try n64.add("Super Mario 64 (USA).zip")
        let z64 = try n64.add("Super Mario 64 (USA).z64")

        #expect(try snes.folder.bothForms(named: "Zelda (USA)") == BothForms(keep: archive, keepsCompacted: true, trash: [sfc]))
        #expect(try n64.folder.bothForms(named: "Super Mario 64 (USA)") == BothForms(keep: zip, keepsCompacted: true, trash: [z64]))
    }

    @Test func everyOtherCopyGoesWhenThereAreMoreThanTwo() throws {
        let n64 = try FakeROMFolder(in: directory, platform: 4)
        let zip = try n64.add("Super Mario 64 (USA).zip")
        let z64 = try n64.add("Super Mario 64 (USA).z64")
        let archive = try n64.add("Super Mario 64 (USA).7z")

        #expect(
            try n64.folder.bothForms(named: "Super Mario 64 (USA)") == BothForms(keep: zip, keepsCompacted: true, trash: [z64, archive]))
    }

    @Test func aLooseCueSheetGoesWithItsTracks() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: 7)
        try ps1.add("Ridge Racer (USA)/Ridge Racer (USA).chd")
        let cue = try ps1.add("Ridge Racer (USA).cue", #"FILE "Ridge Racer (USA).bin" BINARY"#)
        let bin = try ps1.add("Ridge Racer (USA).bin")

        #expect(
            try ps1.folder.bothForms(named: "Ridge Racer (USA)")
                == BothForms(
                    keep: ps1.url.appending(path: "Ridge Racer (USA)", directoryHint: .isDirectory), keepsCompacted: false,
                    trash: [cue, bin]))
    }

    @Test func aROMInOneFormHasNothingToKeepOrTrash() throws {
        let snes = try FakeROMFolder(in: directory, platform: 19)
        try snes.add("Zelda (USA).7z")

        #expect(try snes.folder.bothForms(named: "Zelda (USA)") == nil)
        #expect(try snes.folder.bothForms(named: "Super Metroid (USA)") == nil)
    }
}

@Suite struct BothFormsReviewTests {
    let h: Harness
    let j: LudeumHarness
    let snes: FakeROMFolder
    let ps2: FakeROMFolder
    let trash: URL

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        snes = try FakeROMFolder(in: h.directory, platform: 19)
        ps2 = try FakeROMFolder(in: h.directory)
        trash = h.directory.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        h.internet.addPlatform(19, "Super Nintendo Entertainment System")
        h.internet.addPlatform(8, "PlayStation 2")
    }

    var romFolders: [ROMFolder] { [snes.folder, ps2.folder] }

    func importNow() async throws {
        _ = try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil).run(romFolders: romFolders)
    }

    func bothForms() throws -> [BothFormsROM] { try j.journal.reviewQueue().bothForms }

    func rom(_ name: String) throws -> Row {
        try j.journal.db.read { try Row.fetchOne($0, sql: "SELECT * FROM rom WHERE folderName = ?", arguments: [name])! }
    }

    /// Keeps one copy as its ROM folder has it now, the Trash being a folder the test can look in.
    func keepOne(_ item: BothFormsROM, as forms: BothForms) throws {
        let trash = trash
        try j.journal.keepOneForm(item, as: forms, romFolders: romFolders) {
            try FileManager.default.moveItem(at: $0, to: trash.appending(path: $0.lastPathComponent))
        }
    }

    func trashed() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: trash.path(percentEncoded: false)).sorted() }

    @Test func everyROMKeptInBothFormsWaitsInTheReviewQueue() async throws {
        try snes.add("Zelda (USA).sfc")
        try snes.add("Zelda (USA).7z")
        try snes.add("Super Metroid (USA).7z")
        try ps2.add("Okami (USA)/Okami (USA).iso")
        try ps2.add("Okami (USA).7z")
        try ps2.add("Ico (USA).7z")

        try await importNow()

        let queue = try j.journal.reviewQueue()
        #expect(queue.bothForms.map(\.rom.folderName) == ["Okami (USA)", "Zelda (USA)"])
        #expect(queue.bothForms.map(\.rom.fileName) == ["Okami (USA)/Okami (USA).iso", "Zelda (USA).sfc"])
        #expect(queue.bothForms.map(\.game) == [nil, nil])
        #expect(queue.count == queue.noSuggestion.count + queue.notCompacted.count + 2)
    }

    @Test func aCopyRemovedByHandClearsTheItemOnTheNextImport() async throws {
        try ps2.add("Okami (USA)/Okami (USA).iso")
        try ps2.add("Okami (USA).7z")
        try await importNow()
        #expect(try bothForms().count == 1)

        try ps2.remove("Okami (USA).7z")
        try await importNow()

        #expect(try bothForms().isEmpty)
    }

    @Test func aSecondCopyOfAKnownROMPutsItInTheQueueOnTheNextImport() async throws {
        try snes.add("Zelda (USA).7z")
        try await importNow()
        #expect(try bothForms().isEmpty)

        try snes.add("Zelda (USA).sfc")
        try await importNow()

        #expect(try bothForms().map(\.rom.folderName) == ["Zelda (USA)"])
    }

    @Test func keepingTheCompactedCopyTrashesTheLooseFileAndTheItemLeavesTheQueue() async throws {
        try snes.add("Zelda (USA).sfc")
        try snes.add("Zelda (USA).7z")
        try await importNow()
        let item = try #require(try bothForms().first)
        let forms = try #require(try snes.folder.bothForms(named: "Zelda (USA)"))

        try keepOne(item, as: forms)

        #expect(try trashed() == ["Zelda (USA).sfc"])
        #expect(try snes.folder.scan().map(\.fileName) == ["Zelda (USA).7z"])
        #expect(try rom("Zelda (USA)")["fileName"] as String == "Zelda (USA).7z")
        let queue = try j.journal.reviewQueue()
        #expect(queue.bothForms.isEmpty)
        #expect(queue.notCompacted.isEmpty)
    }

    @Test func keepingThePlayableCopyTrashesItsArchive() async throws {
        try ps2.add("Okami (USA)/Okami (USA).iso")
        try ps2.add("Okami (USA).7z")
        try await importNow()
        let item = try #require(try bothForms().first)
        let forms = try #require(try ps2.folder.bothForms(named: "Okami (USA)"))

        try keepOne(item, as: forms)

        #expect(try trashed() == ["Okami (USA).7z"])
        #expect(try ps2.folder.scan().map(\.fileName) == ["Okami (USA)/Okami (USA).iso"])
        #expect(try rom("Okami (USA)")["archived"] as Bool == false)
        #expect(try bothForms().isEmpty)
    }

    @Test func itsRefusedWithNothingTrashedWhenTheCopiesHaveChangedSinceTheyWereShown() async throws {
        let n64 = try FakeROMFolder(in: h.directory, platform: 4)
        try n64.add("Super Mario 64 (USA).z64")
        try n64.add("Super Mario 64 (USA).7z")
        _ = try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil).run(romFolders: [n64.folder])
        let item = try #require(try bothForms().first)
        let forms = try #require(try n64.folder.bothForms(named: "Super Mario 64 (USA)"))
        try n64.add("Super Mario 64 (USA).zip")
        let trash = trash

        #expect(throws: ReviewError.bothFormsChanged) {
            try j.journal.keepOneForm(item, as: forms, romFolders: [n64.folder]) {
                try FileManager.default.moveItem(at: $0, to: trash.appending(path: $0.lastPathComponent))
            }
        }

        #expect(try trashed().isEmpty)
        #expect(try bothForms().count == 1)
    }

    @Test func aROMNoLongerInBothFormsIsRefusedAndLeavesTheQueue() async throws {
        try ps2.add("Okami (USA)/Okami (USA).iso")
        try ps2.add("Okami (USA).7z")
        try await importNow()
        let item = try #require(try bothForms().first)
        let forms = try #require(try ps2.folder.bothForms(named: "Okami (USA)"))
        try ps2.remove("Okami (USA)")

        #expect(throws: ReviewError.bothFormsChanged) { try keepOne(item, as: forms) }

        #expect(try trashed().isEmpty)
        #expect(try bothForms().isEmpty)
        #expect(try rom("Okami (USA)")["archived"] as Bool == true)
    }
}
