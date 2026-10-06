import Foundation

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
        guard let repo = ROMPlatform.all[platform]?.libretroRepo else { return nil }
        let folders = try await listing(repo)
        // An exact name beats a title match.
        func find(_ folder: String) -> String? {
            let names = folders[folder] ?? []
            guard
                let name = LibretroLookup.exact(fileName: fileName, in: names)
                    ?? LibretroLookup.fuzzy(fileName: fileName, titles: titles, in: names)
            else { return nil }
            return "\(repo.replacingOccurrences(of: "_", with: " "))/\(folder)/\(name).png"
        }
        return LibretroNames(boxart: find("Named_Boxarts"), snap: find("Named_Snaps"), title: find("Named_Titles"))
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
