import Foundation

/// Archive, Unarchive and Compact: a ROM folder ROM packed into a `.7z`, unpacked so it can be Played, or packed into
/// the archive its Emulator opens directly, as a Background task. Archive and Unarchive are for the Platforms whose
/// ROMs can be Archived (`ROMPlatform.all`); Compact is for the Platforms whose Emulator opens an archive.
@MainActor public struct ROMArchiving {
    public enum Action: Sendable, Equatable {
        case archive, unarchive, compact
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

    /// What can be done to the ROM: Compact while it isn't yet in its Platform's compact extension, Archive or
    /// Unarchive on a Platform whose ROMs can be Archived, and nil for a missing ROM or any other.
    public nonisolated static func action(for rom: LudeumROM) -> Action? {
        guard !rom.missing, let platform = ROMPlatform.all[rom.platformId] else { return nil }
        if platform.compactExtension != nil { return platform.canCompact(fileName: rom.fileName) ? .compact : nil }
        guard platform.archiving != nil else { return nil }
        return rom.archived ? .unarchive : .archive
    }

    /// Whether the ROM's Unarchive unpacks its one file loose, rather than everything into a folder named after it.
    public nonisolated static func unarchivesToOneFile(_ rom: LudeumROM) -> Bool {
        ROMPlatform.all[rom.platformId]?.archiving == .singleFile
    }

    /// The file a Compact makes, e.g. `Tetris (World).7z`; nil when the ROM can't be Compacted.
    public nonisolated static func compactFileName(for rom: LudeumROM) -> String? {
        guard action(for: rom) == .compact, let ext = ROMPlatform.all[rom.platformId]?.compactExtension else { return nil }
        return "\(rom.folderName).\(ext)"
    }

    /// Queues the ROM's Archive, Unarchive or Compact. Once it ends, the ROM is checked again so the journal sees whatever
    /// changed, then `finished` runs: also after a failure or a Stop, which can come once its files have already moved.
    public func start(_ rom: LudeumROM, finished: @escaping @MainActor () -> Void = {}) {
        guard let action = Self.action(for: rom), let folder = locator.folder(of: rom) else { return }
        let name = rom.folderName
        let archiver = archiver
        let journal = journal
        let done: @MainActor () -> Void = {
            try? journal?.checkROMAgain(rom.id, in: folder)
            finished()
        }
        switch action {
        case .archive:
            tasks.enqueue("Archiving \(name)", subject: .rom(rom.id)) { progress in
                try await archiver().archive(name, in: folder, progress: progress)
            } ended: {
                done()
            }
        case .unarchive:
            let archive = folder.url.appending(path: rom.fileName)
            tasks.enqueue("Unarchiving \(name)", subject: .rom(rom.id)) { progress in
                try await archiver().unarchive(archive, romName: name, in: folder, progress: progress)
            } ended: {
                done()
            }
        case .compact:
            tasks.enqueue("Compacting \(name)", subject: .rom(rom.id)) { progress in
                try await archiver().compact(name, in: folder, progress: progress)
            } ended: {
                done()
            }
        }
    }
}
