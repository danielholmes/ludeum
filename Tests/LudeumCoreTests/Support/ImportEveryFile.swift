import Foundation

@testable import LudeumCore

extension Import {
    /// An Import that adds every file in the folders as a ROM: tests that set up ROMs by putting files in a ROM folder, as
    /// every Import did before the journal said which ROMs there are (ADR 0016).
    func run(
        addingEveryFileIn folders: [ROMFolder], writing: @Sendable () async -> Void = {}, wrote: @Sendable () async -> Void = {}
    ) async throws -> ImportResult {
        let every = Set(
            folders.flatMap { folder in
                ((try? folder.scan()) ?? []).map { StrayFile.Key(platformId: folder.platformId, name: $0.name) }
            })
        return try await run(romFolders: folders, adding: every, writing: writing, wrote: wrote)
    }
}
