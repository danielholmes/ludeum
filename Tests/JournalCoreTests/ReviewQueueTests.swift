import Foundation
import GRDB
import Testing

@testable import JournalCore

@Suite struct ReviewQueueTests {
    let h: Harness
    let j: JournalHarness
    let snes: [String: Any] = ["id": 19, "name": "SNES"]

    init() throws {
        h = try Harness()
        j = try JournalHarness()
        h.internet.addPlatform(19, "SNES")
        h.internet.addGame(7, "Kirby Super Star", fields: ["platforms": [snes]])
        h.internet.addGame(8, "Super Star Wars", fields: ["platforms": [snes]])
        h.internet.addGame(9, "Super Return of the Jedi", fields: ["platforms": [snes]])
    }

    var queue: ReviewQueue { ReviewQueue(journal: j.journal, igdb: h.igdb) }

    /// An unmatched ROM as the first Import leaves it.
    @discardableResult
    func unmatched(
        _ pk: Int64, _ name: String, suggestion: Int64? = nil, kind: String? = nil, namesAgree: Bool? = nil, checksumGame: Int64? = nil,
        stars: Int = 0, collections: [String] = [], start: String? = nil, missing: Bool = false
    ) throws -> Int64 {
        try j.journal.db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO rom (openEmuPk, md5, fileName, systemId, missing, version, suggestedIgdbGameId, suggestionKind,
                        checksumIgdbGameId, namesAgree)
                    VALUES (?, ?, ?, 'openemu.system.snes', ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [pk, "md5-\(pk)", name, missing, ROMName(name).version, suggestion, kind, checksumGame, namesAgree])
            let id = db.lastInsertedRowID
            let json = String(decoding: try JSONEncoder().encode(collections), as: UTF8.self)
            try db.execute(
                sql: "INSERT INTO heldOpenEmuData (romId, stars, collections, currentStart) VALUES (?, ?, ?, ?)",
                arguments: [id, stars, json, start])
            return id
        }
    }

    func match(_ rom: Int64) throws -> (game: GameID?, kind: String?) {
        try j.journal.db.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT gameId, matchKind FROM rom WHERE id = ?", arguments: [rom])!
            return (row["gameId"], row["matchKind"])
        }
    }

    @Test func itemsAreSortedIntoKinds() throws {
        try unmatched(1, "Kirby Super Star (USA)", suggestion: 7, kind: "name", namesAgree: true)
        try unmatched(2, "Super Star Wars - Return of the Jedi (USA)", suggestion: 8, kind: "checksum", namesAgree: false)
        try unmatched(3, "Super Return (USA)", suggestion: 9, kind: "name", namesAgree: false)
        try unmatched(4, "Unknown Homebrew")
        try unmatched(5, "RE2 Dual Shock (USA)", suggestion: 9, kind: "checksum", namesAgree: true, checksumGame: 8)

        let items = try j.journal.reviewQueue()

        #expect(items.namesAgree.map(\.romName) == ["Kirby Super Star (USA)", "RE2 Dual Shock (USA)"])
        #expect(items.namesAgree[1].checksumIgdbGameId == 8)
        #expect(items.checksumSuggestions.map(\.romName) == ["Super Star Wars - Return of the Jedi (USA)"])
        #expect(items.nameSuggestions.map(\.romName) == ["Super Return (USA)"])
        #expect(items.noSuggestion.map(\.romName) == ["Unknown Homebrew"])
        #expect(items.count == 5)
    }

    @Test func confirmingMatchesTheROMAndAppliesItsHeldOpenEmuData() async throws {
        let rom = try unmatched(
            1, "Kirby Super Star (USA)", suggestion: 7, kind: "name", namesAgree: true, stars: 4,
            collections: ["_TODO", "_Current", "Kirby"], start: "2026-09")
        let item = try #require(try j.journal.reviewQueue().namesAgree.first)

        let game = try await queue.confirm(item)

        #expect(try match(rom) == (game, "confirmed"))
        let g = try j.journal.game(game)
        #expect(g.name == "Kirby Super Star")
        #expect(g.igdbGameId == 7)
        #expect(g.platformId == 19)
        #expect(g.intent == .backlog)
        #expect(g.rating == Rating(tenths: 80))
        #expect(try j.journal.playthroughs(game).map(\.draft.start) == [PartialDate("2026-09")])
        #expect(try j.journal.lists(containing: game).map(\.name) == ["Kirby"])
        #expect(try j.journal.reviewQueue().count == 0)
    }

    @Test func confirmAllTakesEveryItemWhoseNamesAgree() async throws {
        try unmatched(1, "Kirby Super Star (USA)", suggestion: 7, kind: "name", namesAgree: true)
        try unmatched(2, "Super Return of the Jedi (USA)", suggestion: 9, kind: "checksum", namesAgree: true, checksumGame: 8)
        try unmatched(3, "Super Return (USA)", suggestion: 9, kind: "name", namesAgree: false)

        let confirmed = try await queue.confirmAll()

        #expect(confirmed == 2)
        let left = try j.journal.reviewQueue()
        #expect(left.namesAgree.isEmpty)
        #expect(left.nameSuggestions.count == 1)
    }

    @Test func choosingASearchResultIsAManualMatch() async throws {
        let rom = try unmatched(4, "Unknown Homebrew")
        let item = try #require(try j.journal.reviewQueue().noSuggestion.first)

        let game = try await queue.choose(item, igdbGameId: 7, name: "Kirby Super Star", platform: IGDBPlatform(id: 19, name: "SNES"))

        #expect(try match(rom) == (game, "manual"))
        #expect(try j.journal.game(game).igdbGameId == 7)
    }

    @Test func aROMCanBeAssignedToAnExistingGame() throws {
        try j.journal.addPlatform(id: 19, name: "SNES")
        let game = try j.journal.addGame(platformId: 19, name: "Sweet Home", igdbGameId: 70, igdbName: "Sweet Home")
        let rom = try unmatched(6, "Sweet Home (Japan) [T+Eng]")
        let item = try #require(try j.journal.reviewQueue().noSuggestion.first)

        #expect(try !j.journal.wouldHaveDuplicateVersions(game, adding: item.romId))
        try j.journal.assign(item, to: game)

        #expect(try match(rom) == (game, "manual"))
    }

    @Test func makingAGameByHandMatchesTheROM() throws {
        try j.journal.addPlatform(id: 19, name: "SNES")
        let rom = try unmatched(4, "Hermano 1.1 jam", stars: 5)
        let item = try #require(try j.journal.reviewQueue().noSuggestion.first)

        let game = try j.journal.makeByHand(item, name: "Hermano", platformId: 19)

        #expect(try match(rom) == (game, "manual"))
        #expect(try j.journal.game(game).rating == Rating(tenths: 100))
    }

    @Test func confirmingIntoAGameThatHasAVersionWarns() async throws {
        try j.journal.addPlatform(id: 19, name: "SNES")
        let game = try j.journal.addGame(platformId: 19, name: "Kirby Super Star", igdbGameId: 7, igdbName: "Kirby Super Star")
        let japan = try unmatched(1, "Kirby Super Star (Japan)")
        try j.journal.assign(try #require(try j.journal.reviewQueue().noSuggestion.first { $0.romId == japan }), to: game)
        try unmatched(2, "Kirby Super Star (USA)", suggestion: 7, kind: "name", namesAgree: true)

        let item = try #require(try j.journal.reviewQueue().namesAgree.first)

        #expect(try await queue.confirmWouldGiveDuplicateVersions(item))
    }

    @Test func duplicateVersionsItemsListPresentROMsOfOneGame() throws {
        try j.journal.addPlatform(id: 19, name: "SNES")
        let game = try j.journal.addGame(platformId: 19, name: "Double Dragon III", igdbGameId: 3, igdbName: "Double Dragon III")
        let japan = try unmatched(10, "Double Dragon III (Japan)")
        let usa = try unmatched(11, "Double Dragon III (USA)")
        try unmatched(12, "Double Dragon III (Europe)", missing: true)
        let items = try j.journal.reviewQueue().noSuggestion

        try j.journal.assign(try #require(items.first { $0.romId == japan }), to: game)
        #expect(try j.journal.wouldHaveDuplicateVersions(game, adding: usa))
        try j.journal.assign(try #require(items.first { $0.romId == usa }), to: game)
        try j.journal.assign(try #require(items.first { $0.romName.contains("Europe") }), to: game)

        let duplicates = try j.journal.reviewQueue().duplicateVersions
        #expect(duplicates.count == 1)
        #expect(duplicates[0].game.id == game)
        #expect(duplicates[0].roms.map(\.fileName) == ["Double Dragon III (Japan)", "Double Dragon III (USA)"])
    }
}
