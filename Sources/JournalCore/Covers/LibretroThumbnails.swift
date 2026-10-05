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
/// Each system's file listing comes from GitHub (one request per repo, cached); images come from
/// `thumbnails.libretro.com`, which follows the repos' per-disc symlinks.
public final class LibretroThumbnails: Sendable {
    let cache: CacheStore
    let api: Throttle
    let maxAge: TimeInterval

    public init(
        cache: CacheStore, transport: HTTPTransport = URLSessionTransport(), clock: TimeSource = SystemTimeSource(),
        maxAge: TimeInterval = CacheStore.defaultMaxAge
    ) {
        self.cache = cache
        self.maxAge = maxAge
        api = Throttle(requestsPerSecond: 1, transport: transport, clock: clock)
    }

    /// The repos an OpenEmu system's ROMs are looked up in, in order. OpenEmu files Game Boy
    /// and Game Boy Color together.
    static let repos: [String: [String]] = [
        "openemu.system.gb": ["Nintendo_-_Game_Boy", "Nintendo_-_Game_Boy_Color"],
        "openemu.system.gba": ["Nintendo_-_Game_Boy_Advance"],
        "openemu.system.gc": ["Nintendo_-_GameCube"],
        "openemu.system.gg": ["Sega_-_Game_Gear"],
        "openemu.system.n64": ["Nintendo_-_Nintendo_64"],
        "openemu.system.nds": ["Nintendo_-_Nintendo_DS"],
        "openemu.system.nes": ["Nintendo_-_Nintendo_Entertainment_System"],
        "openemu.system.pcecd": ["NEC_-_PC_Engine_CD_-_TurboGrafx-CD"],
        "openemu.system.pce": ["NEC_-_PC_Engine_-_TurboGrafx_16"],
        "openemu.system.psp": ["Sony_-_PlayStation_Portable"],
        "openemu.system.psx": ["Sony_-_PlayStation"],
        "openemu.system.saturn": ["Sega_-_Saturn"],
        "openemu.system.scd": ["Sega_-_Mega-CD_-_Sega_CD"],
        "openemu.system.sg": ["Sega_-_Mega_Drive_-_Genesis"],
        "openemu.system.sms": ["Sega_-_Master_System_-_Mark_III"],
        "openemu.system.snes": ["Nintendo_-_Super_Nintendo_Entertainment_System"],
        "openemu.system.32x": ["Sega_-_32X"],
        "openemu.system.vb": ["Nintendo_-_Virtual_Boy"],
        "openemu.system.lynx": ["Atari_-_Lynx"],
        "openemu.system.2600": ["Atari_-_2600"],
        "openemu.system.ngp": ["SNK_-_Neo_Geo_Pocket_Color"],
        "openemu.system.ws": ["Bandai_-_WonderSwan_Color"],
    ]

    static let folders = ["Named_Boxarts", "Named_Snaps", "Named_Titles"]

    /// A `.gbc` file, or GoodTools' `[C]` (Color) flag.
    static func isColor(_ fileName: String) -> Bool {
        fileName.lowercased().hasSuffix(".gbc") || fileName.contains("[C]")
    }

    /// Looks a ROM up in its system's listings. Nil for a system libretro has no repo for.
    public func names(system: String, fileName: String, titles: [String]) async throws -> LibretroNames? {
        guard var repos = Self.repos[system] else { return nil }
        // A Game Boy Color ROM filed under Game Boy looks in Game Boy Color first, so a Color game
        // doesn't take the box of a Game Boy game with the same name.
        if system == "openemu.system.gb", Self.isColor(fileName) { repos.reverse() }
        var listings: [(repo: String, folders: [String: Set<String>])] = []
        for repo in repos { listings.append((repo, try await listing(repo))) }
        // An exact name in any repo beats a title match; within each step, the first repo wins (Game Boy
        // before Game Boy Color, unless the ROM is a Color one).
        func find(_ folder: String) -> String? {
            let steps: [(Set<String>) -> String?] = [
                { LibretroLookup.exact(fileName: fileName, in: $0) },
                { LibretroLookup.fuzzy(fileName: fileName, titles: titles, in: $0) },
            ]
            for step in steps {
                for (repo, folders) in listings {
                    if let name = step(folders[folder] ?? []) {
                        return "\(repo.replacingOccurrences(of: "_", with: " "))/\(folder)/\(name).png"
                    }
                }
            }
            return nil
        }
        return LibretroNames(boxart: find("Named_Boxarts"), snap: find("Named_Snaps"), title: find("Named_Titles"))
    }

    /// An image by its path, from the cache or downloaded the first time.
    public func image(_ path: String) async throws -> URL {
        try await cache.image(at: "libretro/\(path)") {
            let url = URL(string: "https://thumbnails.libretro.com")!.appending(path: path)
            let (data, response) = try await api.send(URLRequest(url: url))
            guard response.statusCode == 200 else { throw HTTPStatusError(status: response.statusCode, url: url) }
            return data
        }
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
