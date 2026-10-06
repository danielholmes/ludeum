import AppKit
import LudeumCore

/// Decoded Covers and the Library's genres and themes, kept in memory so screens open without re-reading
/// the cache. Covers are dropped when any Cover changes; facts when the cache refresh has fetched records again.
@MainActor final class MemoryCache {
    /// Tile-sized Covers, up to a limit: past it, or when the system is short of memory, some are dropped and decoded
    /// again when next shown.
    private let covers: NSCache<NSNumber, DecodedCover> = {
        let covers = NSCache<NSNumber, DecodedCover>()
        covers.totalCostLimit = 256 << 20
        return covers
    }()
    private var coverRevision = -1
    /// Linked Games' IGDB facts, by IGDB game id, each read from its cached record once and kept: a journal edit
    /// doesn't change them.
    private var facts: [Int64: GameFacts] = [:]
    /// The IGDB games read so far, including any IGDB has no record of.
    private var factsRead: Set<Int64> = []
    /// Counts `factsChanged`, so a read begun before one isn't kept after it.
    private var factsDrops = 0
    /// The read under way, so screens asking at once wait on the same one.
    private var factsLoad: Task<Void, Never>?

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

    /// Every linked Game's IGDB facts, by IGDB game id. Only Games linked since the last ask are read, so an edit to
    /// the journal doesn't read every record again. A read that fails isn't kept, so the next ask tries again; until
    /// one works, the facts read so far are what's shown.
    func facts(_ services: Services) async -> [Int64: GameFacts] {
        guard let journal = services.journal, let igdb = services.igdb else { return [:] }
        // One read at a time: whoever asks meanwhile waits, then finds its Games already read.
        while let factsLoad { await factsLoad.value }
        guard let unread = try? journal.linkedIGDBGames().subtracting(factsRead), !unread.isEmpty else { return facts }
        let drops = factsDrops
        let load = Task {
            guard let read = try? await LibraryFacts(igdb: igdb).byGame(Array(unread)), drops == factsDrops else { return }
            facts.merge(read) { _, new in new }
            factsRead.formUnion(unread)
        }
        factsLoad = load
        await load.value
        factsLoad = nil
        return facts
    }

    /// The cache refresh has fetched records again, so their facts are read afresh.
    func factsChanged() {
        facts = [:]
        factsRead = []
        factsDrops += 1
    }
}

/// A Game's decoded Cover, or its placeholder (no image), as `NSCache` holds it.
private final class DecodedCover {
    let image: NSImage?
    init(image: NSImage?) { self.image = image }
}
