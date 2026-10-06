import Foundation
import GRDB
import Testing

@testable import LudeumCore

@Suite struct CompactedROMFolderTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "compacted \(UUID().uuidString)")

    @Test func a7zMesenOpensIsAReadyROM() throws {
        let snes = try FakeROMFolder(in: directory, platform: 19)
        let archive = try snes.add("Zelda (USA).7z")

        #expect(try snes.folder.scan() == [FolderROMFile(name: "Zelda (USA)", ready: archive, archive: archive)])
        #expect(try snes.folder.files(named: "Zelda (USA)") == [archive])
    }

    @Test func theLooseFileIsPlayedOverItsCompactedCopy() throws {
        let snes = try FakeROMFolder(in: directory, platform: 19)
        try snes.add("Zelda (USA).7z")
        let sfc = try snes.add("Zelda (USA).sfc")

        #expect(try snes.folder.scan().map(\.ready) == [sfc])
    }

    @Test func onAnAresPlatformAZipIsReadyAndA7zIsArchived() throws {
        let megaDrive = try FakeROMFolder(in: directory, platform: 29)
        let zip = try megaDrive.add("Sonic (USA).zip")
        let archive = try megaDrive.add("Streets of Rage (USA).7z")

        #expect(
            try megaDrive.folder.scan() == [
                FolderROMFile(name: "Sonic (USA)", ready: zip, archive: nil),
                FolderROMFile(name: "Streets of Rage (USA)", ready: nil, archive: archive),
            ])
    }

    @Test func aPSP7zIsArchived() throws {
        let psp = try FakeROMFolder(in: directory, platform: ROMPlatform.psp)
        try psp.add("Lumines (USA).7z")

        #expect(try psp.folder.scan().map(\.archived) == [true])
    }
}

@Suite struct SingleFileUnarchivePlanTests {
    let psp = ROMFolder.platform(ROMPlatform.psp, URL(filePath: "/Games/PSP", directoryHint: .isDirectory))!
    let archive = URL(filePath: "/Games/PSP/Lumines (USA).7z")

    func plan(_ paths: [String]) throws -> UnarchivePlan {
        try ROMArchiver.unarchivePlan(
            listing: paths.map { SevenZip.Entry(path: $0, size: 100) }, archive: archive, romName: "Lumines (USA)", folder: psp)
    }

    @Test func itsOneImageGoesLooseInTheROMFolderNamedAfterTheROM() throws {
        #expect(try plan(["lumines.ISO"]).destination == URL(filePath: "/Games/PSP/Lumines (USA).iso"))
    }

    @Test func findersHiddenFilesBesideTheImageAreLeftBehind() throws {
        let p = try plan([".DS_Store", "lumines.iso"])

        #expect(p.entries.map(\.path) == ["lumines.iso"])
        #expect(p.destination == URL(filePath: "/Games/PSP/Lumines (USA).iso"))
    }

    @Test func anImageWhoseOwnNameStartsWithADotIsStillTheGame() throws {
        let p = try plan([".DS_Store", "._.hack--Link (Japan).iso", ".hack--Link (Japan).iso"])

        #expect(p.entries.map(\.path) == [".hack--Link (Japan).iso"])
    }

    @Test func anythingBesideTheImageIsRefused() {
        #expect(throws: ArchiveError.notOneFile(["lumines.iso", "readme.txt"])) { try plan(["lumines.iso", "readme.txt"]) }
    }

    @Test func aFileTheEmulatorCantOpenIsRefused() {
        #expect(throws: ArchiveError.noImage) { try plan(["readme.txt"]) }
    }
}

@Suite(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
struct CompactTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "compact \(UUID().uuidString)", directoryHint: .isDirectory)
    let trash: URL

    init() throws {
        trash = directory.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    var archiver: ROMArchiver {
        let trash = trash
        return ROMArchiver(
            sevenZip: SevenZip.find()!, freeSpace: { _ in .max },
            moveToTrash: { try FileManager.default.moveItem(at: $0, to: trash.appending(path: $0.lastPathComponent)) })
    }

    func trashed() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: trash.path(percentEncoded: false)).sorted() }

    @Test func compactingPacksALooseROMIntoA7zItsEmulatorOpensAndTrashesTheFile() async throws {
        let gameBoy = try FakeROMFolder(in: directory, platform: 33)
        try gameBoy.add("Tetris (World).gb", String(repeating: "GB", count: 10_000))

        try await archiver.compact("Tetris (World)", in: gameBoy.folder)

        let rom = try #require(try gameBoy.folder.scan().first)
        #expect(rom.fileName == "Tetris (World).7z")
        #expect(!rom.archived)
        #expect(try await SevenZip.find()!.contents(of: rom.ready!).map { "\($0.path) \($0.size)" } == ["Tetris (World).gb 20000"])
        #expect(try trashed() == ["Tetris (World).gb"])
    }

    @Test func compactingA7zAresCantOpenRepacksItAsAZip() async throws {
        let megaDrive = try FakeROMFolder(in: directory, platform: 29)
        let sevenZip = SevenZip.find()!
        try megaDrive.add("work/Sonic (USA).md", String(repeating: "MD", count: 10_000))
        try await sevenZip.create(
            megaDrive.url.appending(path: "Sonic (USA).7z"), files: ["Sonic (USA).md"], in: megaDrive.url.appending(path: "work"),
            progress: { _ in })
        try megaDrive.remove("work")
        #expect(try megaDrive.folder.scan().map(\.archived) == [true])

        try await archiver.compact("Sonic (USA)", in: megaDrive.folder)

        let rom = try #require(try megaDrive.folder.scan().first)
        #expect(rom.fileName == "Sonic (USA).zip")
        #expect(!rom.archived)
        #expect(try await sevenZip.contents(of: rom.ready!).map { "\($0.path) \($0.size)" } == ["Sonic (USA).md 20000"])
        #expect(try trashed() == ["Sonic (USA).7z"])
    }

    @Test func aCompactedROMHasNothingToCompact() async throws {
        let snes = try FakeROMFolder(in: directory, platform: 19)
        try snes.add("Zelda (USA).7z")

        await #expect(throws: ArchiveError.nothingToDo) { try await archiver.compact("Zelda (USA)", in: snes.folder) }
    }

    @Test func aPSPROMInASubfolderArchivesWithoutFindersHiddenFilesSoItUnarchives() async throws {
        let psp = try FakeROMFolder(in: directory, platform: ROMPlatform.psp)
        try psp.add("Lumines (USA)/Lumines (USA).iso", String(repeating: "PSP", count: 10_000))
        try psp.add("Lumines (USA)/.DS_Store", "finder")

        try await archiver.archive("Lumines (USA)", in: psp.folder)
        #expect(try trashed() == ["Lumines (USA)"])
        try await archiver.unarchive(psp.url.appending(path: "Lumines (USA).7z"), romName: "Lumines (USA)", in: psp.folder)

        #expect(try psp.folder.scan().map(\.fileName) == ["Lumines (USA).iso"])
    }

    @Test func aPSPROMInASubfolderWhoseImagesNameStartsWithADotArchivesAndUnarchives() async throws {
        let psp = try FakeROMFolder(in: directory, platform: ROMPlatform.psp)
        try psp.add("hack Link (Japan)/.hack--Link (Japan).iso", String(repeating: "PSP", count: 10_000))
        try psp.add("hack Link (Japan)/.DS_Store", "finder")

        try await archiver.archive("hack Link (Japan)", in: psp.folder)
        try await archiver.unarchive(psp.url.appending(path: "hack Link (Japan).7z"), romName: "hack Link (Japan)", in: psp.folder)

        #expect(try psp.folder.scan().map(\.fileName) == ["hack Link (Japan).iso"])
    }

    @Test func aPSPROMsSubfolderHoldingMoreThanTheGameIsntArchived() async throws {
        let psp = try FakeROMFolder(in: directory, platform: ROMPlatform.psp)
        try psp.add("Lumines (USA)/Lumines (USA).iso", String(repeating: "PSP", count: 10_000))
        try psp.add("Lumines (USA)/readme.txt", "notes")

        await #expect(throws: ArchiveError.notOneFile(["Lumines (USA).iso", "readme.txt"])) {
            try await archiver.archive("Lumines (USA)", in: psp.folder)
        }
        #expect(try trashed().isEmpty)
        #expect(try psp.folder.scan().map(\.fileName) == ["Lumines (USA)/Lumines (USA).iso"])
    }

    @Test func aPSPROMArchivesAndUnarchivesAsOneLooseFile() async throws {
        let psp = try FakeROMFolder(in: directory, platform: ROMPlatform.psp)
        try psp.add("Lumines (USA).iso", String(repeating: "PSP", count: 10_000))

        try await archiver.archive("Lumines (USA)", in: psp.folder)
        #expect(try psp.folder.scan().map(\.fileName) == ["Lumines (USA).7z"])
        try await archiver.unarchive(psp.url.appending(path: "Lumines (USA).7z"), romName: "Lumines (USA)", in: psp.folder)

        let rom = try #require(try psp.folder.scan().first)
        #expect(rom.fileName == "Lumines (USA).iso")
        #expect(try String(contentsOf: rom.ready!, encoding: .utf8) == String(repeating: "PSP", count: 10_000))
        #expect(try trashed() == ["Lumines (USA).7z", "Lumines (USA).iso"])
    }

    @Test func unarchivingAPSPROMNamesItsFileAfterTheROM() async throws {
        let psp = try FakeROMFolder(in: directory, platform: ROMPlatform.psp)
        try psp.add("work/lumines.iso", "image")
        try await SevenZip.find()!.create(
            psp.url.appending(path: "Lumines (USA).7z"), files: ["lumines.iso"], in: psp.url.appending(path: "work"), progress: { _ in })
        try psp.remove("work")

        try await archiver.unarchive(psp.url.appending(path: "Lumines (USA).7z"), romName: "Lumines (USA)", in: psp.folder)

        #expect(try psp.folder.scan().map(\.fileName) == ["Lumines (USA).iso"])
    }
}

@Suite struct NotCompactedReviewTests {
    let j: LudeumHarness
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "not compacted \(UUID().uuidString)", directoryHint: .isDirectory)

    init() throws {
        j = try LudeumHarness()
    }

    /// A ROM folder ROM's row, Matched to a new Game or not.
    @discardableResult
    func rom(
        _ name: String, _ fileName: String, on platform: Int64, archived: Bool = false, missing: Bool = false, matched: Bool = false
    ) throws -> Int64 {
        try j.journal.db.write { db in
            try ROMPlatform.ensureKnown(db, platform)
            var game: Int64?
            if matched {
                try db.execute(sql: "INSERT INTO game (platformId, name) VALUES (?, ?)", arguments: [platform, name])
                game = db.lastInsertedRowID
            }
            try db.execute(
                sql: """
                    INSERT INTO rom (folderName, fileName, name, platformId, archived, missing, gameId, matchKind, matchedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    name, fileName, name, platform, archived, missing, game, game.map { _ in "manual" }, game.map { _ in Date() },
                ])
            return db.lastInsertedRowID
        }
    }

    @Test func presentROMsThatCanBeCompactedWaitInTheQueueMatchedOrNot() throws {
        try rom("Zelda (USA)", "Zelda (USA).sfc", on: 19, matched: true)
        try rom("Sonic (USA)", "Sonic (USA).7z", on: 29, archived: true)
        try rom("Tetris (World)", "Tetris (World).7z", on: 33)
        try rom("Wario Land (USA)", "Wario Land (USA).gb", on: 33, missing: true)
        try rom("Okami (USA)", "Okami (USA).iso", on: ROMPlatform.ps2)

        let items = try j.journal.reviewQueue().notCompacted

        #expect(items.map(\.rom.folderName) == ["Sonic (USA)", "Zelda (USA)"])
        #expect(items.map(\.compactFileName) == ["Sonic (USA).zip", "Zelda (USA).7z"])
        #expect(items.map { $0.game != nil } == [false, true])
        let queue = try j.journal.reviewQueue()
        #expect(queue.count == queue.noSuggestion.count + 2)
    }

    @Test(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
    func compactingRunsAsABackgroundTaskThenTheItemLeavesTheQueue() async throws {
        let snes = try FakeROMFolder(in: directory, platform: 19)
        try snes.add("Zelda (USA).sfc", String(repeating: "SNES", count: 1000))
        let id = try rom("Zelda (USA)", "Zelda (USA).sfc", on: 19)
        let item = try #require(try j.journal.reviewQueue().notCompacted.first)
        let trash = directory.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)

        try await Self.compact(item.rom, in: snes.folder, journal: j.journal, trash: trash)

        #expect(try j.journal.reviewQueue().notCompacted.isEmpty)
        let row = try #require(try j.journal.db.read { try Row.fetchOne($0, sql: "SELECT * FROM rom WHERE id = ?", arguments: [id]) })
        #expect(row["fileName"] as String == "Zelda (USA).7z")
        #expect(row["archived"] as Bool == false)
    }

    @MainActor static func compact(_ rom: LudeumROM, in folder: ROMFolder, journal: LudeumStore, trash: URL) async throws {
        let tasks = BackgroundTasks()
        let archiving = ROMArchiving(
            locator: ROMLocator(romFolders: [folder]), journal: journal, tasks: tasks,
            archiver: {
                ROMArchiver(
                    sevenZip: SevenZip.find()!, freeSpace: { _ in .max },
                    moveToTrash: { try FileManager.default.moveItem(at: $0, to: trash.appending(path: $0.lastPathComponent)) })
            })
        var finished = false

        archiving.start(rom) { finished = true }

        #expect(tasks.active(.rom(rom.id))?.title == "Compacting Zelda (USA)")
        await untilIdle(tasks)
        #expect(tasks.items.isEmpty)
        #expect(finished)
    }

    @Test func aGameArchivedInA7zAresCantOpenSaysToCompact() {
        let play = Play(
            platformId: 29, platformName: "Mega Drive",
            roms: [
                LudeumROM(
                    id: 1, folderName: "Sonic (USA)", platformId: 29, fileName: "Sonic (USA).7z", name: "Sonic (USA)", version: "",
                    disc: nil, missing: false, archived: true)
            ], settings: EmulatorSettings())

        #expect(play.availability == .refused(.archivedNeedsCompacting))
    }
}
