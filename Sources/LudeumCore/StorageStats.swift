import Foundation
import GRDB

/// How much room everything Ludeum keeps takes up, measured from the files themselves each time: their logical sizes,
/// so a file Dropbox keeps online-only counts in full. Hidden files are left out, as an Import leaves them out.
public struct StorageStats: Sendable, Equatable {
    /// One row per Platform group with a ROM folder that has anything in it, largest first.
    public var platforms: [PlatformStorage] = []
    public var backups: Int64 = 0
    /// The battery saves archived from OpenEmu.
    public var batterySaves: Int64 = 0
    /// The live journal, outside the Data folder.
    public var journal: Int64 = 0
    /// What can always be fetched again, outside the Ludeum folder.
    public var cache: Int64 = 0

    /// What I keep in Dropbox.
    public var dataFolder: Int64 { platforms.reduce(0) { $0 + $1.total } + backups + batterySaves }
    public var total: Int64 { dataFolder + journal + cache }

    /// Measures it all. Slow for a big library: run it off the main thread.
    public static func measure(_ folder: LudeumFolder, journal: LudeumStore?, cache: URL) -> StorageStats {
        var stats = StorageStats()
        let missing = (try? journal?.missingROMCounts()) ?? [:]
        var rows: [Int64: PlatformStorage] = [:]
        for romFolder in folder.romFolders {
            guard var measured = PlatformStorage.measure(romFolder) else { continue }
            measured.missing = missing[romFolder.platformId] ?? 0
            rows[measured.id] = rows[measured.id].map { $0.adding(measured) } ?? measured
        }
        stats.platforms = rows.values.sorted { $0.total > $1.total }
        stats.backups = Sizes.total(in: folder.backups)
        stats.batterySaves = Sizes.total(in: folder.batterySaveArchive)
        stats.journal = ["journal.sqlite", "journal.sqlite-wal", "journal.sqlite-shm"]
            .reduce(0) { $0 + Sizes.size(of: folder.url.appending(path: $1)) }
        stats.cache = Sizes.total(in: cache)
        return stats
    }
}

/// A count of ROMs and the room their files take.
public struct ROMTally: Sendable, Equatable {
    public var count = 0
    public var bytes: Int64 = 0

    public init(count: Int = 0, bytes: Int64 = 0) {
        self.count = count
        self.bytes = bytes
    }

    static func + (a: Self, b: Self) -> Self { .init(count: a.count + b.count, bytes: a.bytes + b.bytes) }
}

/// One Platform's ROM folder, or those of Platforms shown as one: everything in them, and what their ROMs are.
public struct PlatformStorage: Sendable, Equatable, Identifiable {
    /// The IGDB platform it shows under.
    public let id: Int64
    /// The Platform's name, or its group's.
    public var name: String { PlatformGroups.groupName(id) ?? ROMPlatform.all[id]?.name ?? "Platform \(id)" }
    /// Everything in its ROM folder.
    public var total: Int64 = 0
    public var playable = ROMTally()
    public var archived = ROMTally()
    /// What's in its ROM folder that no ROM is made of.
    public var notAROM: Int64 { total - playable.bytes - archived.bytes }
    /// Its present ROMs.
    public var roms: Int { playable.count + archived.count }
    /// ROMs the journal has marked missing, which take no room.
    public var missing = 0
    /// Present ROMs on a Platform whose Emulator opens an archive, not yet Compacted into it.
    public var notCompacted = 0
    /// ROMs kept in more than one form at once, e.g. a Playable copy beside its Archived `.7z`, wasting room.
    public var inBothForms = 0
    /// Its ROM folder, or one of its group's, is there but couldn't be read, so the figures leave it out.
    public var unreadable = false

    /// Both rows together, under this one's Platform.
    func adding(_ other: Self) -> Self {
        var sum = self
        sum.total += other.total
        sum.playable = playable + other.playable
        sum.archived = archived + other.archived
        sum.missing += other.missing
        sum.notCompacted += other.notCompacted
        sum.inBothForms += other.inBothForms
        sum.unreadable = unreadable || other.unreadable
        return sum
    }

    /// Nil when the folder isn't there or has nothing in it.
    static func measure(_ folder: ROMFolder) -> PlatformStorage? {
        guard FileManager.default.fileExists(atPath: folder.url.path(percentEncoded: false)) else { return nil }
        var row = PlatformStorage(id: PlatformGroups.shownID(folder.platformId))
        guard let roms = try? folder.scan(), let sizes = try? Sizes.files(in: folder.url) else {
            row.unreadable = true
            return row
        }
        guard !sizes.isEmpty else { return nil }
        row.total = sizes.values.reduce(0, +)
        // A file two ROMs are made of (a loose playlist's Discs, each a ROM too) counts under the first.
        var claimed: Set<String> = []
        for rom in roms {
            guard let made = try? folder.files(of: rom).compactMap({ Sizes.relative($0, to: folder.url) }) else {
                row.unreadable = true
                continue
            }
            // Its files in every form it's kept in, none outside the folder.
            let files = Set(made).filter { sizes[$0] != nil && !claimed.contains($0) }
            claimed.formUnion(files)
            let bytes = files.reduce(0) { $0 + sizes[$1]! }
            if rom.archived {
                row.archived.count += 1
                row.archived.bytes += bytes
            } else {
                row.playable.count += 1
                row.playable.bytes += bytes
            }
            if let file = rom.ready ?? rom.archive, ROMPlatform.all[folder.platformId]?.canCompact(fileName: file.lastPathComponent) == true
            {
                row.notCompacted += 1
            }
            if rom.inBothForms { row.inBothForms += 1 }
        }
        return row
    }
}

/// Logical file sizes, by path within a folder.
enum Sizes {
    /// Every file at any depth below `folder`, but hidden ones (or those in hidden folders), by its path in `folder`.
    static func files(in folder: URL) throws -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: folder.path(percentEncoded: false))
        where !path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
            let values = try? folder.appending(path: path).resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            sizes[path] = Int64(values?.fileSize ?? 0)
        }
        return sizes
    }

    /// Everything below `folder`, but hidden files: none when it isn't there.
    static func total(in folder: URL) -> Int64 { ((try? files(in: folder)) ?? [:]).values.reduce(0, +) }

    /// One file's size: none when it isn't there.
    static func size(of file: URL) -> Int64 { Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }

    /// The file's path within `folder`; nil when it's outside it.
    static func relative(_ file: URL, to folder: URL) -> String? {
        let base = folder.standardizedFileURL.path(percentEncoded: false)
        let path = file.standardizedFileURL.path(percentEncoded: false)
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)).trimmingPrefix("/").description : nil
    }
}

extension LudeumStore {
    /// How many ROMs each Platform has missing, by IGDB platform id.
    func missingROMCounts() throws -> [Int64: Int] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT platformId, COUNT(*) AS n FROM rom WHERE missing GROUP BY platformId")
                .reduce(into: [:]) { $0[$1["platformId"]] = $1["n"] }
        }
    }
}
