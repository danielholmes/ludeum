import AppKit
import Foundation
import JournalCore

/// Previews, and with `--write` runs, a Sync from a scratch journal into a COPY of an OpenEmu
/// library. Never point it at the live library.
func syncRun(library: URL, journalFolder: URL, write: Bool, igdb: IGDBClient) async throws {
    let journal = try JournalStore(directory: journalFolder)
    let cache = try CacheStore(directory: cacheDirectory)
    let covers = Covers(journal: journal, cache: cache, igdb: igdb, libretro: LibretroThumbnails(cache: cache))
    let sync = OpenEmuSync(
        journal: journal, covers: covers, backupFolder: journalFolder.appending(path: "OpenEmu backups"),
        isOpenEmuRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: "org.openemu.OpenEmu").isEmpty })
    let preview = try await sync.preview(library: library)
    print("Guards failing: \(preview.failedGuards.map(\.rawValue))")
    print("Stars: \(preview.starChanges.count) Games; collections: \(preview.collectionChanges.count) changed")
    for c in preview.collectionChanges {
        print("  \(c.isNew ? "new " : "")\(c.name)\(c.renamedFrom.map { " (was \($0))" } ?? ""): +\(c.added) -\(c.removed)")
    }
    print("Other collections: \(preview.otherCollections.map { "\($0.name) (\($0.gameCount))" })")
    print("Covers: \(preview.coversAdded.count) added, \(preview.coversReplaced.count) replaced, \(preview.coversSkipped.count) skipped")
    print("Not synced (Duplicate Versions): \(preview.notSynced.map(\.name))")
    guard write else { return }
    let result = try await sync.sync(library: library, deleting: [])
    print("Synced. OpenEmu backup: \(result.backupName)")
}
