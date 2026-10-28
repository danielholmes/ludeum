import Foundation

/// The Ludeum folder, `~/Library/Application Support/Ludeum/`: the one place Ludeum keeps what it owns (ADR 0010).
/// The live journal sits in it, beside the Data folder: what must survive losing this Mac, which I link into Dropbox by
/// hand. There are no settings for any of these locations. The cache is elsewhere (`CacheStore.defaultDirectory`).
///
/// The Emulators Ludeum installs sit beside the journal, with what they keep for themselves (ADR 0024).
///
/// ```
/// Ludeum/
///   journal.sqlite
///   Emulators/DuckStation.app
///   Data/
///     ROMs/<Platform>/
///     Attachments/<Platform>/<Game>/
///     Backups/
///     Emulators/DuckStation/Save States/
///     Emulators/DuckStation/Memory Cards/
///     Emulators/DuckStation/BIOS/, Game Settings/, Input Profiles/, Screenshots/
///     OpenEmu Battery Saves archive/
/// ```
public struct LudeumFolder: Sendable, Equatable {
    public let url: URL
    /// The Data folder: normally `Data/` in the Ludeum folder, often a link into Dropbox.
    public let data: URL

    /// `data` stands in for the Data folder, in tests.
    public init(url: URL, data: URL? = nil) {
        self.url = url
        self.data = data ?? url.appending(path: "Data", directoryHint: .isDirectory)
    }

    public static let standard = LudeumFolder(
        url: URL.applicationSupportDirectory.appending(path: "Ludeum", directoryHint: .isDirectory))

    /// Where the ROM folders are, one per Platform.
    public var roms: URL { data.appending(path: "ROMs", directoryHint: .isDirectory) }

    public var backups: URL { data.appending(path: "Backups", directoryHint: .isDirectory) }

    /// Where Attachments' files are, in a folder per Game under one per Platform (ADR 0014). Created when first needed.
    public var attachments: URL { data.appending(path: "Attachments", directoryHint: .isDirectory) }

    /// Where the Emulators Ludeum installs are kept, with what they keep for themselves: outside the Data folder, as
    /// they can be installed again.
    public var emulators: URL { url.appending(path: "Emulators", directoryHint: .isDirectory) }

    /// The DuckStation Ludeum installs (ADR 0024).
    public var duckStationApp: URL { emulators.appending(path: "DuckStation.app", directoryHint: .isDirectory) }

    /// One of the folders DuckStation keeps in the Data folder, under `Emulators/DuckStation/`, where its Standing
    /// settings point it. Made before every launch Ludeum gives it.
    public func duckStation(_ folder: DuckStationFolder) -> URL {
        data.appending(path: "Emulators/DuckStation/\(folder.name)", directoryHint: .isDirectory)
    }

    /// DuckStation's save states, under its own file names.
    public var duckStationSaveStates: URL { duckStation(.saveStates) }

    /// DuckStation's memory cards, named as it names them.
    public var duckStationMemoryCards: URL { duckStation(.memoryCards) }

    /// Where the since-removed `migrate-openemu` copied OpenEmu's Game saves, keeping its `<Core>/Battery Saves/` layout.
    public var batterySaveArchive: URL { data.appending(path: "OpenEmu Battery Saves archive", directoryHint: .isDirectory) }

    /// A Platform's ROM folder, named for it under `ROMs/`. Nil for a Platform without one. Created when first needed.
    public func romFolder(platform: Int64) -> URL? {
        ROMPlatform.all[platform].map { roms.appending(path: $0.folderName, directoryHint: .isDirectory) }
    }

    /// Every ROM folder an Import reads: one per Platform that has one, by IGDB platform id.
    public var romFolders: [ROMFolder] {
        ROMPlatform.all.keys.sorted().compactMap { id in romFolder(platform: id).flatMap { ROMFolder.platform(id, $0) } }
    }

    /// Nothing works until the Data folder is found. Returns where it resolves to, through any link, once `ROMs/`
    /// and `Backups/` are in it (made if they're missing). Never makes the Data folder itself: a missing one would
    /// otherwise be quietly replaced by an empty folder that isn't in Dropbox.
    @discardableResult
    public func checkData() throws(DataFolderMissing) -> URL {
        let files = FileManager.default
        var isDirectory: ObjCBool = false
        guard files.fileExists(atPath: data.path(percentEncoded: false), isDirectory: &isDirectory), isDirectory.boolValue else {
            let path = data.path(percentEncoded: false)
            let link = try? files.destinationOfSymbolicLink(atPath: path.hasSuffix("/") ? String(path.dropLast()) : path)
            throw DataFolderMissing(data: data, linksTo: link, isFile: files.fileExists(atPath: path) && link == nil)
        }
        do {
            for folder in [roms, backups] where !files.fileExists(atPath: folder.path(percentEncoded: false)) {
                try files.createDirectory(at: folder, withIntermediateDirectories: false)
            }
        } catch {
            throw DataFolderMissing(data: data, linksTo: nil, isFile: false, underlying: String(describing: error))
        }
        return data.resolvingSymlinksInPath()
    }
}

/// The Data folder can't be found. `remedy` says how to fix it: the app's blocking sheet and every `ludeum-import`
/// command show the same words.
public struct DataFolderMissing: Error, Equatable, CustomStringConvertible {
    public let data: URL
    /// Where the Data folder links to, when it's a link to somewhere that isn't there.
    public let linksTo: String?
    let isFile: Bool
    var underlying: String? = nil

    public var remedy: String {
        let path = data.path(percentEncoded: false)
        let unslashed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let problem =
            if let underlying {
                "Ludeum couldn't make the ROMs and Backups folders in its Data folder, \(path): \(underlying)."
            } else if let linksTo {
                "Ludeum's Data folder, \(path), links to \(linksTo), which can't be found. Is Dropbox running?"
            } else if isFile {
                "Ludeum's Data folder, \(path), is a file, not a folder."
            } else {
                "Ludeum can't find its Data folder, \(path)."
            }
        return """
            \(problem) It holds the ROM folders and Backups, so nothing works without it. \
            Create that folder, or link it to where they're kept: ln -s ~/Dropbox/games/Ludeum "\(unslashed)"
            """
    }

    public var description: String { remedy }
}
