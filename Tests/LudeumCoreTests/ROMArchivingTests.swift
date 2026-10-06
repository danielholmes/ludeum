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

    @Test func aPlatformWithoutAROMFolderCantDoAnything() {
        let atari2600: Int64 = 59
        #expect(ROMArchiving.action(for: rom("Pitfall! (USA)", on: atari2600, "Pitfall! (USA).a26")) == nil)
    }

    @Test(arguments: [
        (Int64(7), "Vagrant Story (USA)/Vagrant Story (USA).cue"), (32, "Nights (USA)/Nights (USA).cue"), (150, "Ys (USA)/Ys (USA).cue"),
        (78, "Sonic CD (USA)/Sonic CD (USA).cue"), (21, "Metroid Prime (USA).rvz"),
        (5, "World of Goo (USA) (WiiWare).wad"),
    ])
    func aDiscGameCubeOrWiiROMCanBeArchivedAndUnarchived(platform: Int64, fileName: String) {
        #expect(ROMArchiving.action(for: rom("Game", on: platform, fileName)) == .archive)
        #expect(ROMArchiving.action(for: rom("Game", on: platform, "Game.7z", archived: true)) == .unarchive)
    }

    @Test func aPSPROMCanBeArchivedAndUnarchived() {
        #expect(ROMArchiving.action(for: rom("Lumines (USA)", on: ROMPlatform.psp, "Lumines (USA).iso")) == .archive)
        #expect(ROMArchiving.action(for: rom("Lumines (USA)", on: ROMPlatform.psp, "Lumines (USA).7z", archived: true)) == .unarchive)
    }

    @Test(arguments: IntoFolders.platforms)
    func everyDiscPlatformArchivesIntoAFolder(platform: Int64) {
        #expect(ROMPlatform.all[platform]?.archiving == .intoFolder)
    }

    @Test func pspGameCubeAndWiiROMsUnarchiveToOneFileAndDiscROMsIntoAFolder() {
        #expect(ROMArchiving.unarchivesToOneFile(rom("Lumines (USA)", on: ROMPlatform.psp, "Lumines (USA).7z", archived: true)))
        #expect(ROMArchiving.unarchivesToOneFile(rom("Metroid Prime (USA)", on: 21, "Metroid Prime (USA).7z", archived: true)))
        #expect(
            ROMArchiving.unarchivesToOneFile(rom("World of Goo (USA) (WiiWare)", on: 5, "World of Goo (USA) (WiiWare).7z", archived: true)))
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

extension ROMFolderImportTests {
    @Test(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
    func anArchiveThatFailsAfterItsFilesChangedStillShowsTheJournalWhatsThere() async throws {
        let game = try await okamiInTheJournal()
        try ps2.remove("Okami (USA).7z")
        try ps2.add("Okami (USA).iso", String(repeating: "PS2", count: 10_000))
        try j.journal.checkROMsAgain(game, in: [ps2.folder])
        let rom = try #require(try j.journal.roms(of: game).first)

        let finished = await Self.archiveButFailToTrash(rom, journal: j.journal, locator: ROMLocator(romFolders: [ps2.folder]))

        // The .7z is in place and its .iso couldn't go to the Trash: the ROM is now in both forms.
        #expect(try self.rom("Okami (USA)")?["inBothForms"] as Bool? == true)
        #expect(finished)
    }

    /// Archives with a Trash that refuses everything, so the task fails once the `.7z` is already in place. Returns
    /// whether `finished` ran.
    @MainActor static func archiveButFailToTrash(_ rom: LudeumROM, journal: LudeumStore, locator: ROMLocator) async -> Bool {
        struct NoTrash: Error {}
        let tasks = BackgroundTasks()
        let archiving = ROMArchiving(
            locator: locator, journal: journal, tasks: tasks,
            archiver: { ROMArchiver(sevenZip: SevenZip.find()!, freeSpace: { _ in .max }, moveToTrash: { _ in throw NoTrash() }) })
        var finished = false

        archiving.start(rom) { finished = true }
        await untilIdle(tasks)

        #expect(tasks.items.count == 1)
        return finished
    }
}
