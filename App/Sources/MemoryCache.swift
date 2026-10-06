import AppKit
import LudeumCore

/// Decoded Covers and the Library's genres and themes, kept in memory so screens open without re-reading
/// the cache. Covers are dropped when any Cover changes; genres when the journal does.
@MainActor final class MemoryCache {
    /// Tile-sized Covers, up to a limit: past it, or when the system is short of memory, some are dropped and decoded
    /// again when next shown.
    private let covers: NSCache<NSNumber, DecodedCover> = {
        let covers = NSCache<NSNumber, DecodedCover>()
        covers.totalCostLimit = 256 << 20
        return covers
    }()
    private var coverRevision = -1
    private var facts: [Int64: GameFacts]?
    private var factsRevision = -1
    /// The load under way, so every screen asking at one revision waits on the same one.
    private var factsLoad: (revision: Int, task: Task<[Int64: GameFacts]?, Never>)?

    /// A Game's Cover if it's been loaded since the last Cover change: `.some(nil)` is the placeholder.
    func cover(_ game: GameID, revision: Int) -> NSImage?? {
        if revision != coverRevision {
            covers.removeAllObjects()
            coverRevision = revision
        }
        return covers.object(forKey: NSNumber(value: game)).map(\.image)
    }

    func store(cover: NSImage?, for game: GameID, revision: Int) {
        guard revision == coverRevision else { return }
        // Its cost is its decoded size: four bytes a pixel.
        let bytes = cover.map { Int($0.size.width * $0.size.height) * 4 } ?? 0
        covers.setObject(DecodedCover(image: cover), forKey: NSNumber(value: game), cost: bytes)
    }

    /// Every linked Game's IGDB genres and themes, read once per journal revision. A load that fails isn't kept, so the
    /// next ask tries again; until one works, the facts last read are what's shown.
    func facts(_ services: Services) async -> [Int64: GameFacts] {
        let revision = services.changes.revision
        if let facts, factsRevision == revision { return facts }
        guard let journal = services.journal, let igdb = services.igdb else { return [:] }
        let load: Task<[Int64: GameFacts]?, Never>
        if let factsLoad, factsLoad.revision == revision {
            load = factsLoad.task
        } else {
            load = Task {
                guard let ids = try? journal.library(LibraryFilter(), sort: .name, ascending: true).compactMap(\.igdbGameId) else {
                    return nil
                }
                return try? await LibraryFacts(igdb: igdb).byGame(ids)
            }
            factsLoad = (revision, load)
        }
        let loaded = await load.value
        if factsLoad?.task == load { factsLoad = nil }
        guard let loaded else { return facts ?? [:] }
        // A load for an older revision that finishes late doesn't replace a newer one's.
        if revision > factsRevision {
            facts = loaded
            factsRevision = revision
        }
        return loaded
    }
}

/// A Game's decoded Cover, or its placeholder (no image), as `NSCache` holds it.
private final class DecodedCover {
    let image: NSImage?
    init(image: NSImage?) { self.image = image }
}
