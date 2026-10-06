import Foundation
import Testing

@testable import LudeumCore

@Suite struct ROMArchivingActionTests {
    @Test func aReadyPS2FolderROMCanBeArchived() {
        #expect(ROMArchiving.action(for: folderROM("Okami (USA)")) == .archive)
    }

    @Test func anArchivedOneCanBeUnarchived() {
        #expect(ROMArchiving.action(for: folderROM("Okami (USA)", archived: true)) == .unarchive)
    }

    @Test func aMissingROMCantBeEither() {
        #expect(ROMArchiving.action(for: folderROM("Okami (USA)", missing: true)) == nil)
    }

    @Test func aPlatformWithNeitherCantDoAnything() {
        #expect(ROMArchiving.action(for: rom("Sonic CD (USA)", on: 78, "Sonic CD (USA)/Sonic CD (USA).cue")) == nil)
    }

    @Test(arguments: [
        (Int64(7), "Vagrant Story (USA)/Vagrant Story (USA).cue"), (32, "Nights (USA)/Nights (USA).cue"), (150, "Ys (USA)/Ys (USA).cue"),
        (21, "Metroid Prime (USA).rvz"),
    ])
    func aDiscOrGameCubeROMCanBeArchivedAndUnarchived(platform: Int64, fileName: String) {
        #expect(ROMArchiving.action(for: rom("Game", on: platform, fileName)) == .archive)
        #expect(ROMArchiving.action(for: rom("Game", on: platform, "Game.7z", archived: true)) == .unarchive)
    }

    @Test func aPSPROMCanBeArchivedAndUnarchived() {
        #expect(ROMArchiving.action(for: rom("Lumines (USA)", on: ROMPlatform.psp, "Lumines (USA).iso")) == .archive)
        #expect(ROMArchiving.action(for: rom("Lumines (USA)", on: ROMPlatform.psp, "Lumines (USA).7z", archived: true)) == .unarchive)
    }

    @Test func pspAndGameCubeROMsUnarchiveToOneFileAndDiscROMsIntoAFolder() {
        #expect(ROMArchiving.unarchivesToOneFile(rom("Lumines (USA)", on: ROMPlatform.psp, "Lumines (USA).7z", archived: true)))
        #expect(ROMArchiving.unarchivesToOneFile(rom("Metroid Prime (USA)", on: 21, "Metroid Prime (USA).7z", archived: true)))
        #expect(!ROMArchiving.unarchivesToOneFile(rom("Vagrant Story (USA)", on: 7, "Vagrant Story (USA).7z", archived: true)))
        #expect(!ROMArchiving.unarchivesToOneFile(rom("ICO", on: ROMPlatform.ps2, "ICO.7z", archived: true)))
    }

    @Test func aLooseCartridgeROMCanBeCompactedIntoA7z() {
        let zelda = rom("Zelda (USA)", on: 19, "Zelda (USA).sfc")

        #expect(ROMArchiving.action(for: zelda) == .compact)
        #expect(ROMArchiving.compactFileName(for: zelda) == "Zelda (USA).7z")
    }

    @Test func aCompactedOneCantBeArchivedOrCompactedAgain() {
        #expect(ROMArchiving.action(for: rom("Zelda (USA)", on: 19, "Zelda (USA).7z")) == nil)
        #expect(ROMArchiving.action(for: rom("Sonic (USA)", on: 29, "Sonic (USA).zip")) == nil)
    }

    @Test func anAresROMCompactsIntoAZipEvenFromA7zAresCantOpen() {
        let sonic = rom("Sonic (USA)", on: 29, "Sonic (USA).7z", archived: true)

        #expect(ROMArchiving.action(for: sonic) == .compact)
        #expect(ROMArchiving.compactFileName(for: sonic) == "Sonic (USA).zip")
    }

    @Test func aMissingOneCantBeCompacted() {
        #expect(ROMArchiving.action(for: rom("Zelda (USA)", on: 19, "Zelda (USA).sfc", missing: true)) == nil)
    }

    func rom(_ name: String, on platform: Int64, _ fileName: String, archived: Bool = false, missing: Bool = false) -> LudeumROM {
        LudeumROM(
            id: 1, folderName: name, platformId: platform, fileName: fileName, name: name, version: "", disc: nil, missing: missing,
            archived: archived)
    }
}

extension ROMFolderImportTests {
    @Test(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
    func archivingRunsAsABackgroundTaskThenTheJournalSeesItArchived() async throws {
        let game = try await okamiInTheJournal()
        try ps2.remove("Okami (USA).7z")
        try ps2.add("Okami (USA).iso", String(repeating: "PS2", count: 10_000))
        try j.journal.checkROMsAgain(game, in: [ps2.folder])
        let rom = try #require(try j.journal.roms(of: game).first)

        try await Self.archive(
            rom, journal: j.journal, locator: ROMLocator(romFolders: [ps2.folder]),
            trash: h.directory.appending(path: "Trash", directoryHint: .isDirectory))

        #expect(try j.journal.roms(of: game).map(\.archived) == [true])
    }

    @MainActor static func archive(_ rom: LudeumROM, journal: LudeumStore, locator: ROMLocator, trash: URL) async throws {
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let tasks = BackgroundTasks()
        let archiving = ROMArchiving(
            locator: locator, journal: journal, tasks: tasks,
            archiver: {
                ROMArchiver(
                    sevenZip: SevenZip.find()!, freeSpace: { _ in .max },
                    moveToTrash: { try FileManager.default.moveItem(at: $0, to: trash.appending(path: $0.lastPathComponent)) })
            })
        var finished = false

        archiving.start(rom) { finished = true }

        #expect(tasks.active(.rom(rom.id))?.title == "Archiving Okami (USA)")
        await untilIdle(tasks)
        #expect(tasks.items.isEmpty)
        #expect(finished)
    }
}
