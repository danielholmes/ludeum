import Foundation
import GRDB
import Synchronization
import Testing

@testable import LudeumCore

extension LudeumStore {
    /// A read that waits behind any write.
    fileprivate func attachmentCount() throws -> Int {
        try db.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM attachment") ?? 0 }
    }
}

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

    /// `attachments`, doing `during` as each picked file is copied, or failing instead with `failing`.
    func attachments(during: @escaping @Sendable () throws -> Void, failing: (any Error & Sendable)? = nil) -> Attachments {
        let trash = trash
        return Attachments(
            journal: j.journal, root: root,
            moveToTrash: { file in try FileManager.default.moveItem(at: file, to: trash.appending(path: file.lastPathComponent)) },
            copy: { from, to in
                try during()
                if let failing { throw failing }
                try FileManager.default.copyItem(at: from, to: to)
            })
    }

    /// Whether the journal can be read from another thread right now, as the main thread would, rather than waiting. On a
    /// thread of its own, and with time to spare, as the other suites running alongside can starve it: only a journal that
    /// really is held waits this long.
    static func journalIsFree(_ journal: LudeumStore) -> Bool {
        let read = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            _ = try? journal.attachmentCount()
            read.signal()
        }
        return read.wait(timeout: .now() + 30) == .success
    }

    // MARK: Adding

    /// Dropbox can take minutes over a file it keeps online only, and the main thread reads the journal all the time.
    @Test func theJournalIsFreeWhileAFileIsCopiedIn() throws {
        let game = try j.addGame()
        let journal = j.journal
        let free = Mutex<Bool?>(nil)
        let slow = attachments(during: { free.withLock { $0 = Self.journalIsFree(journal) } })

        try slow.add([try pick("manual.pdf")], to: game)

        #expect(free.withLock { $0 } == true)
        #expect(files("SNES/Super Metroid") == ["manual.pdf"])
    }

    @Test func theJournalIsFreeWhileALocatedFileIsCopiedIn() throws {
        let game = try j.addGame()
        let a = try #require(try attachments.add([try pick("scan.pdf")], to: game).first)
        try FileManager.default.removeItem(at: a.url)
        try attachments.checkFiles(game)
        let journal = j.journal
        let free = Mutex<Bool?>(nil)
        let slow = attachments(during: { free.withLock { $0 = Self.journalIsFree(journal) } })

        try slow.locate(a.id, file: try pick("found.pdf"), moving: false)

        #expect(free.withLock { $0 } == true)
        #expect(try attachments.attachments(of: game).map(\.missing) == [false])
    }

    @Test func aFileThatCantBeCopiedAddsNothingAndStaysWhereItIs() throws {
        let game = try j.addGame()
        let file = try pick("manual.pdf")
        let failing = attachments(during: {}, failing: CocoaError(.fileReadUnknown))

        #expect(throws: CocoaError.self) { try failing.add([file], to: game, moving: true) }

        #expect(try attachments.attachments(of: game).isEmpty)
        #expect(files("SNES/Super Metroid").isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    @Test func aLocatedFileThatCantBeCopiedLeavesItMissingWithNothingInItsPlace() throws {
        let game = try j.addGame()
        let a = try #require(try attachments.add([try pick("scan.pdf")], to: game).first)
        try FileManager.default.removeItem(at: a.url)
        try attachments.checkFiles(game)
        let file = try pick("found.pdf")
        // A copy that dies part of the way through.
        let dying = Attachments(
            journal: j.journal, root: root, moveToTrash: { _ in },
            copy: { _, to in
                try Data("par".utf8).write(to: to)
                throw CocoaError(.fileReadUnknown)
            })

        #expect(throws: CocoaError.self) { try dying.locate(a.id, file: file, moving: true) }

        #expect(!FileManager.default.fileExists(atPath: a.url.path(percentEncoded: false)))
        #expect(try attachments.attachments(of: game).map(\.missing) == [true])
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    /// The copy can outlast a rename: its file goes where the Game's folder is by then.
    @Test func aFileGoesToWhereItsGamesFolderIsOnceItsCopied() throws {
        let game = try j.addGame()
        try attachments.add([try pick("manual.pdf")], to: game)
        let journal = j.journal
        let plain = attachments
        let slow = attachments(during: {
            try journal.setNameOverride(game, "Metroid 3")
            try plain.follow(game)
        })

        try slow.add([try pick("map.png")], to: game)

        #expect(files("SNES/Metroid 3") == ["manual.pdf", "map.png"])
    }

    @Test func aFileGoesBackToWhereItsGamesFolderIsOnceItsCopied() throws {
        let game = try j.addGame()
        let a = try #require(try attachments.add([try pick("scan.pdf")], to: game).first)
        try FileManager.default.removeItem(at: a.url)
        try attachments.checkFiles(game)
        let journal = j.journal
        let plain = attachments
        let slow = attachments(during: {
            try journal.setNameOverride(game, "Metroid 3")
            try plain.follow(game)
        })

        try slow.locate(a.id, file: try pick("found.pdf"), moving: false)

        #expect(files("SNES/Metroid 3") == ["scan.pdf"])
    }

    @Test func aFileThatCameBackWhileTheOtherWasCopiedLeavesThePickedOneAlone() throws {
        let game = try j.addGame()
        let a = try #require(try attachments.add([try pick("scan.pdf", "its own")], to: game).first)
        let hidden = picked.appending(path: "hidden.pdf")
        try FileManager.default.moveItem(at: a.url, to: hidden)
        try attachments.checkFiles(game)
        let file = try pick("found.pdf", "another")
        let slow = attachments(during: { try FileManager.default.moveItem(at: hidden, to: a.url) })

        try slow.locate(a.id, file: file, moving: true)

        #expect(try String(contentsOf: a.url, encoding: .utf8) == "its own")
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        #expect(try attachments.attachments(of: game).map(\.missing) == [false])
    }

    /// Stopped as it's copied, what has gone in stays and the rest doesn't.
    @Test func aCancelledAddStopsOnceTheFileBeingCopiedIsDone() async throws {
        let game = try j.addGame()
        let (first, second) = (try pick("a.pdf"), try pick("b.pdf"))
        let copies = Mutex(0)
        let cancelling = attachments(during: {
            let copy = copies.withLock {
                $0 += 1
                return $0
            }
            if copy == 2 { withUnsafeCurrentTask { $0?.cancel() } }
        })

        let result = await Task.detached { try cancelling.add([first, second], to: game, moving: true) }.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(files("SNES/Super Metroid") == ["a.pdf"])
        #expect(try trashed() == ["a.pdf"])
        #expect(FileManager.default.fileExists(atPath: second.path(percentEncoded: false)))
    }

    @Test func eachFileAddedMovesItsProgressOn() throws {
        let game = try j.addGame()
        let fractions = Mutex<[Double]>([])

        try attachments.add([try pick("a.pdf"), try pick("b.pdf")], to: game) { fraction in fractions.withLock { $0.append(fraction) } }

        #expect(fractions.withLock { $0 } == [0.5, 1])
    }

    @Test func checkRefusesWhatCantBeAnAttachmentBeforeAnythingStarts() throws {
        let scans = picked.appending(path: "Scans", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scans, withIntermediateDirectories: true)

        #expect(throws: AttachmentError.notAFile("Scans")) { try attachments.check([try pick("manual.pdf"), scans]) }
        #expect(throws: Never.self) { try attachments.check([try pick("manual.pdf")]) }
    }

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
        try j.journal.addPlatform(id: 14, name: "Mac")
        let game = try j.journal.addGame(platformId: 14, name: "Half-Life 2: Episode One")

        try attachments.add([try pick("manual.pdf")], to: game)

        #expect(files("Mac") == ["Half-Life 2 - Episode One"])
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

    @Test func anExtensionTypedAgainIsNotDoubled() throws {
        let game = try j.addGame()
        let a = try #require(try attachments.add([try pick("scan.pdf")], to: game).first)

        try attachments.rename(a.id, to: "Manual.PDF")

        #expect(files("SNES/Super Metroid") == ["Manual.pdf"])
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

        #expect(try trashed() == ["a.pdf", "b.pdf"])
        #expect(!exists("SNES"))
        #expect(throws: LudeumError.gameNotFound) { try j.journal.game(game) }
    }

    @Test func deletingAGameLeavesFilesIPutInItsFolderMyself() throws {
        let game = try j.addGame()
        try attachments.add([try pick("a.pdf")], to: game)
        try Data("mine".utf8).write(to: root.appending(path: "SNES/Super Metroid/notes.txt"))

        try attachments.deleteGame(game)

        #expect(try trashed() == ["a.pdf"])
        #expect(files("SNES/Super Metroid") == ["notes.txt"])
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

        try attachments.checkFiles()

        #expect(try attachments.attachments(of: game).map(\.missing) == [true])
        let queue = try j.journal.reviewQueue()
        #expect(queue.missingAttachments.map(\.id) == [a.id])
        #expect(queue.missingAttachments.map(\.fileName) == ["manual.pdf"])
        #expect(queue.missingAttachments.map(\.game.name) == ["Super Metroid"])
        #expect(queue.count == 1)

        try FileManager.default.moveItem(at: elsewhere, to: file)
        try attachments.checkFiles(game)

        #expect(try j.journal.reviewQueue().missingAttachments.isEmpty)
    }

    @Test func locatingAMissingFilePutsItBackUnderItsOwnName() throws {
        let game = try j.addGame()
        let a = try #require(try attachments.add([try pick("manual.pdf")], to: game).first)
        try FileManager.default.removeItem(at: root.appending(path: "SNES/Super Metroid/manual.pdf"))
        try attachments.checkFiles()

        try attachments.locate(a.id, file: try pick("found it.pdf"), moving: true)

        #expect(files("SNES/Super Metroid") == ["manual.pdf"])
        #expect(try trashed() == ["found it.pdf"])
        #expect(try j.journal.reviewQueue().missingAttachments.isEmpty)
    }

    @Test func locatingAFileThatsBackAlreadyLeavesThePickedFileAlone() throws {
        let game = try j.addGame()
        let a = try #require(try attachments.add([try pick("manual.pdf")], to: game).first)
        let file = root.appending(path: "SNES/Super Metroid/manual.pdf")
        let elsewhere = picked.appending(path: "kept.pdf")
        try FileManager.default.moveItem(at: file, to: elsewhere)
        try attachments.checkFiles()
        try FileManager.default.copyItem(at: elsewhere, to: file)

        try attachments.locate(a.id, file: elsewhere, moving: true)
        try attachments.locate(a.id, file: file, moving: true)

        #expect(files("SNES/Super Metroid") == ["manual.pdf"])
        #expect(FileManager.default.fileExists(atPath: elsewhere.path(percentEncoded: false)))
        #expect(try trashed().isEmpty)
        #expect(try j.journal.reviewQueue().missingAttachments.isEmpty)
    }

    @Test func aFileAlreadyInAttachmentsIsRefused() throws {
        let game = try j.addGame()
        let other = try j.addGame("Metroid Fusion")
        let a = try #require(try attachments.add([try pick("manual.pdf")], to: game).first)

        #expect(throws: AttachmentError.alreadyInAttachments("manual.pdf")) {
            try attachments.add([a.url], to: other, moving: true)
        }

        #expect(files("SNES/Super Metroid") == ["manual.pdf"])
        #expect(try trashed().isEmpty)
    }

    @Test func deletingAMissingAttachmentJustLeavesTheJournal() throws {
        let game = try j.addGame()
        let a = try #require(try attachments.add([try pick("manual.pdf")], to: game).first)
        try FileManager.default.removeItem(at: root.appending(path: "SNES/Super Metroid/manual.pdf"))
        try attachments.checkFiles()

        try attachments.delete(a.id)

        #expect(try trashed().isEmpty)
        #expect(try j.journal.reviewQueue().missingAttachments.isEmpty)
        #expect(!exists("SNES"))
    }

    @Test func filesIDidntAddAreIgnored() throws {
        let game = try j.addGame()
        try attachments.add([try pick("manual.pdf")], to: game)
        try Data("stray".utf8).write(to: root.appending(path: "SNES/Super Metroid/stray.txt"))

        try attachments.checkFiles()

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
