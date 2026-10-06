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

    @Test func anOpenEmuROMCantBeEither() {
        let rom = LudeumROM(
            id: 1, openEmuPk: 7, folderName: nil, systemId: "openemu.system.snes", fileName: "zelda.sfc", name: "Zelda",
            version: "", disc: nil, missing: false, archived: false)

        #expect(ROMArchiving.action(for: rom) == nil)
    }
}

extension ROMFolderImportTests {
    @Test func archivingRunsAsABackgroundTaskThenTheJournalSeesItArchived() async throws {
        let game = try await okamiInTheJournal()
        try ps2.remove("Okami (USA).7z")
        try ps2.add("Okami (USA).iso", String(repeating: "PS2", count: 10_000))
        try j.journal.checkROMsAgain(game, in: [ps2.folder])
        let rom = try #require(try j.journal.roms(of: game).first)

        try await Self.archive(
            rom, of: game, journal: j.journal, locator: ROMLocator(openEmuLibrary: oe.folder, romFolders: [ps2.folder]),
            trash: h.directory.appending(path: "Trash", directoryHint: .isDirectory))

        #expect(try j.journal.roms(of: game).map(\.archived) == [true])
    }

    @MainActor static func archive(_ rom: LudeumROM, of game: GameID, journal: LudeumStore, locator: ROMLocator, trash: URL) async throws {
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

        archiving.start(rom, of: game) { finished = true }

        #expect(tasks.active(.rom(rom.id))?.title == "Archiving Okami (USA)")
        await untilIdle(tasks)
        #expect(tasks.items.isEmpty)
        #expect(finished)
    }
}
