import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// Confirm on a sibling Platform: one OpenEmu kept under the same system as the ROM's (Game Boy and Game Boy Color,
/// NES and Famicom, SNES and Super Famicom).
@Suite struct ReviewConfirmPlatformTests {
    let h: Harness
    let j: LudeumHarness
    let gameBoy: FakeROMFolder
    let colour: FakeROMFolder

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        gameBoy = try FakeROMFolder(in: h.directory, platform: 33)
        colour = try FakeROMFolder(in: h.directory, platform: 22)
        h.internet.addPlatform(33, "Game Boy")
        h.internet.addPlatform(22, "Game Boy Color")
        h.internet.addGame(5, "Pokemon Gold", fields: ["platforms": [["id": 22, "name": "Game Boy Color"]]])
    }

    var queue: ReviewQueue { ReviewQueue(journal: j.journal, igdb: h.igdb, romFolders: [gameBoy.folder, colour.folder]) }

    /// A ROM in the Game Boy folder, suggested as Pokemon Gold.
    func gold(fileName: String = "Pokemon Gold (USA).gbc", missing: Bool = false) throws -> ReviewItem {
        if !missing { try gameBoy.add(fileName, "rom") }
        try j.journal.db.write { db in
            try ROMPlatform.ensureKnown(db, 33)
            let name = (fileName as NSString).deletingPathExtension
            try db.execute(
                sql: """
                    INSERT INTO rom (folderName, fileName, name, platformId, missing, suggestedIgdbGameId, suggestionKind, namesAgree)
                    VALUES (?, ?, ?, 33, ?, 5, 'name', 1)
                    """, arguments: [name, fileName, name, missing])
        }
        return try #require(try j.journal.reviewQueue().namesAgree.first)
    }

    func rom() throws -> Row {
        try j.journal.db.read { try Row.fetchOne($0, sql: "SELECT * FROM rom")! }
    }

    func exists(_ folder: FakeROMFolder, _ path: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.url.appending(path: path).path(percentEncoded: false))
    }

    @Test func confirmOffersTheROMsPlatformAndItsSiblings() throws {
        #expect(try gold().platformChoices == [33, 22])
    }

    @Test func confirmingOnTheROMsOwnPlatformLeavesItsFileWhereItIs() async throws {
        let game = try await queue.confirm(try gold())

        #expect(try j.journal.game(game).platformId == 33)
        #expect(try rom()["platformId"] as Int64 == 33)
        #expect(exists(gameBoy, "Pokemon Gold (USA).gbc"))
    }

    @Test func confirmingOnASiblingMovesTheROMIntoThatPlatformsFolder() async throws {
        let game = try await queue.confirm(try gold(), on: 22)

        #expect(try j.journal.game(game).platformId == 22)
        #expect(try rom()["platformId"] as Int64 == 22)
        #expect(try rom()["gameId"] as GameID? == game)
        #expect(!exists(gameBoy, "Pokemon Gold (USA).gbc"))
        #expect(try String(contentsOf: colour.url.appending(path: "Pokemon Gold (USA).gbc"), encoding: .utf8) == "rom")
    }

    @Test func itsArchiveAndSubfolderMoveWithIt() async throws {
        try gameBoy.add("Pokemon Gold (USA).7z", "archive")
        try gameBoy.add("Pokemon Gold (USA)/Pokemon Gold (USA).gbc", "unpacked")
        try await j.journal.db.write { db in
            try ROMPlatform.ensureKnown(db, 33)
            try db.execute(
                sql: """
                    INSERT INTO rom (folderName, fileName, platformId, suggestedIgdbGameId, suggestionKind, namesAgree)
                    VALUES ('Pokemon Gold (USA)', 'Pokemon Gold (USA)/Pokemon Gold (USA).gbc', 33, 5, 'name', 1)
                    """)
        }
        let item = try #require(try j.journal.reviewQueue().namesAgree.first)

        try await queue.confirm(item, on: 22)

        #expect(exists(colour, "Pokemon Gold (USA).7z"))
        #expect(exists(colour, "Pokemon Gold (USA)/Pokemon Gold (USA).gbc"))
        #expect(try gameBoy.folder.scan().isEmpty)
    }

    @Test func aMissingROMOnlyChangesItsPlatformInTheJournal() async throws {
        try await queue.confirm(try gold(missing: true), on: 22)

        #expect(try rom()["platformId"] as Int64 == 22)
        #expect(try rom()["missing"] as Bool)
        #expect(try colour.folder.scan().isEmpty)
    }

    @Test func aROMStillOpenEmusOnlyChangesItsPlatformInTheJournal() async throws {
        let unmigrated = try LudeumHarness(beforeOpenEmuMigration: true)
        try await unmigrated.journal.db.write { db in
            try ROMPlatform.ensureKnown(db, 33)
            try db.execute(
                sql: """
                    INSERT INTO rom (openEmuPk, md5, fileName, platformId, suggestedIgdbGameId, suggestionKind, namesAgree)
                    VALUES (1, 'aa', 'Pokemon Gold (USA).gbc', 33, 5, 'name', 1)
                    """)
        }
        let item = try #require(try unmigrated.journal.reviewQueue().namesAgree.first)

        let game = try await ReviewQueue(journal: unmigrated.journal, igdb: h.igdb, romFolders: [gameBoy.folder, colour.folder])
            .confirm(item, on: 22)

        #expect(try unmigrated.journal.game(game).platformId == 22)
        #expect(try await unmigrated.journal.db.read { try Int64.fetchOne($0, sql: "SELECT platformId FROM rom") } == 22)
    }

    @Test func aPlatformThatIsntASiblingIsRefused() async throws {
        let item = try gold()

        await #expect(throws: ReviewError.notASiblingPlatform) { try await queue.confirm(item, on: 19) }
        #expect(try rom()["gameId"] as GameID? == nil)
    }

    @Test func aFileAlreadyInTheSiblingsFolderRefusesWithNothingMovedOrMatched() async throws {
        let item = try gold()
        try colour.add("Pokemon Gold (USA).gb", "someone else's")

        await #expect(throws: ReviewError.alreadyInROMFolder) { try await queue.confirm(item, on: 22) }
        #expect(exists(gameBoy, "Pokemon Gold (USA).gbc"))
        #expect(try rom()["platformId"] as Int64 == 33)
        #expect(try rom()["gameId"] as GameID? == nil)
    }

    @Test func aFileTheSiblingsFolderWontReadIsRefused() async throws {
        let item = try gold(fileName: "Pokemon Gold (USA).sgb")

        await #expect(throws: ReviewError.siblingWontReadFile) { try await queue.confirm(item, on: 22) }
        #expect(exists(gameBoy, "Pokemon Gold (USA).sgb"))
    }

    @Test func aPresentROMWhoseFilesCantBeFoundIsRefused() async throws {
        let item = try gold()
        try gameBoy.remove("Pokemon Gold (USA).gbc")

        await #expect(throws: ReviewError.romFilesNotFound) { try await queue.confirm(item, on: 22) }
        #expect(try rom()["platformId"] as Int64 == 33)
    }

    @Test func eachOpenEmuSystemWithSeveralPlatformsIsASiblingGroup() {
        for platforms in openEmuSystemPlatforms.values where platforms.count > 1 {
            #expect(ROMPlatform.siblings(of: Int64(platforms[0])) == platforms.map(Int64.init))
        }
    }

    @Test func aPlatformWithNoSiblingIsTheOnlyChoice() throws {
        try j.journal.db.write { db in
            try ROMPlatform.ensureKnown(db, 8)
            try db.execute(sql: "INSERT INTO rom (folderName, fileName, platformId) VALUES ('Okami (USA)', 'Okami (USA).iso', 8)")
        }
        #expect(try j.journal.reviewQueue().noSuggestion.first?.platformChoices == [8])
    }
}
