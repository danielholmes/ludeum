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
        try h.journal.addPlaythrough(metroid, PlaythroughDraft(start: PartialDate("2024"), outcome: .finished))
        try h.journal.addPlaythrough(doom, PlaythroughDraft(start: PartialDate("2026-09")))
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
        #expect(rows.allSatisfy { !$0.noROMInOpenEmu })
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

    @Test func filtersByOutcome() throws {
        #expect(try names(LibraryFilter(outcome: .playing)) == ["Doom"])
        #expect(try names(LibraryFilter(outcome: .finished)) == ["Super Metroid"])
        #expect(try names(LibraryFilter(outcome: .dropped)).isEmpty)
        #expect(try names(LibraryFilter(outcome: .notPlayed)) == ["A Link to the Past"])
    }

    @Test func aGameWhoseROMsAreAllMissingIsMarked() throws {
        try h.journal.recordROM(game: doom, openEmuPk: 1, md5: "a", fileName: "doom.zip", systemId: "x", missing: true)
        try h.journal.recordROM(game: zelda, openEmuPk: 2, md5: "b", fileName: "z.sfc", systemId: "x", missing: true)
        try h.journal.recordROM(game: zelda, openEmuPk: 3, md5: "c", fileName: "z2.sfc", systemId: "x", missing: false)

        let marked = try h.journal.library(LibraryFilter(), sort: .name, ascending: true).filter(\.noROMInOpenEmu).map(\.name)

        #expect(marked == ["Doom"])
    }

    @Test func filtersByList() throws {
        let list = try h.journal.createList("Favourites")
        try h.journal.addToList(list, doom)

        #expect(try names(LibraryFilter(listId: list)) == ["Doom"])
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

    func rom(_ pk: Int64, _ fileName: String, missing: Bool = false) throws {
        try h.journal.recordROM(
            game: game, openEmuPk: pk, md5: "\(pk)", fileName: fileName, systemId: "openemu.system.psx", missing: missing)
    }

    @Test func romsShowTheirVersion() throws {
        try rom(1, "Resident Evil 2 (USA) (Disc 1) (Leon).chd")
        try rom(2, "Resident Evil 2 (Japan).chd", missing: true)
        let roms = try h.journal.roms(of: game)

        #expect(roms.map(\.fileName) == ["Resident Evil 2 (USA) (Disc 1) (Leon).chd", "Resident Evil 2 (Japan).chd"])
        #expect(roms[0].version == "USA")
        #expect(roms[0].disc == 1)
        #expect(roms[1].missing)
    }

    @Test func versionSuggestionsComeFromTheGamesROMNames() throws {
        try rom(1, "Resident Evil 2 (USA) (Disc 1) (Leon).chd")
        try rom(2, "Resident Evil 2 (USA) (Disc 2) (Claire).chd")
        try rom(3, "Resident Evil 2 (Japan).chd")

        #expect(try h.journal.versionSuggestions(for: game) == ["Japan", "USA"])
    }

    @Test func theNameOverrideReadsBack() throws {
        #expect(try h.journal.nameOverride(game) == nil)
        try h.journal.setNameOverride(game, "RE2")
        #expect(try h.journal.nameOverride(game) == "RE2")
    }

    @Test func playedViaSuggestionsAreWhatIveUsedBefore() throws {
        let other = try h.addGame("Doom")
        try h.journal.addPlaythrough(other, PlaythroughDraft(outcome: .finished, playedVia: "Steam Deck"))
        try h.journal.addPlaythrough(other, PlaythroughDraft(outcome: .finished, playedVia: "Switch Online"))

        #expect(try h.journal.playedViaSuggestions(for: other) == ["Steam Deck", "Switch Online"])
        try rom(1, "Resident Evil 2 (USA).chd")
        #expect(try h.journal.playedViaSuggestions(for: game) == ["OpenEmu", "Steam Deck", "Switch Online"])
    }

    @Test func aDeletionSaysWhatGoesWithIt() throws {
        try rom(2, "Resident Evil 2 (Japan).chd", missing: true)
        try h.journal.setRating(game, Rating(tenths: 90))
        try h.journal.addPlaythrough(game, PlaythroughDraft(outcome: .finished))
        try h.journal.addToList(try h.journal.createList("Horror"), game)

        let summary = try h.journal.deletionSummary(game)

        #expect(summary == DeletionSummary(ratingEntries: 1, playthroughs: 1, lists: 1, missingROMs: 1, presentROMs: 0))
        #expect(summary.canDelete)
        try rom(3, "Resident Evil 2 (USA).chd")
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
        #expect(LibraryFilter(undatedPlaythroughs: true).scoped(by: LibraryFilter()).undatedPlaythroughs)
        #expect(LibraryFilter().scoped(by: LibraryFilter(series: "Metroid", company: "Nintendo")).series == "Metroid")
    }
}
