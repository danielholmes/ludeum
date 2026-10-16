import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// Stray files (ADR 0017): the journal says which ROMs there are, so an Import never makes a ROM of a file it doesn't
/// have. It lists the file in the Review queue instead, until it's Added as a ROM or leaves its ROM folder.
@Suite struct StrayFileTests {
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

    @discardableResult
    func importNow(adding: Set<StrayFile.Key> = [], folders: [ROMFolder]? = nil) async throws -> ImportResult {
        try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil)
            .run(romFolders: folders ?? [ps2.folder], adding: adding)
    }

    func romCount() throws -> Int { try j.journal.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM rom") ?? 0 } }

    func strays() throws -> [StrayFile] { try j.journal.reviewQueue().strayFiles }

    let okami = StrayFile.Key(platformId: ROMPlatform.ps2, name: "Okami (USA)")

    @Test func aFileTheJournalDoesntHaveIsAStrayFileNotAROM() async throws {
        try ps2.add("Okami (USA).7z")

        let result = try await importNow()

        #expect(try romCount() == 0)
        #expect(result.sentToReview.isEmpty)
        #expect(result.strayFiles == ["Okami (USA)"])
        #expect(result.changedSomething)
        #expect(try strays().map(\.key) == [okami])
        #expect(try strays().map(\.fileName) == ["Okami (USA).7z"])
        #expect(try j.journal.reviewQueue().count == 1)
    }

    @Test func aStrayFileIsReportedOnlyWhenItFirstTurnsUp() async throws {
        try ps2.add("Okami (USA).7z")
        try await importNow()

        let result = try await importNow()

        #expect(result == ImportResult())
        #expect(try strays().map(\.name) == ["Okami (USA)"])
    }

    @Test func aStrayFileThatLeavesItsROMFolderLeavesTheReviewQueue() async throws {
        try ps2.add("Okami (USA).7z")
        try await importNow()
        try ps2.remove("Okami (USA).7z")

        try await importNow()

        #expect(try strays().isEmpty)
    }

    @Test func aStrayFileKeepsUpWithItsFile() async throws {
        try ps2.add("Okami (USA).7z")
        try await importNow()
        try ps2.remove("Okami (USA).7z")
        try ps2.add("Okami (USA)/Okami (USA).iso")

        try await importNow()

        #expect(try strays().map(\.fileName) == ["Okami (USA)/Okami (USA).iso"])
    }

    @Test func addingAStrayFileMakesItANewROMMatchedAsAnyOtherIs() async throws {
        try ps2.add("Okami (USA).7z")
        try ps2.add("Kuon (USA).7z")
        try await importNow()

        let result = try await importNow(adding: [okami])

        #expect(result.sentToReview.map(\.romName) == ["Okami (USA)"])
        #expect(try j.journal.reviewQueue().unmatched.first?.suggestedIgdbGameId == 1234)
        #expect(try romCount() == 1)
        #expect(try strays().map(\.name) == ["Kuon (USA)"])
    }

    @Test func addingSeveralStrayFilesMakesEachOneAROMAndNoOtherFile() async throws {
        try ps2.add("Okami (USA).7z")
        try ps2.add("Kuon (USA).7z")
        try await importNow()
        let listed = Set(try strays().map(\.key))
        // Turned up after the list was shown, so it isn't among those added.
        try ps2.add("Rule of Rose (USA).7z")

        let result = try await importNow(adding: listed)

        #expect(Set(result.sentToReview.map(\.romName)) == ["Okami (USA)", "Kuon (USA)"])
        #expect(result.strayFiles == ["Rule of Rose (USA)"])
        #expect(try romCount() == 2)
        #expect(try strays().map(\.name) == ["Rule of Rose (USA)"])
    }

    @Test func aFileThatIsAnotherFormOfAKnownROMIsntStray() async throws {
        try ps2.add("Okami (USA).7z")
        try await importNow(adding: [okami])
        try ps2.remove("Okami (USA).7z")
        try ps2.add("Okami (USA).iso")

        let result = try await importNow()

        #expect(result.strayFiles.isEmpty)
        #expect(try strays().isEmpty)
        #expect(try romCount() == 1)
    }

    @Test func aFolderThatCantBeReadLeavesItsStrayFilesAlone() async throws {
        try ps2.add("Okami (USA).7z")
        try await importNow()
        try FileManager.default.removeItem(at: ps2.url)

        try await importNow()

        #expect(try strays().map(\.name) == ["Okami (USA)"])
    }

    @Test func eachROMFolderKeepsItsOwnStrayFiles() async throws {
        let gameBoy = try FakeROMFolder(in: h.directory, platform: 33)
        try ps2.add("Okami (USA).7z")
        try gameBoy.add("Tetris (World).7z")
        try await importNow(folders: [ps2.folder, gameBoy.folder])

        try await importNow(folders: [gameBoy.folder])

        #expect(try strays().map(\.name) == ["Okami (USA)", "Tetris (World)"])
    }

    @Test func aStrayFileRecordedAsAROMWhileTheImportRanIsntStray() async throws {
        try ps2.add("Okami (USA).7z")
        let file = try #require(try ps2.folder.scan().first)
        _ = try j.journal.recordAddedROM(
            file, checksum: nil, on: ROMPlatform.ps2, reusing: nil, regions: [], match: .byHand(name: "Okami"))
        var plan = ImportPlan()
        plan.strayFiles = [ROMPlatform.ps2: [file]]

        let result = try j.journal.applyImport(plan)

        #expect(result.strayFiles.isEmpty)
        #expect(try strays().isEmpty)
    }

    @Test func recordingAROMTakesItsNameOutOfTheStrayFiles() async throws {
        try ps2.add("Okami (USA).7z")
        try await importNow()
        let file = try #require(try ps2.folder.scan().first)

        _ = try j.journal.recordAddedROM(
            file, checksum: nil, on: ROMPlatform.ps2, reusing: nil, regions: [], match: .byHand(name: "Okami"))

        #expect(try strays().isEmpty)
    }

    /// Okami, Matched by hand, then renamed in Finder: once Imported, a missing ROM and a Stray file by its new name.
    func renamedOkami() async throws -> (rom: Int64, game: GameID, stray: StrayFile) {
        try ps2.add("Okami (USA).7z")
        let added = try j.journal.recordAddedROM(
            #require(try ps2.folder.rom(named: "Okami (USA)")), checksum: .md5("old"), on: ROMPlatform.ps2, reusing: nil,
            regions: ["USA"], match: .byHand(name: "Okami"))
        try ps2.remove("Okami (USA).7z")
        try ps2.add("Okami (USA) (Rev 1).7z")
        try await importNow()
        return (added.rom, added.game, try #require(try strays().first))
    }

    func rom(_ id: Int64) throws -> Row? {
        try j.journal.db.read { try Row.fetchOne($0, sql: "SELECT * FROM rom WHERE id = ?", arguments: [id]) }
    }

    @Test func aMissingROMCanTakeAStrayFileAsItsOwn() async throws {
        let okami = try await renamedOkami()
        try await j.journal.db.write { try $0.execute(sql: "UPDATE rom SET libretroLookedUp = 1") }

        try j.journal.giveStrayFile(okami.stray, to: okami.rom, in: ps2.folder)

        let row = try #require(try rom(okami.rom))
        // Looked up again by its new name.
        #expect(row["libretroLookedUp"] as Bool == false)
        #expect(row["folderName"] as String == "Okami (USA) (Rev 1)")
        #expect(row["fileName"] as String == "Okami (USA) (Rev 1).7z")
        #expect(row["missing"] as Bool == false)
        #expect(row["gameId"] as GameID? == okami.game)
        #expect(row["regions"] as String? == Regions.encode(["USA"]))
        // Its old file's checksum isn't this one's.
        #expect(row["md5"] as String? == nil)
        #expect(try strays().isEmpty)
        #expect(try romCount() == 1)
        #expect(try await importNow() == ImportResult())
    }

    @Test func aROMRenamedOnlyInCaseCanBeGivenItsFileBack() async throws {
        try ps2.add("Okami (USA).7z")
        let added = try j.journal.recordAddedROM(
            #require(try ps2.folder.rom(named: "Okami (USA)")), checksum: nil, on: ROMPlatform.ps2, reusing: nil, regions: [],
            match: .byHand(name: "Okami"))
        try ps2.remove("Okami (USA).7z")
        try ps2.add("okami (usa).7z")
        try await importNow()
        let stray = try #require(try strays().first)

        try j.journal.giveStrayFile(stray, to: added.rom, in: ps2.folder)

        #expect(try rom(added.rom)?["folderName"] as String? == "okami (usa)")
    }

    @Test func aStrayFileCanOnlyBeGivenToAMissingROM() async throws {
        let okami = try await renamedOkami()
        try ps2.add("Okami (USA).7z")
        try await importNow()

        #expect(throws: ReviewError.notMissing) { try j.journal.giveStrayFile(okami.stray, to: okami.rom, in: ps2.folder) }
        #expect(try rom(okami.rom)?["folderName"] as String? == "Okami (USA)")
    }

    @Test func aStrayFileGoneFromItsFolderCantBeGivenToAMissingROM() async throws {
        let okami = try await renamedOkami()
        try ps2.remove("Okami (USA) (Rev 1).7z")

        #expect(throws: ReviewError.strayFileGone) { try j.journal.giveStrayFile(okami.stray, to: okami.rom, in: ps2.folder) }
        #expect(try rom(okami.rom)?["folderName"] as String? == "Okami (USA)")
    }

    @Test func aStrayFileListsTheMissingROMsOfItsPlatformLikeliestFirst() async throws {
        let gameBoy = try FakeROMFolder(in: h.directory, platform: 33)
        let names = ["Kuon (USA)", "Okami (USA)", "Rule of Rose (USA)", "Okami (Japan)"]
        for name in names { try ps2.add("\(name).7z") }
        try gameBoy.add("Okami (USA).7z")
        let folders = [ps2.folder, gameBoy.folder]
        try await importNow(
            adding: Set(
                names.map { StrayFile.Key(platformId: ROMPlatform.ps2, name: $0) } + [StrayFile.Key(platformId: 33, name: "Okami (USA)")]),
            folders: folders)
        for name in ["Kuon (USA)", "Okami (USA)", "Rule of Rose (USA)"] { try ps2.remove("\(name).7z") }
        try gameBoy.remove("Okami (USA).7z")
        try ps2.add("Okami HD (USA).7z")
        try await importNow(folders: folders)
        let stray = try #require(try strays().first)

        let missing = try j.journal.missingROMs(for: stray)

        // Okami (Japan) is still there, and the Game Boy's Okami is another Platform's.
        #expect(missing.map(\.rom.folderName) == ["Okami (USA)", "Kuon (USA)", "Rule of Rose (USA)"])
    }

    @Test func aMissingROMIsListedWithItsGame() async throws {
        let okami = try await renamedOkami()

        #expect(try j.journal.missingROMs(for: okami.stray).map(\.gameName) == ["Okami"])
    }
}
