import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// A Platform's ROM folder in a temporary directory: PS2's unless another is given.
struct FakeROMFolder {
    let url: URL
    let platformId: Int64

    init(in directory: URL, platform: Int64 = ROMPlatform.ps2) throws {
        platformId = platform
        url = directory.appending(path: "Platform \(platform) \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    init(at url: URL, platform: Int64) throws {
        platformId = platform
        self.url = url
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    var folder: ROMFolder { .platform(platformId, url)! }

    @discardableResult
    func add(_ fileName: String, _ contents: String = "") throws -> URL {
        let file = url.appending(path: fileName)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func remove(_ fileName: String) throws { try FileManager.default.removeItem(at: url.appending(path: fileName)) }
}

@Suite struct ROMFolderScanTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "rom folder \(UUID().uuidString)")

    @Test func readyFilesArePlayableAndSevenZipsAreArchived() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let iso = try ps2.add("Sensible Soccer 2006 (Europe).iso")
        let archive = try ps2.add("Okami (USA).7z")

        #expect(
            try ps2.folder.scan() == [
                FolderROMFile(name: "Okami (USA)", ready: nil, archive: archive),
                FolderROMFile(name: "Sensible Soccer 2006 (Europe)", ready: iso, archive: nil),
            ])
    }

    @Test func msx2HasAROMFolderOfRomFilesThoughNoEmulatorYet() throws {
        let msx2 = try FakeROMFolder(in: directory, platform: 53)
        let rom = try msx2.add("Metal Gear (Europe).rom")

        #expect(try msx2.folder.scan() == [FolderROMFile(name: "Metal Gear (Europe)", ready: rom, archive: nil)])
        #expect(ROMPlatform.all[53]?.folderName == "MSX2")
        #expect(Emulator.of(platformId: 53) == nil)
    }

    @Test func vitaHasAROMFolderOfVpkFilesThoughNoEmulatorYet() throws {
        let vita = try FakeROMFolder(in: directory, platform: ROMPlatform.vita)
        let rom = try vita.add("Gravity Rush (USA).vpk")
        try vita.add("Persona 4 Golden (USA).zip")

        #expect(try vita.folder.scan() == [FolderROMFile(name: "Gravity Rush (USA)", ready: rom, archive: nil)])
        #expect(ROMPlatform.all[ROMPlatform.vita]?.folderName == "Vita")
        #expect(Emulator.of(platformId: ROMPlatform.vita) == nil)
    }

    @Test func otherFilesAndSubfoldersAreIgnored() throws {
        let ps2 = try FakeROMFolder(in: directory)
        try ps2.add(".DS_Store")
        try ps2.add("ICO.zip")
        try ps2.add("ICO.rar")
        try ps2.add("readme.txt")
        try ps2.add("Archive/Bully (USA).7z")

        #expect(try ps2.folder.scan().isEmpty)
    }

    @Test func anExtractedCopyBesideItsArchiveIsOneROMThatsPlayable() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let archive = try ps2.add("Okami (USA).7z")
        let iso = try ps2.add("Okami (USA).iso")

        #expect(try ps2.folder.scan() == [FolderROMFile(name: "Okami (USA)", ready: iso, archive: archive)])
    }

    @Test func aCueSheetsTracksArentROMsOfTheirOwn() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let cue = try ps2.add("Ape Escape 2 (USA).cue", "FILE \"Ape Escape 2 (USA) (Track 1).bin\" BINARY\n  TRACK 01 MODE2/2352\n")
        try ps2.add("Ape Escape 2 (USA) (Track 1).bin")

        #expect(try ps2.folder.scan() == [FolderROMFile(name: "Ape Escape 2 (USA)", ready: cue, archive: nil)])
    }

    @Test func aCueSheetsTracksMatchIgnoringCaseAndFolders() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let cue = try ps2.add("Ape Escape 2 (USA).cue", "FILE \"tracks\\APE ESCAPE 2 (USA).BIN\" BINARY\n")
        try ps2.add("Ape Escape 2 (USA).bin")

        #expect(try ps2.folder.scan() == [FolderROMFile(name: "Ape Escape 2 (USA)", ready: cue, archive: nil)])
    }

    @Test func aSubfolderHoldingOneImageIsAReadyROMNamedAfterTheFolder() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let bin = try ps2.add("ICO/ICO (USA).bin")
        try ps2.add("ICO/readme.html")
        try ps2.add("ICO.7z")

        #expect(try ps2.folder.scan() == [FolderROMFile(name: "ICO", ready: bin, archive: ps2.url.appending(path: "ICO.7z"))])
        #expect(try ps2.folder.scan().first?.fileName == "ICO/ICO (USA).bin")
    }

    @Test func aSubfolderWithACueSheetPlaysTheCueSheet() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let cue = try ps2.add("Ape Escape 2/Disc/Ape Escape 2.cue", "FILE \"Ape Escape 2 (Track 1).bin\" BINARY\n")
        try ps2.add("Ape Escape 2/Disc/Ape Escape 2 (Track 1).bin")

        #expect(try ps2.folder.scan() == [FolderROMFile(name: "Ape Escape 2", ready: cue, archive: nil)])
    }

    @Test func aSubfolderWithSeveralImagesAndNoCueSheetIsntAROM() throws {
        let ps2 = try FakeROMFolder(in: directory)
        try ps2.add("ICO/ICO.iso")
        try ps2.add("ICO/ICO (Demo).iso")
        try ps2.add(".ludeum-work/x/ICO.iso")

        #expect(try ps2.folder.scan().isEmpty)
    }

    @Test func wiisWiiWareWADsAndDiscImagesAreReadyForDolphin() throws {
        let wii = try FakeROMFolder(in: directory, platform: 5)
        let wad = try wii.add("World of Goo (USA) (WiiWare).wad")
        let disc = try wii.add("Wii Sports (USA).rvz")

        #expect(
            try wii.folder.scan() == [
                FolderROMFile(name: "Wii Sports (USA)", ready: disc, archive: nil),
                FolderROMFile(name: "World of Goo (USA) (WiiWare)", ready: wad, archive: nil),
            ])
        #expect(ROMPlatform.all[5]?.folderName == "Wii")
        #expect(Emulator.of(platformId: 5) == .dolphin)
    }

    @Test func oneROMLookedUpByNameIsWhatAScanFindsForIt() throws {
        let ps2 = try FakeROMFolder(in: directory)
        try ps2.add("Okami (USA).7z")
        let okami = try ps2.add("Okami (USA).iso")
        try ps2.add("ICO/ICO (USA).bin")
        try ps2.add("ICO.7z")
        try ps2.add("Ape Escape 2 (USA).cue", "FILE \"Ape Escape 2 (USA) (Track 1).bin\" BINARY\n")
        try ps2.add("Ape Escape 2 (USA) (Track 1).bin")
        try ps2.add("Bully (USA) v1.2.iso")
        try ps2.add("Demos/a.iso")
        try ps2.add("Demos/b.iso")
        try ps2.add("notes.txt")

        let scanned = try ps2.folder.scan()

        #expect(scanned.map(\.name) == ["Ape Escape 2 (USA)", "Bully (USA) v1.2", "ICO", "Okami (USA)"])
        for rom in scanned {
            let found = try ps2.folder.rom(named: rom.name)
            #expect(found == rom)
            #expect(found?.fileName == rom.fileName)
        }
        #expect(try ps2.folder.rom(named: "Okami (USA)")?.ready == okami)
        // A cue sheet's track, a folder that isn't a game, and nothing at all.
        #expect(try ps2.folder.rom(named: "Ape Escape 2 (USA) (Track 1)") == nil)
        #expect(try ps2.folder.rom(named: "Demos") == nil)
        #expect(try ps2.folder.rom(named: "Bully (USA) v1") == nil)
        #expect(try ps2.folder.rom(named: "Shadow of the Colossus (USA)") == nil)
    }

    @Test func aFolderThatIsntThereCantBeScanned() {
        let missing = ROMFolder.ps2(directory.appending(path: "nowhere", directoryHint: .isDirectory))

        #expect(throws: (any Error).self) { try missing.scan() }
    }
}

@Suite struct ROMFolderImportTests {
    let h: Harness
    let j: LudeumHarness
    let ps2: FakeROMFolder

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        ps2 = try FakeROMFolder(in: h.directory)
        h.internet.addPlatform(8, "PlayStation 2")
        h.internet.addGame(1234, "Okami", fields: ["platforms": [["id": 8, "name": "PlayStation 2"]]])
        h.internet.addSearch("Okami", platform: 8, results: [1234])
    }

    func importNow() async throws -> ImportResult {
        try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil).run(romFolders: [ps2.folder])
    }

    func rom(_ name: String) throws -> Row? {
        try j.journal.db.read { try Row.fetchOne($0, sql: "SELECT * FROM rom WHERE folderName = ?", arguments: [name]) }
    }

    /// Imports Okami's archive and confirms its suggestion, returning its Game.
    func okamiInTheJournal() async throws -> GameID {
        try ps2.add("Okami (USA).7z")
        _ = try await importNow()
        let item = try #require(try j.journal.reviewQueue().namesAgree.first)
        _ = try await ReviewQueue(journal: j.journal, igdb: h.igdb).confirm(item)
        return try #require(try rom("Okami (USA)")?["gameId"])
    }

    @Test func aNewFolderROMGoesToTheReviewQueueEvenWhenItsNameMatches() async throws {
        try ps2.add("Okami (USA).7z")

        let result = try await importNow()

        #expect(result.sentToReview.map(\.romName) == ["Okami (USA)"])
        let item = try #require(try j.journal.reviewQueue().namesAgree.first)
        #expect(item.suggestedIgdbGameId == 1234)
        #expect(item.platformId == ROMPlatform.ps2)
        #expect(try rom("Okami (USA)")?["archived"] as Bool? == true)
        #expect(try rom("Okami (USA)")?["missing"] as Bool? == false)
    }

    @Test func confirmingItPutsTheGameOnPS2() async throws {
        let game = try await okamiInTheJournal()

        #expect(try j.journal.game(game).platformId == 8)
    }

    @Test func extractingAnArchivedROMMakesItPlayableSilently() async throws {
        let game = try await okamiInTheJournal()
        try ps2.add("Okami (USA).iso")
        try ps2.remove("Okami (USA).7z")

        let result = try await importNow()

        #expect(!result.changedSomething)
        let roms = try j.journal.roms(of: game)
        #expect(roms.map(\.archived) == [false])
        #expect(roms.map(\.missing) == [false])
    }

    @Test func archivingItAgainIsTheSameROM() async throws {
        let game = try await okamiInTheJournal()
        try ps2.add("Okami (USA).iso")
        _ = try await importNow()
        try ps2.remove("Okami (USA).iso")
        try ps2.add("Okami (USA).7z")

        _ = try await importNow()

        #expect(try j.journal.roms(of: game).map(\.archived) == [true])
    }

    @Test func aFolderROMWhoseFilesAreAllGoneIsMissing() async throws {
        let game = try await okamiInTheJournal()
        try ps2.remove("Okami (USA).7z")

        let result = try await importNow()

        #expect(result.goneMissing.map(\.romName) == ["Okami (USA)"])
        #expect(try j.journal.roms(of: game).map(\.missing) == [true])
    }

    @Test func aMissingROMWhoseFileComesBackRejoinsItsGameSilently() async throws {
        let game = try await okamiInTheJournal()
        try ps2.remove("Okami (USA).7z")
        _ = try await importNow()
        try ps2.add("Okami (USA).iso")

        let result = try await importNow()

        #expect(!result.changedSomething)
        #expect(result.returned == [ImportedROM(romName: "Okami (USA)", game: game)])
        #expect(try j.journal.roms(of: game).map(\.missing) == [false])
    }

    @Test func nothingNewSaysNothing() async throws {
        _ = try await okamiInTheJournal()

        #expect(try await importNow() == ImportResult())
    }

    @Test func theLibraryMarksAGameWhoseROMsAreAllArchived() async throws {
        let game = try await okamiInTheJournal()
        func archived() throws -> Bool? {
            try j.journal.library(LibraryFilter(), sort: .name, ascending: true).first { $0.id == game }.map { $0.roms == .archived }
        }
        #expect(try archived() == true)

        try ps2.add("Okami (USA)/Okami.iso")
        try j.journal.checkROMsAgain(game, in: [ps2.folder])

        #expect(try archived() == false)
    }

    @Test func anArchivedROMIsPresentSoItsGameCantBeDeleted() async throws {
        let game = try await okamiInTheJournal()

        #expect(throws: LudeumError.gameHasCopies) { try j.journal.deleteGame(game) }
    }

    @Test func aFolderThatIsntThereLeavesItsROMsAlone() async throws {
        let game = try await okamiInTheJournal()
        try FileManager.default.removeItem(at: ps2.url)

        let result = try await importNow()

        #expect(!result.changedSomething)
        #expect(try j.journal.roms(of: game).map(\.missing) == [false])
    }

    @Test func aROMUnarchivedWhileTheImportRanStaysAsItWasCheckedThen() async throws {
        let game = try await okamiInTheJournal()
        let id: Int64 = try #require(try rom("Okami (USA)")?["id"])
        let ps2 = ps2
        let journal = j.journal

        // An Unarchive finishing after the Import read the ROM folder, which checks its ROM again.
        _ = try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: journal, backups: nil).run(romFolders: [ps2.folder]) {
            _ = try? ps2.add("Okami (USA).iso")
            try? ps2.remove("Okami (USA).7z")
            try? journal.checkROMAgain(id, in: ps2.folder)
        }

        let roms = try journal.roms(of: game)
        #expect(roms.map(\.archived) == [false])
        #expect(roms.map(\.fileName) == ["Okami (USA).iso"])
    }

    @Test func aROMThatWentMissingWhileTheImportRanStaysMissing() async throws {
        let game = try await okamiInTheJournal()
        let ps2 = ps2
        let journal = j.journal

        _ = try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: journal, backups: nil).run(romFolders: [ps2.folder]) {
            try? ps2.remove("Okami (USA).7z")
            try? journal.checkROMsAgain(game, in: [ps2.folder])
        }

        #expect(try journal.roms(of: game).map(\.missing) == [true])
    }

    @Test func checkingAGameAgainUpdatesOnlyItsROMs() async throws {
        let game = try await okamiInTheJournal()
        try ps2.add("Okami (USA).iso")
        try ps2.add("Shadow of the Colossus (USA).7z")

        try j.journal.checkROMsAgain(game, in: [ps2.folder])

        #expect(try j.journal.roms(of: game).map(\.archived) == [false])
        #expect(try rom("Shadow of the Colossus (USA)") == nil)
    }

    @Test func theFileAPlayOpensIsTheReadyOne() async throws {
        let game = try await okamiInTheJournal()
        #expect(try ps2.folder.readyFile(named: "Okami (USA)") == nil)
        let iso = try ps2.add("Okami (USA).iso")

        #expect(try ps2.folder.readyFile(named: "Okami (USA)") == iso)
        #expect(try j.journal.roms(of: game).first?.folderName == "Okami (USA)")
    }
}

@Suite struct ROMFilesTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "rom files \(UUID().uuidString)")

    @Test func aSingleFileROMIsJustThatFile() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let sfc = try ps2.add("Super Metroid (USA).sfc")

        #expect(ROMFiles.files(of: sfc) == [sfc])
    }

    @Test func aCueSheetBringsItsTracks() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let cue = try ps2.add("RE2.cue", "FILE \"RE2 (Track 1).bin\" BINARY\nFILE \"RE2 (Track 2).bin\" BINARY\n")
        let t1 = try ps2.add("RE2 (Track 1).bin")
        let t2 = try ps2.add("RE2 (Track 2).bin")

        #expect(ROMFiles.files(of: cue) == [cue, t1, t2])
    }

    @Test func aPlaylistBringsItsDiscsAndTheirTracks() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let m3u = try ps2.add("RE2.m3u", "RE2 (Disc 1).cue\nRE2 (Disc 2).cue\n")
        let d1 = try ps2.add("RE2 (Disc 1).cue", "FILE \"RE2 (Disc 1).bin\" BINARY\n")
        let b1 = try ps2.add("RE2 (Disc 1).bin")
        let d2 = try ps2.add("RE2 (Disc 2).cue", "FILE \"RE2 (Disc 2).bin\" BINARY\n")
        let b2 = try ps2.add("RE2 (Disc 2).bin")

        #expect(ROMFiles.files(of: m3u) == [m3u, d1, b1, d2, b2])
    }

    @Test func aReferencedFileThatIsntThereIsLeftOut() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let cue = try ps2.add("RE2.cue", "FILE \"RE2 (Track 1).bin\" BINARY\n")

        #expect(ROMFiles.files(of: cue) == [cue])
    }

    @Test func aROMFolderROMInASubfolderIsEverythingInIt() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let bin = try ps2.add("ICO/ICO (USA).bin")
        let readme = try ps2.add("ICO/docs/readme.html")

        #expect(try ps2.folder.files(named: "ICO") == [bin, readme])
    }

    @Test func aFolderOfTheROMsNameThatDoesntHoldTheGameIsntItsFiles() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let iso = try ps2.add("ICO.iso")
        try ps2.add("ICO/notes.txt")

        #expect(try ps2.folder.files(named: "ICO") == [iso])
    }

    @Test func anArchivedROMFolderROMIsItsArchive() throws {
        let ps2 = try FakeROMFolder(in: directory)
        let archive = try ps2.add("ICO.7z")

        #expect(try ps2.folder.files(named: "ICO") == [archive])
    }
}
