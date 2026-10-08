import Foundation
import GRDB
import Testing

@testable import LudeumCore

@Suite struct LibraryTests {
    let h: LudeumHarness
    let metroid: GameID
    let zelda: GameID
    let doom: GameID

    init() throws {
        h = try LudeumHarness()
        try h.journal.addPlatform(id: 19, name: "SNES")
        try h.journal.addPlatform(id: 6, name: "PC")
        metroid = try h.journal.addGame(platformId: 19, name: "Super Metroid")
        zelda = try h.journal.addGame(platformId: 19, name: "A Link to the Past")
        doom = try h.journal.addGame(platformId: 6, name: "Doom")
        try h.journal.setRating(metroid, Rating(tenths: 95))
        try h.journal.setRating(zelda, Rating(tenths: 80))
        try h.journal.setIntent(doom, .backlog)
        h.clock.advance(days: 1)
        try h.journal.setIntent(zelda, .upNext)
        try h.journal.setChildhood(zelda, true)
        try h.journal.addPlaythrough(metroid, PlaythroughDraft(start: PartialDate("2024")!, outcome: .finished))
        try h.journal.addPlaythrough(doom, PlaythroughDraft(start: PartialDate("2026-09")!))
    }

    func names(_ filter: LibraryFilter = LibraryFilter(), sort: LibrarySort = .name, ascending: Bool = true) throws -> [String] {
        try h.journal.library(filter, sort: sort, ascending: ascending).map(\.name)
    }

    @Test func everyGameByNameWithWhatTheTableShows() throws {
        let rows = try h.journal.library(LibraryFilter(), sort: .name, ascending: true)

        #expect(rows.map(\.name) == ["A Link to the Past", "Doom", "Super Metroid"])
        let doomRow = rows[1]
        #expect(doomRow.platformName == "PC")
        #expect(doomRow.rating == nil)
        #expect(doomRow.intent == .backlog)
        #expect(doomRow.isPlaying)
        #expect(rows[2].outcomes == [.finished])
        #expect(rows.allSatisfy { $0.roms == .noROMs })
    }

    @Test func sortsByPlayedAndChildhood() throws {
        // Played: Playing, then Finished, then Dropped, then never played.
        #expect(try names(sort: .played, ascending: false) == ["Doom", "Super Metroid", "A Link to the Past"])
        #expect(try names(sort: .played, ascending: true) == ["A Link to the Past", "Super Metroid", "Doom"])
        #expect(try names(sort: .childhood, ascending: false) == ["A Link to the Past", "Doom", "Super Metroid"])
        #expect(!LibrarySort.played.defaultAscending)
        #expect(!LibrarySort.childhood.defaultAscending)
    }

    @Test func filtersCombine() throws {
        #expect(try names(LibraryFilter(platformId: 19)) == ["A Link to the Past", "Super Metroid"])
        #expect(try names(LibraryFilter(rating: .unrated)) == ["Doom"])
        #expect(try names(LibraryFilter(rating: .atLeast(Rating(tenths: 90)!))) == ["Super Metroid"])
        #expect(try names(LibraryFilter(intent: .some(.upNext))) == ["A Link to the Past"])
        #expect(try names(LibraryFilter(intent: .some(nil))) == ["Super Metroid"])
        #expect(try names(LibraryFilter(childhood: true)) == ["A Link to the Past"])
        #expect(try names(LibraryFilter(platformId: 19, childhood: false)) == ["Super Metroid"])
    }

    @Test func filtersByArchivablePlatforms() throws {
        try h.journal.addPlatform(id: ROMPlatform.ps2, name: "PS2")
        try h.journal.addPlatform(id: 7, name: "PlayStation")
        _ = try h.journal.addGame(platformId: ROMPlatform.ps2, name: "Ico")
        _ = try h.journal.addGame(platformId: 7, name: "Vagrant Story")

        #expect(try names(LibraryFilter(archivablePlatforms: true)) == ["Ico", "Vagrant Story"])
        #expect(try names(LibraryFilter(platformId: 7, archivablePlatforms: true)) == ["Vagrant Story"])
        #expect(try names(LibraryFilter(platformId: 19, archivablePlatforms: true)).isEmpty)
    }

    @Test func filtersByOutcome() throws {
        #expect(try names(LibraryFilter(outcome: .playing)) == ["Doom"])
        #expect(try names(LibraryFilter(outcome: .finished)) == ["Super Metroid"])
        #expect(try names(LibraryFilter(outcome: .dropped)).isEmpty)
        #expect(try names(LibraryFilter(outcome: .notPlayed)) == ["A Link to the Past"])
    }

    @Test func filtersByPlayableOrArchivedROMs() throws {
        try h.journal.recordROM(game: metroid, fileName: "Super Metroid (USA).sfc", missing: false)
        try h.journal.recordROM(game: metroid, fileName: "Super Metroid (Japan).7z", missing: false)
        try h.journal.recordROM(game: zelda, fileName: "A Link to the Past (USA).7z", missing: false)
        try h.journal.recordROM(game: zelda, fileName: "A Link to the Past (Japan).sfc", missing: true)
        try h.journal.recordROM(game: doom, fileName: "Doom.zip", missing: true)
        try h.journal.db.write { try $0.execute(sql: "UPDATE rom SET archived = 1 WHERE fileName LIKE '%.7z'") }

        #expect(try names(LibraryFilter(roms: .playable)) == ["Super Metroid"])
        #expect(try names(LibraryFilter(roms: .archived)) == ["A Link to the Past"])
    }

    @Test func eachRowSaysWhetherItsROMsArePlayableArchivedMissingOrNone() throws {
        try h.journal.recordROM(game: doom, fileName: "doom.zip", missing: true)
        try h.journal.recordROM(game: zelda, fileName: "z.sfc", missing: true)
        try h.journal.recordROM(game: zelda, fileName: "z2.7z", missing: false)
        try h.journal.recordROM(game: metroid, fileName: "m.7z", missing: false)
        try h.journal.db.write { try $0.execute(sql: "UPDATE rom SET archived = 1 WHERE fileName LIKE '%.7z'") }

        func states() throws -> [String: LibraryROMState] {
            Dictionary(
                uniqueKeysWithValues: try h.journal.library(LibraryFilter(), sort: .name, ascending: true).map { ($0.name, $0.roms) })
        }
        // A missing ROM wins over an Archived one beside it.
        #expect(try states() == ["Doom": .missing, "A Link to the Past": .missing, "Super Metroid": .archived])

        try h.journal.db.write { try $0.execute(sql: "UPDATE rom SET archived = 0") }
        #expect(try states()["Super Metroid"] == .playable)

        try h.journal.db.write { try $0.execute(sql: "DELETE FROM rom WHERE gameId = ?", arguments: [metroid]) }
        #expect(try states()["Super Metroid"] == .noROMs)
    }

    @Test func aRowOffersPlayWhenItHasAROMOnAPlatformWithAnEmulator() throws {
        try h.journal.recordROM(game: metroid, fileName: "Super Metroid (USA).sfc", missing: false)
        // Missing (or Archived), Play is still offered: it says why it can't open.
        try h.journal.recordROM(game: zelda, fileName: "A Link to the Past (USA).sfc", missing: true)
        // PC has no Emulator.
        try h.journal.recordROM(game: doom, fileName: "Doom.zip", missing: false)
        // No ROM.
        try h.journal.addGame(platformId: 19, name: "Chrono Trigger")

        let rows = try h.journal.library(LibraryFilter(), sort: .name, ascending: true)

        #expect(
            Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0.offersPlay) })
                == ["Super Metroid": true, "A Link to the Past": true, "Doom": false, "Chrono Trigger": false])
    }

    @Test func filtersByList() throws {
        let list = try h.journal.createList("Favourites")
        try h.journal.addToList(list, doom)

        #expect(try names(LibraryFilter(listId: list)) == ["Doom"])
    }

    @Test func filtersByPlayerOrSolo() throws {
        let alex = try h.journal.addPlayer(PlayerDraft(firstName: "Alex", lastName: "Smith", colour: .red))
        try h.journal.addPlaythrough(zelda, PlaythroughDraft(start: PartialDate("2020")!, players: [alex]))

        #expect(try names(LibraryFilter(player: .player(alex))) == ["A Link to the Past"])
        #expect(try names(LibraryFilter(player: .solo)) == ["Doom", "Super Metroid"])
    }

    @Test func sortsWithUnsetValuesLast() throws {
        #expect(try names(sort: .rating, ascending: false) == ["Super Metroid", "A Link to the Past", "Doom"])
        #expect(try names(sort: .rating, ascending: true) == ["A Link to the Past", "Super Metroid", "Doom"])
        #expect(try names(sort: .intentSet, ascending: false) == ["A Link to the Past", "Doom", "Super Metroid"])
        #expect(try names(sort: .platform) == ["Doom", "A Link to the Past", "Super Metroid"])
    }
}

@Suite struct GameDetailReadTests {
    let h: LudeumHarness
    let game: GameID

    init() throws {
        h = try LudeumHarness()
        game = try h.addGame("Resident Evil 2")
    }

    func rom(_ fileName: String, missing: Bool = false) throws {
        try h.journal.recordROM(game: game, fileName: fileName, missing: missing)
    }

    @Test func romsShowTheirVersion() throws {
        try rom("Resident Evil 2 (USA) (Disc 1) (Leon).chd")
        try rom("Resident Evil 2 (Japan).chd", missing: true)
        let roms = try h.journal.roms(of: game)

        #expect(roms.map(\.fileName) == ["Resident Evil 2 (USA) (Disc 1) (Leon).chd", "Resident Evil 2 (Japan).chd"])
        #expect(roms[0].version == "USA")
        #expect(roms[0].disc == 1)
        #expect(roms[1].missing)
    }

    @Test func theNameOverrideReadsBack() throws {
        #expect(try h.journal.nameOverride(game) == nil)
        try h.journal.setNameOverride(game, "RE2")
        #expect(try h.journal.nameOverride(game) == "RE2")
    }

    @Test func aDeletionSaysWhatGoesWithIt() throws {
        try rom("Resident Evil 2 (Japan).chd", missing: true)
        try h.journal.setRating(game, Rating(tenths: 90))
        try h.journal.addPlaythrough(game, PlaythroughDraft(start: PartialDate("2020")!, outcome: .finished))
        try h.journal.addToList(try h.journal.createList("Horror"), game)

        let summary = try h.journal.deletionSummary(game)

        #expect(summary == DeletionSummary(ratingEntries: 1, playthroughs: 1, lists: 1, roms: 1, copies: 0))
        // A missing ROM is a Copy, so it blocks deletion like any other.
        #expect(!summary.canDelete)
        try h.journal.deleteMissingROMs(of: game)
        #expect(try h.journal.deletionSummary(game).canDelete)
        try h.journal.addCopy(game, CopyDraft(kind: .physical))
        #expect(try h.journal.deletionSummary(game) == DeletionSummary(ratingEntries: 1, playthroughs: 1, lists: 1, roms: 0, copies: 1))
        #expect(try !h.journal.deletionSummary(game).canDelete)
    }
}

@Suite struct LibraryNameSearchTests {
    @Test func matchesAnyNameAGoesByIgnoringCaseAndTakingWildcardsLiterally() throws {
        let j = try LudeumHarness()
        try j.journal.addPlatform(id: 19, name: "SNES")
        try j.journal.addGame(platformId: 19, name: "Super Metroid (USA)", igdbGameId: 1, igdbName: "Super Metroid")
        let renamed = try j.journal.addGame(platformId: 19, name: "Zelda", igdbGameId: 2, igdbName: "The Legend of Zelda")
        try j.journal.setNameOverride(renamed, "Zelda 3")
        try j.journal.addGameByHand(name: "100% Orange Juice", platformId: 19)

        func search(_ text: String) throws -> [String] {
            try j.journal.library(LibraryFilter(name: text), sort: .name, ascending: true).map(\.name)
        }

        #expect(try search("metroid") == ["Super Metroid"])
        #expect(try search("legend") == ["Zelda 3"])
        #expect(try search("0%") == ["100% Orange Juice"])
        #expect(try search("_") == [])
        #expect(try search("  ").count == 3)
    }

    @Test func everyWordMustMatchInAnyOrderButNotTogether() throws {
        let j = try LudeumHarness()
        try j.journal.addPlatform(id: 29, name: "Mega Drive")
        try j.journal.addGame(platformId: 29, name: "Streets of Rage (World)", igdbGameId: 1, igdbName: "Streets of Rage")
        try j.journal.addGame(platformId: 29, name: "Rage", igdbGameId: 2, igdbName: "Rage")

        func search(_ text: String) throws -> [String] {
            try j.journal.library(LibraryFilter(name: text), sort: .name, ascending: true).map(\.name)
        }

        #expect(try search("streets rage") == ["Streets of Rage"])
        #expect(try search("rage  streets") == ["Streets of Rage"])
        #expect(try search("rage") == ["Rage", "Streets of Rage"])
        #expect(try search("streets doom").isEmpty)
    }
}

@Suite struct ScopedFilterTests {
    @Test func aScreensScopeWinsAndAddedFiltersCombineWithIt() {
        let scope = LibraryFilter(platformId: 19, outcome: .finished)
        let added = LibraryFilter(platformId: 4, rating: .unrated, childhood: true, genre: "Platform", name: "mario")

        let combined = added.scoped(by: scope)

        #expect(combined.platformId == 19)
        #expect(combined.outcome == .finished)
        #expect(combined.rating == .unrated)
        #expect(combined.childhood == true)
        #expect(combined.genre == "Platform")
        #expect(combined.name == "mario")
        #expect(LibraryFilter().scoped(by: LibraryFilter(series: "Metroid", company: "Nintendo")).series == "Metroid")
    }
}
