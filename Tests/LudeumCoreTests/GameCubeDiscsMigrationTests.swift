import Foundation
import GRDB
import Testing

@testable import LudeumCore

@Suite(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
struct GameCubeDiscsMigrationTests {
    let j: LudeumHarness
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "gamecube discs \(UUID().uuidString)", directoryHint: .isDirectory)
    let gameCube: FakeROMFolder
    let trash: URL

    init() throws {
        j = try LudeumHarness()
        gameCube = try FakeROMFolder(in: directory, platform: 21)
        trash = directory.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    var archiver: ROMArchiver {
        let trash = trash
        return ROMArchiver(
            sevenZip: SevenZip.find()!, freeSpace: { _ in .max },
            moveToTrash: { try FileManager.default.moveItem(at: $0, to: trash.appending(path: $0.lastPathComponent)) })
    }

    var migration: GameCubeDiscsMigration {
        GameCubeDiscsMigration(journal: j.journal, folder: gameCube.folder, archiver: archiver, backups: nil)
    }

    func game(_ name: String) throws -> Int64 {
        try j.journal.db.write { db in
            try ROMPlatform.ensureKnown(db, 21)
            try db.execute(sql: "INSERT INTO game (platformId, name) VALUES (21, ?)", arguments: [name])
            return db.lastInsertedRowID
        }
    }

    @discardableResult
    func rom(_ name: String, _ fileName: String, of game: Int64, archived: Bool, regions: String? = #"["USA"]"#, notes: String? = nil)
        throws -> Int64
    {
        try j.journal.db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO rom (folderName, fileName, name, platformId, archived, gameId, matchKind, matchedAt, discNumber,
                        regions, notes, crc)
                    VALUES (?, ?, ?, 21, ?, ?, 'automatic', ?, ?, ?, ?, 'abcd1234')
                    """,
                arguments: [name, fileName, name, archived, game, Date(), ROMName(name).disc, regions, notes])
            return db.lastInsertedRowID
        }
    }

    /// A Disc Archived as an Archive would leave it: a `.7z` of its one image.
    func archivedDisc(_ name: String, _ contents: String) async throws {
        try gameCube.add("\(name).iso", contents)
        try await archiver.archive(name, in: gameCube.folder)
        try FileManager.default.removeItem(at: trash.appending(path: "\(name).iso"))
    }

    func rows() throws -> [Row] { try j.journal.db.read { try Row.fetchAll($0, sql: "SELECT * FROM rom ORDER BY id") } }

    @Test func archivedDiscsBecomeOneArchivedROMOfTheirFolderAndPlaylistKeepingDisc1sRow() async throws {
        let re = try game("Resident Evil")
        try await archivedDisc("Resident Evil (USA) (Disc 1)", String(repeating: "D1", count: 5_000))
        try await archivedDisc("Resident Evil (USA) (Disc 2)", String(repeating: "D2", count: 5_000))
        let disc1 = try rom("Resident Evil (USA) (Disc 1)", "Resident Evil (USA) (Disc 1).7z", of: re, archived: true, notes: "eBay")
        let disc2 = try rom("Resident Evil (USA) (Disc 2)", "Resident Evil (USA) (Disc 2).7z", of: re, archived: true)
        try await j.journal.db.write { db in
            try db.execute(sql: "INSERT INTO playthrough (gameId, start, romId) VALUES (?, '2026', ?)", arguments: [re, disc2])
        }

        let plan = try migration.plan()
        #expect(plan.merges.map(\.name) == ["Resident Evil (USA)"])
        #expect(plan.merges.first?.archived == true)
        try await migration.run(plan)

        #expect(try gameCube.folder.scan().map(\.fileName) == ["Resident Evil (USA).7z"])
        let inside = try await SevenZip.find()!.list(gameCube.url.appending(path: "Resident Evil (USA).7z")).map(\.path).sorted()
        #expect(inside == ["Resident Evil (USA) (Disc 1).iso", "Resident Evil (USA) (Disc 2).iso", "Resident Evil (USA).m3u"])
        let rows = try rows()
        #expect(rows.map { $0["id"] as Int64 } == [disc1])
        #expect(rows[0]["folderName"] as String == "Resident Evil (USA)")
        #expect(rows[0]["fileName"] as String == "Resident Evil (USA).7z")
        #expect(rows[0]["archived"] as Bool == true)
        #expect(rows[0]["discNumber"] as Int? == nil)
        #expect(rows[0]["notes"] as String? == "eBay")
        #expect(rows[0]["regions"] as String? == #"["USA"]"#)
        #expect(try await j.journal.db.read { try Int64.fetchOne($0, sql: "SELECT romId FROM playthrough") } == disc1)

        // Unarchived, it's the folder an Import reads as one ROM opening its playlist.
        try await archiver.unarchive(
            gameCube.url.appending(path: "Resident Evil (USA).7z"), romName: "Resident Evil (USA)", in: gameCube.folder)
        let playlist = gameCube.url.appending(path: "Resident Evil (USA)/Resident Evil (USA).m3u")
        #expect(try gameCube.folder.scan().map(\.fileName) == ["Resident Evil (USA)/Resident Evil (USA).m3u"])
        #expect(
            try String(contentsOf: playlist, encoding: .utf8) == "Resident Evil (USA) (Disc 1).iso\nResident Evil (USA) (Disc 2).iso\n")
        #expect(try migration.plan().merges.isEmpty)
    }

    @Test func looseDiscsBecomeOneFolderNotArchived() async throws {
        let zero = try game("Resident Evil Zero")
        try gameCube.add("Resident Evil Zero (USA) (Disc 1).rvz", "D1")
        try gameCube.add("Resident Evil Zero (USA) (Disc 2).rvz", "D2")
        try rom("Resident Evil Zero (USA) (Disc 1)", "Resident Evil Zero (USA) (Disc 1).rvz", of: zero, archived: false)
        try rom("Resident Evil Zero (USA) (Disc 2)", "Resident Evil Zero (USA) (Disc 2).rvz", of: zero, archived: false)

        try await migration.run(try migration.plan())

        #expect(try gameCube.folder.scan().map(\.fileName) == ["Resident Evil Zero (USA)/Resident Evil Zero (USA).m3u"])
        #expect(try rows().map { $0["fileName"] as String } == ["Resident Evil Zero (USA)/Resident Evil Zero (USA).m3u"])
    }

    @Test func discsWhoseCopyDetailsDisagreeAreLeft() async throws {
        let zero = try game("Resident Evil Zero")
        try gameCube.add("Resident Evil Zero (USA) (Disc 1).rvz", "D1")
        try gameCube.add("Resident Evil Zero (USA) (Disc 2).rvz", "D2")
        try rom("Resident Evil Zero (USA) (Disc 1)", "Resident Evil Zero (USA) (Disc 1).rvz", of: zero, archived: false, notes: "a")
        try rom("Resident Evil Zero (USA) (Disc 2)", "Resident Evil Zero (USA) (Disc 2).rvz", of: zero, archived: false, notes: "b")

        let plan = try migration.plan()

        #expect(plan.merges.isEmpty)
        #expect(plan.left.map(\.why) == ["their Copy details disagree"])
    }

    @Test func aGamesOtherVersionIsntTouched() async throws {
        let tales = try game("Tales of Symphonia")
        try gameCube.add("Tales of Symphonia (USA) (Disc 1).rvz", "D1")
        try gameCube.add("Tales of Symphonia (USA) (Disc 2).rvz", "D2")
        try gameCube.add("Tales of Symphonia (Europe).rvz", "EU")
        try rom("Tales of Symphonia (USA) (Disc 1)", "Tales of Symphonia (USA) (Disc 1).rvz", of: tales, archived: false)
        try rom("Tales of Symphonia (USA) (Disc 2)", "Tales of Symphonia (USA) (Disc 2).rvz", of: tales, archived: false)
        try rom("Tales of Symphonia (Europe)", "Tales of Symphonia (Europe).rvz", of: tales, archived: false)

        try await migration.run(try migration.plan())

        #expect(try gameCube.folder.scan().map(\.name) == ["Tales of Symphonia (Europe)", "Tales of Symphonia (USA)"])
        #expect(try rows().count == 2)
    }
}
