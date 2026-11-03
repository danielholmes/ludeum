import AppKit
import LudeumCore

/// Decoded Covers, the Library's genres and themes, and its LaunchBox ratings, kept in memory so screens open without
/// re-reading the cache. Covers are dropped when any Cover changes; a Game's facts when its record has been fetched again;
/// its LaunchBox rating when what it's found by changes, or a new dump is read.
@MainActor final class MemoryCache {
    /// Tile-sized Covers, up to a limit: past it, or when the system is short of memory, some are dropped and decoded
    /// again when next shown.
    private let covers: NSCache<NSNumber, DecodedCover> = {
        let covers = NSCache<NSNumber, DecodedCover>()
        covers.totalCostLimit = decodedCoversLimit
        return covers
    }()
    private var coverRevision = -1
    /// Linked Games' IGDB facts, by IGDB game id, each read from its cached record once and kept: a journal edit
    /// doesn't change them.
    private var facts: [Int64: GameFacts] = [:]
    /// The IGDB games read so far, including any IGDB has no record of.
    private var factsRead: Set<Int64> = []
    /// The read under way, so screens asking at once wait on the same one.
    private var factsLoad: Task<Void, Never>?
    /// Each Game's LaunchBox community rating (nil for none), with what it was found by: a Game is looked up again only
    /// once that changes (a rename, a new IGDB link, its facts read again), and every Game once a new dump is read.
    private var launchBoxScores: [GameID: (lookup: LaunchBoxLookup, score: CommunityScore?)] = [:]
    /// When the dump `launchBoxScores` were found in was read.
    private var launchBoxReadAt: Date?

    /// A Game's Cover if it's been loaded since the last Cover change, decoded for at least `pixels` on its long edge
    /// (any size, by default): `.some(nil)` is the placeholder.
    func cover(_ game: GameID, revision: Int, pixels: Int = 0) -> NSImage?? {
        if revision != coverRevision {
            covers.removeAllObjects()
            coverRevision = revision
        }
        guard let cover = covers.object(forKey: NSNumber(value: game)), cover.pixels >= pixels else { return nil }
        return .some(cover.image)
    }

    /// `pixels` is the long edge it was decoded for; the image is smaller when its source is.
    func store(cover: NSImage?, for game: GameID, revision: Int, pixels: Int) {
        guard revision == coverRevision else { return }
        // Its cost is its decoded size: four bytes a pixel.
        let bytes = cover.map { Int($0.size.width * $0.size.height) * 4 } ?? 0
        // A placeholder is the same at any size.
        covers.setObject(
            DecodedCover(image: cover, pixels: cover == nil ? .max : pixels), forKey: NSNumber(value: game), cost: bytes)
    }

    /// Every linked Game's IGDB facts, by IGDB game id. Only Games linked since the last ask are read, so an edit to
    /// the journal doesn't read every record again. A read that fails isn't kept, so the next ask tries again; until
    /// one works, the facts read so far are what's shown.
    func facts(_ services: Services) async -> [Int64: GameFacts] {
        guard let journal = services.journal, let igdb = services.igdb else { return [:] }
        // One read at a time: whoever asks meanwhile waits, then finds its Games already read. The read clears
        // `factsLoad` itself as it ends, so nobody waits on one that's over.
        while let factsLoad { await factsLoad.value }
        // A record fetched again since (by the launch refresh, an Import, a search) has its facts read again.
        factsRead.subtract(igdb.takeGamesFetched().map(Int64.init))
        guard let unread = try? journal.linkedIGDBGames().subtracting(factsRead), !unread.isEmpty else { return facts }
        let load = Task {
            defer { factsLoad = nil }
            guard let read = try? await LibraryFacts(igdb: igdb).byGame(Array(unread)) else { return }
            facts.merge(read) { _, new in new }
            factsRead.formUnion(unread)
        }
        factsLoad = load
        await load.value
        return facts
    }

    /// Every Game's LaunchBox community rating, by Game, its LaunchBox players' score: `facts` (by IGDB game id) give IGDB's
    /// alternative names and year for it. Games with none are absent. Only Games whose names, link or facts have changed
    /// since the last ask are looked up, off the main thread; on a failure, what was found before is what's shown.
    func launchBoxScores(_ services: Services, facts: [Int64: GameFacts]) async -> [GameID: CommunityScore] {
        guard let journal = services.journal, let launchBox = services.launchBox,
            let lookups = try? journal.launchBoxLookups(facts: facts)
        else { return [:] }
        let readAt = try? launchBox.readAt()
        if readAt != launchBoxReadAt {
            launchBoxScores = [:]
            launchBoxReadAt = readAt
        }
        let changed = lookups.filter { launchBoxScores[$0.key]?.lookup != $0.value }
        if !changed.isEmpty, let found = try? await offMain({ try launchBox.playerScores(changed) }), readAt == launchBoxReadAt {
            for (game, lookup) in changed { launchBoxScores[game] = (lookup, found[game]) }
        }
        // A deleted Game's is left out.
        var scores: [GameID: CommunityScore] = [:]
        for (game, entry) in launchBoxScores where lookups[game] != nil { scores[game] = entry.score }
        return scores
    }
}

/// How much memory decoded Covers may take: 256 MB, some five hundred at the usual tile size and over a hundred at the
/// largest.
private let decodedCoversLimit = 256 << 20

/// A Game's decoded Cover, or its placeholder (no image), as `NSCache` holds it.
private final class DecodedCover {
    let image: NSImage?
    /// The long edge it was decoded for.
    let pixels: Int

    init(image: NSImage?, pixels: Int) {
        self.image = image
        self.pixels = pixels
    }
}
