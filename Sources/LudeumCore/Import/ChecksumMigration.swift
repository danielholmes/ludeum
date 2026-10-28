import Foundation
import GRDB

/// The one-off replacement of every stored checksum that isn't what `ROMChecksum` gives today, run by hand through
/// `ludeum-import checksums` (#80): most ROMs that came across from OpenEmu still carry OpenEmu's MD5, which for a disc is
/// of its cue sheet, so Hasheous misses it or matches the wrong game. Each ROM present in its ROM folder is read as an
/// Import reads a new one, and where that differs from what the journal holds, the new checksum replaces both old
/// values, so a ROM ends with an MD5 or a CRC32, never one stale and one new. A ROM in a form no DAT knows has its
/// checksum cleared, since it can only be OpenEmu's. One that's changed and has no Regions is given them again at the
/// next Import; its Regions, Match, suggestion and other Copy details are left alone. A ROM that can't be read now is
/// left as it is. To go once it has run.
public struct ChecksumMigration: Sendable {
    /// A ROM whose checksum changes.
    public struct Change: Sendable, Equatable {
        public let romId: Int64
        public let platformId: Int64
        public let name: String
        let oldMD5: String?
        let oldCRC: String?
        /// Nil when it's cleared: a form no DAT knows.
        public let checksum: ROMChecksum?
    }

    /// A ROM left as it is, and why.
    public struct Left: Sendable, Equatable, CustomStringConvertible {
        public let platformId: Int64
        public let name: String
        public let reason: Reason

        public enum Reason: String, Sendable {
            case noROMFolder = "its Platform has no ROM folder"
            case notInFolder = "its files aren't in its ROM folder"
            case onlineOnly = "Dropbox keeps it online only"
            case unreadable = "it can't be read"
        }

        public var description: String { "left    \(ChecksumMigration.platformName(platformId))  \(name): \(reason.rawValue)" }
    }

    /// What `run` would do, or did.
    public struct Plan: Sendable, Equatable {
        public var changes: [Change] = []
        public var left: [Left] = []
        /// How many present ROMs were read on each Platform.
        public var read: [Int64: Int] = [:]

        /// Per Platform, how many checksums change of how many ROMs read, then each ROM left and why, by Platform and name.
        public var lines: [String] {
            let byPlatform = Dictionary(grouping: changes, by: \.platformId)
            let platforms = read.keys.sorted { ChecksumMigration.platformName($0) < ChecksumMigration.platformName($1) }
            let left = left.sorted {
                (ChecksumMigration.platformName($0.platformId), $0.name) < (ChecksumMigration.platformName($1.platformId), $1.name)
            }
            return platforms.map { platform in
                let changes = byPlatform[platform] ?? []
                let cleared = changes.filter { $0.checksum == nil }.count
                return "\(ChecksumMigration.platformName(platform)): \(changes.count) of \(read[platform] ?? 0) change"
                    + (cleared > 0 ? " (\(cleared) cleared)" : "")
            } + left.map(\.description)
        }
    }

    let journal: LudeumStore
    let romFolders: [ROMFolder]
    let sevenZip: SevenZip
    /// Taken from before it writes, kept forever: the one way back.
    let backups: Backups?
    /// Whether Dropbox has a file on disk, rather than online only.
    let isOnDisk: @Sendable (URL) -> Bool

    public init(journal: LudeumStore, romFolders: [ROMFolder], sevenZip: SevenZip, backups: Backups?) {
        self.init(journal: journal, romFolders: romFolders, sevenZip: sevenZip, backups: backups, isOnDisk: SevenZip.isOnDisk)
    }

    init(
        journal: LudeumStore, romFolders: [ROMFolder], sevenZip: SevenZip, backups: Backups?,
        isOnDisk: @escaping @Sendable (URL) -> Bool
    ) {
        self.journal = journal
        self.romFolders = romFolders
        self.sevenZip = sevenZip
        self.backups = backups
        self.isOnDisk = isOnDisk
    }

    /// Reads every present ROM, changing nothing.
    public func plan() async throws -> Plan {
        let folders = Dictionary(romFolders.map { ($0.platformId, $0) }, uniquingKeysWith: { a, _ in a })
        let roms = try journal.db.read { db in
            try Row.fetchAll(
                db, sql: "SELECT id, platformId, folderName, md5, crc FROM rom WHERE folderName IS NOT NULL AND NOT missing ORDER BY id")
        }
        var plan = Plan()
        for row in roms {
            try Task.checkCancellation()
            let platformId: Int64 = row["platformId"]
            let name: String = row["folderName"]
            func leave(_ reason: Left.Reason) { plan.left.append(Left(platformId: platformId, name: name, reason: reason)) }
            guard let folder = folders[platformId] else {
                leave(.noROMFolder)
                continue
            }
            guard let file = try? folder.rom(named: name) else {
                leave(.notInFolder)
                continue
            }
            plan.read[platformId, default: 0] += 1
            let checksum: ROMChecksum?
            switch await ROMChecksum.read(file, platformId: platformId, sevenZip: sevenZip, isOnDisk: isOnDisk) {
            case .checksum(let read): checksum = read
            case .noDump: checksum = nil
            case .onlineOnly:
                leave(.onlineOnly)
                continue
            case .unreadable:
                leave(.unreadable)
                continue
            }
            let (md5, crc): (String?, String?) = (row["md5"], row["crc"])
            guard checksum?.md5 != md5 || checksum?.crc != crc else { continue }
            plan.changes.append(
                Change(romId: row["id"], platformId: platformId, name: name, oldMD5: md5, oldCRC: crc, checksum: checksum))
        }
        return plan
    }

    /// Does what `plan` found, in one transaction after a backup, returning it. A ROM whose name or checksum changed
    /// since it was read is left for the next run.
    public func run() async throws -> Plan {
        let plan = try await plan()
        guard !plan.changes.isEmpty else { return plan }
        _ = try backups?.backUp(journal, operation: .beforeChecksums)
        try await journal.db.write { db in
            for change in plan.changes {
                try db.execute(
                    sql: """
                        UPDATE rom SET md5 = ?, crc = ?, regionsLookedUp = regionsLookedUp AND regions IS NOT NULL
                        WHERE id = ? AND folderName = ? AND md5 IS ? AND crc IS ?
                        """,
                    arguments: [change.checksum?.md5, change.checksum?.crc, change.romId, change.name, change.oldMD5, change.oldCRC])
            }
        }
        return plan
    }

    static func platformName(_ id: Int64) -> String { ROMPlatform.all[id]?.name ?? "Platform \(id)" }
}
