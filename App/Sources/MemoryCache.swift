import AppKit
import LudeumCore

/// Decoded Covers and the Library's genres and themes, kept in memory so screens open without re-reading
/// the cache. Covers are dropped when any Cover changes; genres when the journal does.
@MainActor final class MemoryCache {
    private var covers: [GameID: NSImage?] = [:]
    private var coverRevision = -1
    private var facts: [Int64: GameFacts]?
    private var factsRevision = -1

    /// A Game's Cover if it's been loaded since the last Cover change: `.some(nil)` is the placeholder.
    func cover(_ game: GameID, revision: Int) -> NSImage?? {
        if revision != coverRevision {
            covers = [:]
            coverRevision = revision
        }
        return covers[game]
    }

    func store(cover: NSImage?, for game: GameID, revision: Int) {
        guard revision == coverRevision else { return }
        covers[game] = .some(cover)
    }

    /// Every linked Game's IGDB genres and themes, read once per journal revision.
    func facts(_ services: Services) async -> [Int64: GameFacts] {
        let revision = services.changes.revision
        if let facts, factsRevision == revision { return facts }
        guard let journal = services.journal, let igdb = services.igdb else { return [:] }
        let ids = (try? journal.library(LibraryFilter(), sort: .name, ascending: true).compactMap(\.igdbGameId)) ?? []
        let loaded = (try? await LibraryFacts(igdb: igdb).byGame(ids)) ?? [:]
        facts = loaded
        factsRevision = revision
        return loaded
    }
}
