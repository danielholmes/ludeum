import Foundation
import GRDB

/// Making the jars kept as Legacy Mobile Device Games' Attachments into ROMs (ADR 0044), run by hand once through
/// `ludeum-import mobile-attachments` with Ludeum closed, then deleted. Each Game's jars go into the Legacy Mobile ROM
/// folder under its Standard name and are Matched to it, by hand. Jars of one Game numbered `(File N)` are its episodes, so
/// one ROM of them as Discs, `(Disc N)`, with a playlist. Any other second jar of a Game is another Version, `(Alt)`, then
/// `(Alt 2)`. Once a Game's jars are in, its jar Attachments go, their files to the Trash.
public struct MobileAttachmentsMigration: Sendable {
    let journal: LudeumStore
    let ludeum: LudeumFolder
    let folder: ROMFolder
    let moveToTrash: @Sendable (URL) throws -> Void

    public init(
        journal: LudeumStore, ludeum: LudeumFolder, folder: ROMFolder, moveToTrash: @escaping @Sendable (URL) throws -> Void = Trash.move
    ) {
        self.journal = journal
        self.ludeum = ludeum
        self.folder = folder
        self.moveToTrash = moveToTrash
    }

    /// One ROM to make of a Game's jars.
    public struct ROM: Sendable, Equatable {
        public let game: GameID
        public let gameName: String
        /// What it's named in the ROM folder.
        public let name: String
        /// Its jars, in Disc order when there are several.
        public let jars: [URL]
        /// The Attachments its jars are, which go once it's in.
        public let attachments: [Int64]
    }

    public struct Plan: Sendable {
        public var roms: [ROM] = []
        /// What's left as it is, and why.
        public var left: [(what: String, why: String)] = []
    }

    public func plan() throws -> Plan {
        let rows = try journal.db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT a.id, a.fileName, a.missing, g.id AS gameId, g.attachmentFolder,
                        COALESCE(g.nameOverride, g.igdbName, g.name) AS gameName
                    FROM attachment a JOIN game g ON g.id = a.gameId
                    WHERE g.platformId = ? AND lower(a.fileName) LIKE '%.jar'
                    ORDER BY g.id, a.fileName COLLATE NOCASE
                    """, arguments: [ROMPlatform.legacyMobile])
        }
        var plan = Plan()
        for gameRows in Dictionary(grouping: rows, by: { $0["gameId"] as Int64 }).sorted(by: { $0.key < $1.key }).map(\.value) {
            let game: GameID = gameRows[0]["gameId"]
            let gameName: String = gameRows[0]["gameName"]
            let attachmentFolder: String? = gameRows[0]["attachmentFolder"]
            let fileNames = gameRows.map { $0["fileName"] as String }
            guard let attachmentFolder, gameRows.allSatisfy({ !($0["missing"] as Bool) }) else {
                plan.left += fileNames.map { ($0, "its file is missing") }
                continue
            }
            let jars = fileNames.map {
                ludeum.attachments.appending(path: attachmentFolder, directoryHint: .isDirectory).appending(path: $0)
            }
            let ids = gameRows.map { $0["id"] as Int64 }
            // No region tag: a jar's name says none, and Hasheous gives its Regions at the next Import if it knows it.
            guard
                let base = ROMRename.standardName(forROM: "", gameName: gameName, regions: [], platformId: ROMPlatform.legacyMobile)?.name()
            else {
                plan.left += fileNames.map { ($0, "its Game's name can't be made a ROM's") }
                continue
            }
            let episodes = fileNames.map { Self.episode(of: $0) }
            if jars.count > 1, episodes.allSatisfy({ $0 != nil }), Set(episodes).count == jars.count {
                let ordered = zip(episodes.map { $0! }, zip(jars, ids)).sorted { $0.0 < $1.0 }
                plan.roms.append(ROM(game: game, gameName: gameName, name: base, jars: ordered.map(\.1.0), attachments: ordered.map(\.1.1)))
            } else {
                for (i, (jar, id)) in zip(jars, ids).enumerated() {
                    let name = i == 0 ? base : i == 1 ? "\(base) (Alt)" : "\(base) (Alt \(i))"
                    plan.roms.append(ROM(game: game, gameName: gameName, name: name, jars: [jar], attachments: [id]))
                }
            }
        }
        for rom in plan.roms where try journal.romNameIsTaken(rom.name, besides: -1, on: ROMPlatform.legacyMobile) {
            plan.left.append((rom.name, "another ROM has its name"))
        }
        plan.roms.removeAll { rom in plan.left.contains { $0.what == rom.name } }
        return plan
    }

    /// The `N` of a `(File N)` in a jar's name, as Resident Evil: Confidential Report's episodes are named.
    static func episode(of fileName: String) -> Int? {
        (fileName as NSString).deletingPathExtension.firstMatch(of: /\(File (\d+)\)/).flatMap { Int($0.output.1) }
    }

    /// Makes each planned ROM, telling `say` each step. The journal is backed up first. A ROM that can't be made is told
    /// and left, its Attachments with it; the rest go on.
    public func run(_ plan: Plan, say: @Sendable (String) -> Void) async throws {
        try journal.backups?.backUp(journal, operation: .beforeMobileAttachments)
        let staging = folder.url.appending(path: ROMArchiver.workFolderName, directoryHint: .isDirectory)
            .appending(path: "mobile-attachments \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: staging) }
        let adder = AddROM(journal: journal, sevenZip: nil, moveToTrash: moveToTrash)
        for rom in plan.roms {
            do {
                // The jars under the names they'll have, so a Game's episodes are read as its Discs.
                let picked = staging.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
                var urls: [URL] = []
                for (i, jar) in rom.jars.enumerated() {
                    let name = rom.jars.count > 1 ? "\(rom.name) (Disc \(i + 1)).jar" : "\(rom.name).jar"
                    let copy = picked.appending(path: name)
                    try FileManager.default.copyItem(at: jar, to: copy)
                    urls.append(copy)
                }
                try await adder.add(ROMSource(urls), to: folder, match: .game(rom.game, deletingMissing: false), keepingOriginals: true)
                say("added \(rom.name) to \(rom.gameName)")
            } catch {
                say("left \(rom.name): \(error.localizedDescription)")
                continue
            }
            try deleteAttachments(rom)
            say("  its Attachments \(rom.jars.map(\.lastPathComponent).joined(separator: ", ")) went to the Trash")
        }
    }

    /// The ROM's Attachments go, as `Attachments.delete` does but without a backup each, the run's one being taken: their
    /// files to the Trash, their rows, and the Game's folder once nothing's left in it, with its Platform's if that's
    /// empty too.
    private func deleteAttachments(_ rom: ROM) throws {
        for jar in rom.jars where FileManager.default.fileExists(atPath: jar.path(percentEncoded: false)) { try moveToTrash(jar) }
        let ids = rom.attachments
        let emptied = try journal.db.write { db -> Bool in
            try db.execute(
                sql: "DELETE FROM attachment WHERE id IN (\(ids.map { _ in "?" }.joined(separator: ",")))",
                arguments: StatementArguments(ids))
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM attachment WHERE gameId = ?", arguments: [rom.game]) == 0
        }
        guard emptied, let folder = rom.jars.first?.deletingLastPathComponent() else { return }
        for empty in [folder, folder.deletingLastPathComponent()] {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: empty.path(percentEncoded: false))) ?? ["?"]
            guard contents.allSatisfy({ $0 == ".DS_Store" }) else { return }
            try FileManager.default.removeItem(at: empty)
            if empty == folder {
                try journal.db.write { db in
                    try db.execute(sql: "UPDATE game SET attachmentFolder = NULL WHERE id = ?", arguments: [rom.game])
                }
            }
        }
    }
}
