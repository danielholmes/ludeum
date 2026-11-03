import Foundation
import GRDB

/// Making each multi-disc GameCube Version one ROM (ADR 0031), run by hand once through `ludeum-import gamecube-discs`
/// with Ludeum closed, then deleted. A Game's GameCube ROMs that are the Discs of one Version, each loose or Archived,
/// become one ROM named after them without their Disc: a subfolder holding the Discs and a playlist of them, Archived
/// again when they all were. Disc 1's row is kept, with the Copy details every Disc agrees on; a Playthrough played on
/// another Disc moves to it, and the other rows go. Discs whose details disagree, or that aren't all there, are left.
public struct GameCubeDiscsMigration: Sendable {
    let journal: LudeumStore
    let folder: ROMFolder
    let archiver: ROMArchiver
    let backups: Backups?

    public init(journal: LudeumStore, folder: ROMFolder, archiver: ROMArchiver, backups: Backups?) {
        self.journal = journal
        self.folder = folder
        self.archiver = archiver
        self.backups = backups
    }

    static let platformId: Int64 = 21
    /// A ROM's Copy details, which go with the one ROM its Discs become.
    static let details = ["regions", "acquiredOn", "acquiredFrom", "price", "currency", "notes"]

    public struct Disc: Sendable, Equatable {
        public let id: Int64
        public let name: String
        public let number: Int
    }

    /// The Discs of one Version becoming one ROM.
    public struct Merge: Sendable, Equatable {
        public let game: String
        /// The ROM's name: its Discs' without their Disc.
        public let name: String
        /// In Disc order; the first one's row is kept.
        public let discs: [Disc]
        /// Every Disc is Archived, so the ROM is Archived again.
        public let archived: Bool
        /// The Copy details every Disc agrees on.
        let details: [String: DatabaseValue]
    }

    public struct Plan: Sendable {
        public var merges: [Merge] = []
        /// What's left as it is, and why.
        public var left: [(rom: String, why: String)] = []
    }

    public func plan() throws -> Plan {
        var plan = Plan()
        let rows = try journal.db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT r.*, g.name AS gameName FROM rom r JOIN game g ON g.id = r.gameId
                    WHERE r.platformId = ? AND r.gameId IN (
                        SELECT gameId FROM rom WHERE platformId = ? AND gameId IS NOT NULL GROUP BY gameId HAVING COUNT(*) > 1)
                    ORDER BY r.gameId, r.folderName
                    """, arguments: [Self.platformId, Self.platformId])
        }
        let versions = Dictionary(grouping: rows.filter { ROMName($0["folderName"]).disc != nil }) { row in
            "\(row["gameId"] as Int64) \(ROMName(row["folderName"]).withoutDisc)"
        }
        for key in versions.keys.sorted() {
            let discs = versions[key]!.sorted { ROMName($0["folderName"]).disc! < ROMName($1["folderName"]).disc! }
            let names = discs.map { $0["folderName"] as String }
            let name = ROMName(names[0]).withoutDisc
            func leave(_ why: String) { plan.left.append((names.joined(separator: ", "), why)) }
            guard discs.count > 1 else { continue }
            guard Set(discs.map { ROMName($0["folderName"]).disc! }).count == discs.count else {
                leave("two of them are the same Disc")
                continue
            }
            if discs.contains(where: { $0["missing"] }) {
                leave("a Disc is missing")
                continue
            }
            var details: [String: DatabaseValue] = [:]
            var agree = true
            for column in Self.details {
                let values = Set(discs.map { $0[column] as DatabaseValue }.filter { !$0.isNull })
                if values.count > 1 { agree = false }
                details[column] = values.first ?? .null
            }
            guard agree else {
                leave("their Copy details disagree")
                continue
            }
            if try folder.rom(named: name) != nil || journal.romNameIsTaken(name, besides: -1, on: Self.platformId) {
                leave("\(name) is already taken")
                continue
            }
            let files = try names.map { try folder.rom(named: $0) }
            guard files.allSatisfy({ $0 != nil }) else {
                leave("a Disc's file isn't in the ROM folder")
                continue
            }
            // Each loose or Archived, never in a subfolder of its own or in both forms.
            guard files.allSatisfy({ file in file!.inBothForms == false && folder.subfolder(of: file!.name, holding: file!.ready) == nil })
            else {
                leave("a Disc isn't one loose file or one .7z")
                continue
            }
            plan.merges.append(
                Merge(
                    game: discs[0]["gameName"], name: name,
                    discs: discs.map { Disc(id: $0["id"], name: $0["folderName"], number: ROMName($0["folderName"]).disc!) },
                    archived: files.allSatisfy { $0!.archived }, details: details))
        }
        return plan
    }

    /// Does what `plan` found, after a backup, one Version at a time: its files first, then its rows in one transaction.
    /// Stops at the first failure, leaving the Versions before it done.
    public func run(_ plan: Plan, progress: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        guard !plan.merges.isEmpty else { return }
        _ = try backups?.backUp(journal, operation: .beforeGameCubeDiscs)
        for merge in plan.merges {
            progress("\(merge.name): its Discs")
            let subfolder = folder.url.appending(path: merge.name, directoryHint: .isDirectory)
            var images: [String] = []
            for disc in merge.discs {
                if let archive = try folder.rom(named: disc.name)?.archive, try folder.rom(named: disc.name)?.ready == nil {
                    progress("\(merge.name): unarchiving \(disc.name)")
                    try await archiver.unarchive(archive, romName: disc.name, in: folder)
                }
                guard let image = try folder.rom(named: disc.name)?.ready else { throw ReviewError.romFilesNotFound }
                try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: image, to: subfolder.appending(path: image.lastPathComponent))
                images.append(image.lastPathComponent)
            }
            let playlist = subfolder.appending(path: "\(merge.name).m3u", directoryHint: .notDirectory)
            try Data((images.joined(separator: "\n") + "\n").utf8).write(to: playlist, options: .withoutOverwriting)
            if merge.archived {
                progress("\(merge.name): archiving")
                try await archiver.archive(merge.name, in: folder)
            }
            try record(merge)
        }
    }

    /// The Discs' rows become Disc 1's, as the one ROM.
    func record(_ merge: Merge) throws {
        let kept = merge.discs[0].id
        let others = merge.discs.dropFirst().map(\.id)
        let fileName = merge.archived ? "\(merge.name).7z" : "\(merge.name)/\(merge.name).m3u"
        try journal.db.write { db in
            let placeholders = others.map { _ in "?" }.joined(separator: ", ")
            try db.execute(
                sql: "UPDATE playthrough SET romId = ? WHERE romId IN (\(placeholders))",
                arguments: StatementArguments([kept] + others))
            try db.execute(sql: "DELETE FROM rom WHERE id IN (\(placeholders))", arguments: StatementArguments(others))
            let details = Self.details.map { "\"\($0)\" = ?" }.joined(separator: ", ")
            try db.execute(
                sql: """
                    UPDATE rom SET folderName = ?, name = ?, fileName = ?, archived = ?, missing = 0, discNumber = NULL,
                        discLabel = NULL, lastDisc = NULL, needsPlaylist = 0, inBothForms = 0, \(details)
                    WHERE id = ?
                    """,
                arguments: StatementArguments([merge.name, merge.name, fileName, merge.archived] as [any DatabaseValueConvertible])
                    + StatementArguments(Self.details.map { merge.details[$0] ?? .null }) + [kept])
        }
    }
}
