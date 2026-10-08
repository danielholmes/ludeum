import Foundation
import Synchronization

/// The libretro-thumbnails names found for one ROM, each a path on `thumbnails.libretro.com`
/// such as "Nintendo - Game Boy Color/Named_Boxarts/Tetris DX (World).png".
public struct LibretroNames: Sendable, Equatable {
    public var boxart: String?
    public var snap: String?
    public var title: String?

    public init(boxart: String? = nil, snap: String? = nil, title: String? = nil) {
        self.boxart = boxart
        self.snap = snap
        self.title = title
    }
}

/// libretro-thumbnails: box scans, snaps and title screens named by No-Intro and Redump names.
/// Each Platform's file listing comes from GitHub (one request per repo, cached); images come from
/// `thumbnails.libretro.com`, which follows the repos' per-disc symlinks, else from GitHub when the CDN lags.
/// Made once and shared, as it holds GitHub's rate limiter; the CDN's images don't wait their turn at it, so a
/// screenful of Covers loads together.
public final class LibretroThumbnails: Sendable {
    let cache: CacheStore
    let transport: HTTPTransport
    let api: Throttle
    let maxAge: TimeInterval
    /// Each repo's Box art names by title key, for Games with no ROM: worked out the first time one's Cover is shown and
    /// kept, as it's looked up again each time. One that fails isn't kept, so the next Cover tries again.
    private let boxartTitles = Mutex<[String: Task<[String: [String]], any Error>]>([:])

    public init(
        cache: CacheStore, transport: HTTPTransport = URLSessionTransport(), clock: TimeSource = SystemTimeSource(),
        maxAge: TimeInterval = CacheStore.defaultMaxAge
    ) {
        self.cache = cache
        self.transport = transport
        self.maxAge = maxAge
        api = Throttle(requestsPerSecond: 1, transport: transport, clock: clock)
    }

    static let folders = ["Named_Boxarts", "Named_Snaps", "Named_Titles"]

    /// Looks a ROM up in its Platform's listings (`ROMPlatform.libretroRepo`). Nil for a Platform with no ROM folder,
    /// whose ROMs libretro isn't asked about.
    public func names(platform: Int64, fileName: String, titles: [String]) async throws -> LibretroNames? {
        var listing = try await listing(platform: platform)
        guard listing.repo != nil else { return nil }
        return listing.names(fileName: fileName, titles: titles)
    }

    /// A Platform's listings, read once to look up any number of its ROMs. One with no ROM folder, whose ROMs libretro
    /// isn't asked about, has an empty one that finds nothing.
    func listing(platform: Int64) async throws -> LibretroListing {
        guard let repo = ROMPlatform.all[platform]?.libretroRepo else { return LibretroListing(repo: nil, folders: [:]) }
        return LibretroListing(repo: repo, folders: try await listing(repo).mapValues(LibretroFolder.init))
    }

    /// A Game with no ROM's Box art, which has no file name to look up: a title match on each of `titles` in turn,
    /// `regions`' box first, else USA, Europe, Japan. Nil when nothing matches, or for a Platform with no ROM folder.
    public func boxart(platform: Int64, titles: [String], regions: Set<NameRegion>) async throws -> String? {
        guard let repo = ROMPlatform.all[platform]?.libretroRepo else { return nil }
        let byTitle = try await boxartTitleIndex(repo)
        return LibretroLookup.fuzzy(titles: titles, regions: regions, in: byTitle).map { Self.path(repo, "Named_Boxarts", $0) }
    }

    private func boxartTitleIndex(_ repo: String) async throws -> [String: [String]] {
        let task = boxartTitles.withLock { tasks in
            if let task = tasks[repo] { return task }
            let task = Task { LibretroLookup.titleIndex(try await listing(repo)["Named_Boxarts"] ?? []) }
            tasks[repo] = task
            return task
        }
        do {
            return try await task.value
        } catch {
            boxartTitles.withLock { if $0[repo] == task { $0[repo] = nil } }
            throw error
        }
    }

    /// An image's path on the CDN, e.g. "Nintendo - Game Boy/Named_Boxarts/Tetris (World).png".
    static func path(_ repo: String, _ folder: String, _ name: String) -> String {
        "\(repo.replacingOccurrences(of: "_", with: " "))/\(folder)/\(name).png"
    }

    /// An image by its path, from the cache or downloaded the first time. The CDN can lag behind the
    /// repos, so an image it hasn't got comes from GitHub, as long as it's a PNG and not a per-disc symlink.
    public func image(_ path: String) async throws -> URL {
        try await cache.image(at: "libretro/\(path)") {
            let url = URL(string: "https://thumbnails.libretro.com")!.appending(path: path)
            let (data, response) = try await transport.send(URLRequest(url: url))
            if response.statusCode == 200 { return data }
            guard response.statusCode == 404, let fromGitHub = try await fromGitHub(path) else {
                throw HTTPStatusError(status: response.statusCode, url: url)
            }
            return fromGitHub
        }
    }

    /// The image from the repo itself, or nil when it isn't there or isn't a PNG.
    private func fromGitHub(_ path: String) async throws -> Data? {
        let parts = path.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let repo = parts[0].replacingOccurrences(of: " ", with: "_")
        let url = URL(string: "https://raw.githubusercontent.com/libretro-thumbnails")!.appending(path: "\(repo)/master/\(parts[1])")
        let (data, response) = try await api.send(URLRequest(url: url))
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        return response.statusCode == 200 && data.starts(with: png) ? data : nil
    }

    static func listingKey(_ repo: String) -> String { "libretro:listing:\(repo)" }

    /// A repo's image names (without `.png`) by folder.
    private func listing(_ repo: String) async throws -> [String: Set<String>] {
        let payloads = try await cache.resolve([repo], key: Self.listingKey, maxAge: maxAge, batchSize: 1) { _ in
            [repo: try await fetchListing(repo)]
        }
        let decoded = try JSONDecoder().decode([String: [String]].self, from: payloads[repo]!)
        return decoded.mapValues(Set.init)
    }

    private func fetchListing(_ repo: String) async throws -> Data {
        let url = URL(string: "https://api.github.com/repos/libretro-thumbnails/\(repo)/git/trees/master?recursive=1")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await api.send(request)
        guard response.statusCode == 200 else { throw HTTPStatusError(status: response.statusCode, url: url) }
        struct Tree: Decodable {
            struct Entry: Decodable { let path: String }
            let tree: [Entry]
        }
        var folders: [String: [String]] = [:]
        for entry in try JSONDecoder().decode(Tree.self, from: data).tree {
            let parts = entry.path.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, Self.folders.contains(parts[0]), parts[1].hasSuffix(".png") else { continue }
            folders[parts[0], default: []].append(String(parts[1].dropLast(4)))
        }
        return try JSONEncoder().encode(folders)
    }
}

/// One Platform's libretro-thumbnails listings, by folder.
struct LibretroListing: Sendable {
    /// Nil for a Platform libretro isn't asked about.
    let repo: String?
    var folders: [String: LibretroFolder]

    /// The ROM's name in each folder: an exact name beats a title match.
    mutating func names(fileName: String, titles: [String]) -> LibretroNames {
        guard let repo else { return LibretroNames() }
        var paths: [String: String] = [:]
        for folder in LibretroThumbnails.folders {
            guard let name = folders[folder]?.find(fileName: fileName, titles: titles) else { continue }
            paths[folder] = LibretroThumbnails.path(repo, folder, name)
        }
        return LibretroNames(boxart: paths["Named_Boxarts"], snap: paths["Named_Snaps"], title: paths["Named_Titles"])
    }
}
