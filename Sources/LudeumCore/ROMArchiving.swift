import Foundation

/// Archive and Unarchive: a ROM folder ROM packed into a `.7z`, or unpacked so it can be Played,
/// as a Background task. Only PS2 ROMs so far.
@MainActor public struct ROMArchiving {
    public enum Action: Sendable, Equatable {
        case archive, unarchive
    }

    let locator: ROMLocator
    let journal: LudeumStore?
    let tasks: BackgroundTasks
    let archiver: @Sendable () throws -> ROMArchiver

    public init(
        locator: ROMLocator, journal: LudeumStore?, tasks: BackgroundTasks,
        archiver: @escaping @Sendable () throws -> ROMArchiver = ROMArchiver.installed
    ) {
        self.locator = locator
        self.journal = journal
        self.tasks = tasks
        self.archiver = archiver
    }

    /// What can be done to the ROM: nil for a missing ROM, an OpenEmu ROM or another Platform's.
    public nonisolated static func action(for rom: LudeumROM) -> Action? {
        guard !rom.missing, rom.folderName != nil, rom.systemId == ROMFolder.ps2SystemId else { return nil }
        return rom.archived ? .unarchive : .archive
    }

    /// Queues the ROM's Archive or Unarchive. Once it's done, the Game's ROMs are checked again so
    /// the journal sees the change, then `finished` runs.
    public func start(_ rom: LudeumROM, of game: GameID, finished: @escaping @MainActor () -> Void = {}) {
        guard let action = Self.action(for: rom), let folder = locator.folder(of: rom), let name = rom.folderName else { return }
        let archiver = archiver
        let journal = journal
        let folders = locator.romFolders
        let done: @MainActor () -> Void = {
            try? journal?.checkROMsAgain(game, in: folders)
            finished()
        }
        switch action {
        case .archive:
            tasks.enqueue("Archiving \(name)", subject: .rom(rom.id)) { progress in
                try await archiver().archive(name, in: folder, progress: progress)
            } finished: {
                done()
            }
        case .unarchive:
            let archive = folder.url.appending(path: rom.fileName)
            tasks.enqueue("Unarchiving \(name)", subject: .rom(rom.id)) { progress in
                try await archiver().unarchive(archive, romName: name, in: folder, progress: progress)
            } finished: {
                done()
            }
        }
    }
}
