import Foundation
import GRDB
import Testing

@testable import LudeumCore

@Suite struct OngoingImportTests {
    let h: Harness
    let j: LudeumHarness
    let oe: FakeOpenEmu

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        oe = try FakeOpenEmu(in: h.directory)
        let snes: [String: Any] = ["id": 19, "name": "SNES"]
        h.internet.addPlatform(19, "SNES")
        h.internet.addGame(1103, "Super Metroid", fields: ["platforms": [snes]])
        h.internet.addGame(1070, "Super Mario World", fields: ["platforms": [snes]])
        h.internet.addHash(md5: "aa", game: 1103, platform: 19)
        h.internet.addHash(md5: "bb", game: 1070, platform: 19)
    }

    var ongoing: OngoingImport {
        OngoingImport(
            igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil,
            snapshotFile: h.directory.appending(path: "ongoing.sqlite"))
    }

    /// Commits a first Import of the fake library as it is now.
    func firstImport() async throws {
        let run = FirstImport(
            igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil, draftFolder: h.directory.appending(path: "draft"))
        let draft = try await run.start(library: oe.folder) { _, _ in }
        try await run.commit(draft)
    }

    func romRow(openEmuPk: Int64) throws -> Row? {
        try j.journal.db.read { try Row.fetchOne($0, sql: "SELECT * FROM rom WHERE openEmuPk = ?", arguments: [openEmuPk]) }
    }

    @Test func itNeedsTheFirstImport() async throws {
        await #expect(throws: ImportError.firstImportNeeded) { try await ongoing.run(library: oe.folder) }
    }

    @Test func anImportThatChangedNothingSaysNothing() async throws {
        try oe.addROM("Super Metroid (USA)", md5: "aa")
        try await firstImport()

        let result = try await ongoing.run(library: oe.folder)

        #expect(!result.changedSomething)
    }

    @Test func aNewROMIsMatchedAutomaticallyAndSilently() async throws {
        try oe.addROM("Super Metroid (USA)", md5: "aa")
        try await firstImport()
        let mario = try oe.addROM("Super Mario World (USA)", md5: "bb")

        let result = try await ongoing.run(library: oe.folder)

        #expect(result.matched.map(\.romName) == ["Super Mario World (USA)"])
        #expect(result.sentToReview.isEmpty)
        let row = try #require(try romRow(openEmuPk: mario))
        #expect(row["matchKind"] as String == "automatic")
        #expect(try j.journal.game(row["gameId"]).name == "Super Mario World")
    }

    @Test func aNewROMWithoutAnAutomaticMatchGoesToTheReviewQueue() async throws {
        try oe.addROM("Super Metroid (USA)", md5: "aa")
        try await firstImport()
        try oe.addROM("Unknown Homebrew", md5: "zz")

        let result = try await ongoing.run(library: oe.folder)

        #expect(result.sentToReview.map(\.romName) == ["Unknown Homebrew"])
        #expect(try j.journal.reviewQueue().noSuggestion.map(\.romName) == ["Unknown Homebrew"])
    }

    @Test func aROMThatDisappearsIsMarkedMissing() async throws {
        let metroid = try oe.addROM("Super Metroid (USA)", md5: "aa")
        try await firstImport()
        try oe.removeROM(metroid)

        let result = try await ongoing.run(library: oe.folder)

        #expect(result.goneMissing.map(\.romName) == ["Super Metroid (USA)"])
        #expect(try romRow(openEmuPk: metroid)?["missing"] as Bool? == true)
    }

    @Test func aROMThatComesBackRejoinsItsGameWithoutReview() async throws {
        let metroid = try oe.addROM("Super Metroid (USA)", md5: "aa")
        try await firstImport()
        let game = try #require(try romRow(openEmuPk: metroid)?["gameId"] as GameID?)
        try oe.removeROM(metroid)
        _ = try await ongoing.run(library: oe.folder)
        // Re-added in OpenEmu: a new Z_PK, the same MD5.
        let again = try oe.addROM("Super Metroid (USA)", md5: "aa")

        let result = try await ongoing.run(library: oe.folder)

        #expect(result.returned.map(\.romName) == ["Super Metroid (USA)"])
        #expect(result.sentToReview.isEmpty)
        #expect(!result.changedSomething)
        let row = try #require(try romRow(openEmuPk: again))
        #expect(row["gameId"] as GameID == game)
        #expect(row["missing"] as Bool == false)
        #expect(row["matchKind"] as String == "automatic")
    }

    @Test func anOrphanedEntryWhoseFileReturnsIsPresentAgainSilently() async throws {
        let metroid = try oe.addROM("Super Metroid (USA)", md5: "aa")
        try await firstImport()
        let file = oe.folder.appending(path: "roms/openemu.system.snes/\(metroid)-rom.sfc")
        let parked = h.directory.appending(path: "parked.sfc")
        try FileManager.default.moveItem(at: file, to: parked)
        #expect(try await ongoing.run(library: oe.folder).goneMissing.count == 1)
        try FileManager.default.moveItem(at: parked, to: file)

        let result = try await ongoing.run(library: oe.folder)

        #expect(try romRow(openEmuPk: metroid)?["missing"] as Bool? == false)
        #expect(result.returned.count == 1)
        #expect(!result.changedSomething)
    }

    @Test func aNewVersionOfAGameIsMatchedAndShowsAsDuplicateVersions() async throws {
        try oe.addROM("Super Metroid (USA)", md5: "aa")
        try await firstImport()
        h.internet.addHash(md5: "a2", game: 1103, platform: 19)
        try oe.addROM("Super Metroid (Japan)", md5: "a2")

        let result = try await ongoing.run(library: oe.folder)

        #expect(result.matched.count == 1)
        #expect(try j.journal.reviewQueue().duplicateVersions.map(\.game.name) == ["Super Metroid"])
    }

    @Test func aChangedStoreUUIDIsRefused() async throws {
        try oe.addROM("Super Metroid (USA)", md5: "aa")
        try await firstImport()
        try oe.replaceStore(uuid: "STORE-2")

        await #expect(throws: ImportError.libraryReplaced) { try await ongoing.run(library: oe.folder) }
    }
}
