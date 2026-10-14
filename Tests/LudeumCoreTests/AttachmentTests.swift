import Foundation
import Testing

@testable import LudeumCore

/// Attachments: files about a Game kept in its folder under `Attachments/` in the Data folder (ADR 0014).
@Suite struct AttachmentTests {
    let j: LudeumHarness
    let data: URL
    let root: URL
    let trash: URL
    let picked: URL
    let attachments: Attachments

    init() throws {
        j = try LudeumHarness()
        data = j.directory.appending(path: "Data", directoryHint: .isDirectory)
        root = LudeumFolder(url: j.directory, data: data).attachments
        trash = j.directory.appending(path: "Trash", directoryHint: .isDirectory)
        picked = j.directory.appending(path: "Downloads", directoryHint: .isDirectory)
        for folder in [trash, picked] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let trash = trash
        attachments = Attachments(journal: j.journal, root: root) { file in
            try FileManager.default.moveItem(at: file, to: trash.appending(path: file.lastPathComponent))
        }
    }

    /// A file in Downloads, to be picked.
    func pick(_ name: String, _ text: String = "manual") throws -> URL {
        let file = picked.appending(path: name)
        try Data(text.utf8).write(to: file)
        return file
    }

    func files(_ path: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.appending(path: path).path(percentEncoded: false))) ?? [])
            .filter { !$0.hasPrefix(".") }.sorted()
    }

    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false)) }

    func trashed() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: trash.path(percentEncoded: false)).sorted() }

    // MARK: Adding

    @Test func anAddedFileIsCopiedIntoItsGamesFolderUnderItsOwnName() throws {
        let game = try j.addGame("Super Metroid")
        let file = try pick("SM_US_scan.pdf")

        let added = try attachments.add([file], to: game)

        #expect(files("SNES/Super Metroid") == ["SM_US_scan.pdf"])
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        #expect(try attachments.attachments(of: game).map(\.fileName) == ["SM_US_scan.pdf"])
        #expect(added.map(\.url) == [root.appending(path: "SNES/Super Metroid/SM_US_scan.pdf")])
        #expect(added.map(\.isManual) == [false])
    }

    @Test func aMovedFilesOriginalGoesToTheTrash() throws {
        let game = try j.addGame()

        try attachments.add([try pick("map.png")], to: game, moving: true)

        #expect(files("SNES/Super Metroid") == ["map.png"])
        #expect(try trashed() == ["map.png"])
    }

    @Test func addManualMarksItAManual() throws {
        let game = try j.addGame()

        try attachments.add([try pick("manual.pdf")], to: game, manual: true)
        try attachments.add([try pick("map.png")], to: game)

        #expect(try attachments.attachments(of: game).map(\.isManual) == [true, false])
        #expect(try attachments.manuals(of: game).map(\.fileName) == ["manual.pdf"])
    }

    @Test func manualsComeFirstThenByName() throws {
        let game = try j.addGame()
        try attachments.add([try pick("b.pdf"), try pick("a.pdf"), try pick("Z guide.pdf")], to: game)
        let b = try #require(try attachments.attachments(of: game).first { $0.fileName == "b.pdf" })

        try attachments.setManual(b.id, true)

        #expect(try attachments.attachments(of: game).map(\.fileName) == ["b.pdf", "a.pdf", "Z guide.pdf"])
        try attachments.setManual(b.id, false)
        #expect(try attachments.manuals(of: game).isEmpty)
    }

    @Test func aNameAlreadyInTheFolderGetsASuffix() throws {
        let game = try j.addGame()
        try attachments.add([try pick("manual.pdf")], to: game)
        let other = picked.appending(path: "Other", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data("japanese".utf8).write(to: other.appending(path: "Manual.pdf"))

        try attachments.add([other.appending(path: "Manual.pdf")], to: game)

        #expect(files("SNES/Super Metroid") == ["Manual (2).pdf", "manual.pdf"])
    }

    @Test func aFolderIsRefusedAndNothingIsAdded() throws {
        let game = try j.addGame()
        let scans = picked.appending(path: "Scans", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scans, withIntermediateDirectories: true)

        #expect(throws: AttachmentError.notAFile("Scans")) { try attachments.add([try pick("manual.pdf"), scans], to: game) }

        #expect(try attachments.attachments(of: game).isEmpty)
        #expect(!exists("SNES"))
    }

    @Test func aPlatformWithNoROMFolderIsNamedAsIGDBNamesIt() throws {
        try j.journal.addPlatform(id: 6, name: "PC (Microsoft Windows)")
        let game = try j.journal.addGame(platformId: 6, name: "Half-Life 2: Episode One")

        try attachments.add([try pick("manual.pdf")], to: game)

        #expect(files("PC (Microsoft Windows)") == ["Half-Life 2 - Episode One"])
    }

    @Test func twoGamesWithOneNameOnOnePlatformGetFoldersOfTheirOwn() throws {
        let first = try j.addGame("Prince of Persia")
        let second = try j.addGame("Prince of Persia")

        try attachments.add([try pick("manual.pdf")], to: first)
        try attachments.add([try pick("manual.pdf")], to: second)

        #expect(files("SNES") == ["Prince of Persia", "Prince of Persia (2)"])
    }

    @Test func aFolderAlreadyOnDiskIsNotShared() throws {
        let game = try j.addGame()
        try FileManager.default.createDirectory(at: root.appending(path: "SNES/Super Metroid"), withIntermediateDirectories: true)

        try attachments.add([try pick("manual.pdf")], to: game)

        #expect(files("SNES/Super Metroid (2)") == ["manual.pdf"])
    }

    // MARK: Renaming

    @Test func renamingKeepsTheExtension() throws {
        let game = try j.addGame()
        let a = try #require(try attachments.add([try pick("SM_US_scan.pdf")], to: game).first)

        try attachments.rename(a.id, to: "Manual (USA)")

        #expect(files("SNES/Super Metroid") == ["Manual (USA).pdf"])
        #expect(try attachments.attachments(of: game).map(\.fileName) == ["Manual (USA).pdf"])
    }

    @Test func renamingToANameAlreadyTakenIsRefused() throws {
        let game = try j.addGame()
        let added = try attachments.add([try pick("a.pdf"), try pick("b.pdf")], to: game)

        #expect(throws: AttachmentError.nameTaken) { try attachments.rename(added[1].id, to: "A") }
        #expect(throws: AttachmentError.nameRequired) { try attachments.rename(added[1].id, to: "  ") }

        #expect(files("SNES/Super Metroid") == ["a.pdf", "b.pdf"])
    }

    @Test func renamingCanChangeOnlyTheCase() throws {
        let game = try j.addGame()
        let a = try #require(try attachments.add([try pick("manual.pdf")], to: game).first)

        try attachments.rename(a.id, to: "Manual")

        #expect(files("SNES/Super Metroid") == ["Manual.pdf"])
    }

    // MARK: Deleting

    @Test func deletingSendsTheFileToTheTrashAndTheLastTakesItsEmptyFoldersWithIt() throws {
        let game = try j.addGame()
        let added = try attachments.add([try pick("a.pdf"), try pick("b.pdf")], to: game)

        try attachments.delete(added[0].id)
        #expect(files("SNES/Super Metroid") == ["b.pdf"])

        try attachments.delete(added[1].id)
        #expect(try trashed() == ["a.pdf", "b.pdf"])
        #expect(!exists("SNES"))
        #expect(try attachments.attachments(of: game).isEmpty)
    }

    @Test func deletingAGameSendsItsAttachmentsToTheTrash() throws {
        let game = try j.addGame()
        try attachments.add([try pick("a.pdf"), try pick("b.pdf")], to: game)

        try attachments.deleteGame(game)

        #expect(try trashed() == ["Super Metroid"])
        #expect(!exists("SNES"))
        #expect(throws: LudeumError.gameNotFound) { try j.journal.game(game) }
    }

    @Test func aGameWithACopyKeepsItsAttachments() throws {
        let game = try j.addGame()
        try attachments.add([try pick("a.pdf")], to: game)
        try j.journal.addCopy(game, CopyDraft(kind: .physical))

        #expect(throws: LudeumError.gameHasCopies) { try attachments.deleteGame(game) }

        #expect(files("SNES/Super Metroid") == ["a.pdf"])
        #expect(try trashed().isEmpty)
    }

    // MARK: Missing files

    @Test func aMissingFileIsInTheReviewQueueUntilItComesBack() throws {
        let game = try j.addGame()
        let a = try #require(try attachments.add([try pick("manual.pdf")], to: game).first)
        let file = root.appending(path: "SNES/Super Metroid/manual.pdf")
        let elsewhere = picked.appending(path: "kept.pdf")
        try FileManager.default.moveItem(at: file, to: elsewhere)

        try attachments.check()

        #expect(try attachments.attachments(of: game).map(\.missing) == [true])
        let queue = try j.journal.reviewQueue()
        #expect(queue.missingAttachments.map(\.id) == [a.id])
        #expect(queue.missingAttachments.map(\.fileName) == ["manual.pdf"])
        #expect(queue.missingAttachments.map(\.game.name) == ["Super Metroid"])
        #expect(queue.count == 1)

        try FileManager.default.moveItem(at: elsewhere, to: file)
        try attachments.check(game)

        #expect(try j.journal.reviewQueue().missingAttachments.isEmpty)
    }

    @Test func locatingAMissingFilePutsItBackUnderItsOwnName() throws {
        let game = try j.addGame()
        let a = try #require(try attachments.add([try pick("manual.pdf")], to: game).first)
        try FileManager.default.removeItem(at: root.appending(path: "SNES/Super Metroid/manual.pdf"))
        try attachments.check()

        try attachments.locate(a.id, file: try pick("found it.pdf"), moving: true)

        #expect(files("SNES/Super Metroid") == ["manual.pdf"])
        #expect(try trashed() == ["found it.pdf"])
        #expect(try j.journal.reviewQueue().missingAttachments.isEmpty)
    }

    @Test func deletingAMissingAttachmentJustLeavesTheJournal() throws {
        let game = try j.addGame()
        let a = try #require(try attachments.add([try pick("manual.pdf")], to: game).first)
        try FileManager.default.removeItem(at: root.appending(path: "SNES/Super Metroid/manual.pdf"))
        try attachments.check()

        try attachments.delete(a.id)

        #expect(try trashed().isEmpty)
        #expect(try j.journal.reviewQueue().missingAttachments.isEmpty)
        #expect(!exists("SNES"))
    }

    @Test func filesIDidntAddAreIgnored() throws {
        let game = try j.addGame()
        try attachments.add([try pick("manual.pdf")], to: game)
        try Data("stray".utf8).write(to: root.appending(path: "SNES/Super Metroid/stray.txt"))

        try attachments.check()

        #expect(try attachments.attachments(of: game).map(\.fileName) == ["manual.pdf"])
    }

    // MARK: Following the Game

    @Test func aRenamedGamesFolderFollowsItsName() throws {
        let game = try j.addGame("Super Metroid")
        try attachments.add([try pick("manual.pdf")], to: game)

        try j.journal.setNameOverride(game, "Metroid 3")
        try attachments.follow(game)

        #expect(files("SNES") == ["Metroid 3"])
        #expect(try attachments.attachments(of: game).map(\.url) == [root.appending(path: "SNES/Metroid 3/manual.pdf")])
    }

    @Test func aFolderWithASuffixStaysWhileItsNameStillFits() throws {
        let first = try j.addGame("Prince of Persia")
        let second = try j.addGame("Prince of Persia")
        try attachments.add([try pick("manual.pdf")], to: first)
        try attachments.add([try pick("manual.pdf")], to: second)

        try attachments.followAll()

        #expect(files("SNES") == ["Prince of Persia", "Prince of Persia (2)"])
    }

    @Test func aGameMovedToAnotherPlatformTakesItsFolderAlong() throws {
        let game = try j.addGame("Super Metroid")
        try attachments.add([try pick("manual.pdf")], to: game)

        try j.journal.link(game, igdbGameId: 1103, igdbName: "Super Metroid", platform: IGDBPlatform(id: 58, name: "Super Famicom"))
        try attachments.followAll()

        #expect(files("") == ["Super Famicom"])
        #expect(files("Super Famicom/Super Metroid") == ["manual.pdf"])
    }

    // MARK: Storage

    @Test func storageCountsAttachmentsInTheDataFolder() throws {
        let game = try j.addGame()
        try attachments.add([try pick("manual.pdf", "12345")], to: game)

        let stats = StorageStats.measure(LudeumFolder(url: j.directory, data: data), journal: j.journal, cache: trash)

        #expect(stats.attachments == 5)
        #expect(stats.dataFolder == 5)
    }
}
