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
/// Each Platform's file listing comes from GitHub (one request per repo, cached), else from the CDN; images come from
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
    private let boxartTitles = Mutex<[String: Task<LibretroLookup.TitleIndex, any Error>]>([:])

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

    /// The repo a Game with no ROM looks for its Box art in, by title: its Platform's ROM folder's, else the one for a
    /// Platform with no ROM folder. Nil for a Platform libretro has none for.
    static func boxartRepo(platform: Int64) -> String? {
        ROMPlatform.all[platform]?.libretroRepo ?? reposForPlatformsWithNoROMFolder[platform]
    }

    /// The repos for Platforms with no ROM folder (`ROMPlatform.libretroRepo` has the rest), by IGDB platform id. Some
    /// are thin (PS3, PS4 and the Xbox 360 have a few dozen boxes); PC, Mac, the Switch and the Xbox One and later have
    /// none. IGDB splits some Platforms libretro doesn't: the Neo Geo MVS and AES (79, 80) share one repo, as do the 3DS
    /// and New 3DS (37, 137).
    static let reposForPlatformsWithNoROMFolder: [Int64: String] = [
        9: "Sony_-_PlayStation_3", 11: "Microsoft_-_Xbox", 12: "Microsoft_-_Xbox_360", 13: "DOS", 15: "Commodore_-_64",
        16: "Commodore_-_Amiga", 23: "Sega_-_Dreamcast", 25: "Amstrad_-_CPC", 26: "Sinclair_-_ZX_Spectrum", 27: "Microsoft_-_MSX",
        30: "Sega_-_32X", 37: "Nintendo_-_Nintendo_3DS", 41: "Nintendo_-_Wii_U", 48: "Sony_-_PlayStation_4",
        50: "The_3DO_Company_-_3DO", 51: "Nintendo_-_Family_Computer_Disk_System", 57: "Bandai_-_WonderSwan", 59: "Atari_-_2600",
        60: "Atari_-_7800", 61: "Atari_-_Lynx", 62: "Atari_-_Jaguar", 63: "Atari_-_ST", 65: "Atari_-_8-bit_Family",
        66: "Atari_-_5200", 67: "Mattel_-_Intellivision", 68: "Coleco_-_ColecoVision", 70: "GCE_-_Vectrex",
        71: "Commodore_-_VIC-20", 77: "Sharp_-_X1", 79: "SNK_-_Neo_Geo", 80: "SNK_-_Neo_Geo", 84: "Sega_-_SG-1000",
        86: "NEC_-_PC_Engine_-_TurboGrafx_16", 87: "Nintendo_-_Virtual_Boy", 90: "Commodore_-_PET", 94: "Commodore_-_Plus-4",
        114: "Commodore_-_CD32", 117: "Philips_-_CD-i", 119: "SNK_-_Neo_Geo_Pocket", 120: "SNK_-_Neo_Geo_Pocket_Color",
        121: "Sharp_-_X68000", 123: "Bandai_-_WonderSwan_Color", 125: "NEC_-_PC-88", 127: "Fairchild_-_Channel_F",
        128: "NEC_-_PC_Engine_SuperGrafx", 133: "Magnavox_-_Odyssey2", 136: "SNK_-_Neo_Geo_CD", 137: "Nintendo_-_Nintendo_3DS",
        149: "NEC_-_PC-98", 156: "Thomson_-_MOTO", 158: "Commodore_-_CDTV", 159: "Nintendo_-_Nintendo_DSi",
        166: "Nintendo_-_Pokemon_Mini", 274: "NEC_-_PC-FX", 306: "Nintendo_-_Satellaview", 339: "Sega_-_PICO",
        373: "Sinclair_-_ZX_81", 376: "Epoch_-_Super_Cassette_Vision", 379: "Tiger_-_Game.com", 380: "Casio_-_Loopy",
        412: "LeapFrog_-_Leapster_Learning_Game_System", 415: "Watara_-_Supervision", 416: "Nintendo_-_Nintendo_64DD",
        438: "Arduboy_Inc_-_Arduboy", 439: "VTech_-_V.Smile", 473: "Emerson_-_Arcadia_2001", 480: "Funtech_-_Super_Acan",
        506: "Amstrad_-_GX4000",
    ]

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
    /// `regions`' box first, else USA, Europe, Japan. Nil when nothing matches, or for a Platform libretro has no repo for.
    public func boxart(platform: Int64, titles: [String], regions: Set<NameRegion>) async throws -> String? {
        guard let repo = Self.boxartRepo(platform: platform) else { return nil }
        let byTitle = try await boxartTitleIndex(repo)
        return LibretroLookup.fuzzy(titles: titles, regions: regions, in: byTitle).map { Self.path(repo, "Named_Boxarts", $0) }
    }

    private func boxartTitleIndex(_ repo: String) async throws -> LibretroLookup.TitleIndex {
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

    /// From GitHub, else, when GitHub refuses, from the CDN's own folder indexes. GitHub allows 60 requests an hour without
    /// an account, shared by everything on the connection, so it can refuse for an hour at a time.
    private func fetchListing(_ repo: String) async throws -> Data {
        let folders: [String: [String]]
        do {
            folders = try await gitHubListing(repo)
        } catch {
            folders = try await cdnListing(repo)
        }
        return try JSONEncoder().encode(folders)
    }

    /// Each folder's index page on the CDN, whose links are its images' names, percent-encoded. A folder the CDN hasn't
    /// got is empty, but a repo it has none of throws, as GitHub's refusal did, rather than be kept as empty.
    private func cdnListing(_ repo: String) async throws -> [String: [String]] {
        var folders: [String: [String]] = [:]
        var missing: URL?
        for folder in Self.folders {
            let url = URL(string: "https://thumbnails.libretro.com")!
                .appending(path: "\(repo.replacingOccurrences(of: "_", with: " "))/\(folder)/")
            let (data, response) = try await transport.send(URLRequest(url: url))
            if response.statusCode == 404 {
                missing = url
                continue
            }
            guard response.statusCode == 200 else { throw HTTPStatusError(status: response.statusCode, url: url) }
            folders[folder] = String(decoding: data, as: UTF8.self).matches(of: #/href="([^"/?]+)\.png"/#)
                .compactMap { String($0.1).removingPercentEncoding }
        }
        if folders.isEmpty, let missing { throw HTTPStatusError(status: 404, url: missing) }
        return folders
    }

    private func gitHubListing(_ repo: String) async throws -> [String: [String]] {
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
        return folders
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
