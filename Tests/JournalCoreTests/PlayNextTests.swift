import Foundation
import Testing

@testable import JournalCore

@Suite struct WhatToPlayNextTests {
    let h: JournalHarness

    init() throws {
        h = try JournalHarness()
    }

    func names(_ filter: LibraryFilter = LibraryFilter(), sort: LibrarySort? = nil, ascending: Bool = true) throws -> PlayNext<String> {
        try h.journal.whatToPlayNext(filter, sort: sort, ascending: ascending).map(\.name)
    }

    @Test func eachGameAppearsOnceInTheFirstSectionThatFits() throws {
        let playingAndUpNext = try h.addGame("Chrono Trigger")
        try h.journal.setIntent(playingAndUpNext, .upNext)
        try h.journal.addPlaythrough(playingAndUpNext, PlaythroughDraft(start: PartialDate("2026")))
        try h.journal.setIntent(try h.addGame("Earthbound"), .upNext)
        try h.journal.setIntent(try h.addGame("Secret of Mana"), .backlog)
        let finished = try h.addGame("Super Metroid")
        try h.journal.addPlaythrough(finished, PlaythroughDraft(outcome: .finished))
        _ = try h.addGame("F-Zero")

        let next = try names()

        #expect(next == PlayNext(playing: ["Chrono Trigger"], upNext: ["Earthbound"], backlog: ["Secret of Mana"]))
    }

    @Test func intentSectionsDefaultToNewestSetFirstWithUndatedLastByName() throws {
        try h.journal.importIntent(try h.addGame("Zelda"), .backlog)
        try h.journal.importIntent(try h.addGame("Actraiser"), .backlog)
        try h.journal.setIntent(try h.addGame("Older"), .backlog)
        h.clock.advance(days: 1)
        try h.journal.setIntent(try h.addGame("Newer"), .backlog)

        #expect(try names().backlog == ["Newer", "Older", "Actraiser", "Zelda"])
        #expect(try names(sort: .name).backlog == ["Actraiser", "Newer", "Older", "Zelda"])
    }

    @Test func playingDefaultsToTheLatestInProgressStartNewestFirst() throws {
        let twoRuns = try h.addGame("Doom")
        try h.journal.addPlaythrough(twoRuns, PlaythroughDraft(start: PartialDate("2020")))
        try h.journal.addPlaythrough(twoRuns, PlaythroughDraft(start: PartialDate("2026-03")))
        try h.journal.addPlaythrough(try h.addGame("Quake"), PlaythroughDraft(start: PartialDate("2026-01-15")))
        try h.journal.addPlaythrough(try h.addGame("Heretic"), PlaythroughDraft(start: PartialDate("2025")))
        let finishedLater = try h.addGame("Hexen")
        try h.journal.addPlaythrough(finishedLater, PlaythroughDraft(start: PartialDate("2019")))
        try h.journal.addPlaythrough(finishedLater, PlaythroughDraft(start: PartialDate("2026-09"), outcome: .finished))

        #expect(try names().playing == ["Doom", "Quake", "Heretic", "Hexen"])
        #expect(try h.journal.whatToPlayNext(LibraryFilter(), sort: nil, ascending: true).playing[0].playingSince == PartialDate("2026-03"))
    }

    @Test func theLibrarysFiltersAndSortsApply() throws {
        try h.journal.addPlatform(id: 6, name: "PC")
        let pc = try h.journal.addGame(platformId: 6, name: "Doom")
        try h.journal.setIntent(pc, .upNext)
        let snes = try h.addGame("Earthbound")
        try h.journal.setIntent(snes, .upNext)
        try h.journal.setRating(snes, Rating(tenths: 90))

        #expect(try names(LibraryFilter(platformId: 6)).upNext == ["Doom"])
        #expect(try names(sort: .rating, ascending: false).upNext == ["Earthbound", "Doom"])
    }

    @Test func startPlayingAddsAPlaythroughFromTodayAndClearsIntent() throws {
        let game = try h.addGame("Earthbound")
        try h.journal.setIntent(game, .upNext)

        try h.journal.startPlaying(game)

        let playthroughs = try h.journal.playthroughs(game)
        #expect(playthroughs.map(\.draft) == [PlaythroughDraft(start: PartialDate(h.journal.today()))])
        #expect(h.journal.today().count == 10)
        #expect(try names() == PlayNext(playing: ["Earthbound"], upNext: [], backlog: []))
        #expect(try h.journal.library(LibraryFilter(), sort: .name, ascending: true)[0].intent == nil)
    }
}

@Suite struct TopRatedTests {
    let h: JournalHarness

    init() throws {
        h = try JournalHarness()
    }

    func rated(_ name: String, _ tenths: Int) throws -> GameID {
        let game = try h.addGame(name)
        try h.journal.setRating(game, Rating(tenths: tenths))
        return game
    }

    @Test func everyRatedGameHighestFirstWithTiesSharingARankByName() throws {
        _ = try rated("Super Metroid", 95)
        _ = try rated("Zelda", 90)
        _ = try rated("Actraiser", 90)
        _ = try rated("Pit Fighter", 0)
        _ = try rated("Contra", 80)
        _ = try h.addGame("Unrated")

        let rows = try h.journal.topRated(LibraryFilter())

        #expect(rows.map(\.game.name) == ["Super Metroid", "Actraiser", "Zelda", "Contra", "Pit Fighter"])
        #expect(rows.map(\.rank) == [1, 2, 2, 4, 5])
    }

    @Test func aGameClearedToUnratedLeaves() throws {
        let game = try rated("Contra", 80)
        try h.journal.setRating(game, nil)

        #expect(try h.journal.topRated(LibraryFilter()).isEmpty)
    }

    @Test func importedRatingsAreMarkedUntilIReRate() throws {
        let game = try h.addGame("Contra")
        try h.journal.importRating(game, Rating(tenths: 60)!)
        #expect(try h.journal.topRated(LibraryFilter()).map(\.game.ratingImported) == [true])

        try h.journal.setRating(game, Rating(tenths: 70))

        #expect(try h.journal.topRated(LibraryFilter()).map(\.game.ratingImported) == [false])
    }

    @Test func theLibrarysFiltersApply() throws {
        try h.journal.addPlatform(id: 6, name: "PC")
        let doom = try h.journal.addGame(platformId: 6, name: "Doom")
        try h.journal.setRating(doom, Rating(tenths: 85))
        let contra = try rated("Contra", 80)
        try h.journal.setChildhood(contra, true)

        #expect(try h.journal.topRated(LibraryFilter(platformId: 6)).map(\.game.name) == ["Doom"])
        #expect(try h.journal.topRated(LibraryFilter(childhood: true)).map(\.game.name) == ["Contra"])
        #expect(try h.journal.topRated(LibraryFilter(platformId: 19)).map(\.rank) == [1])
    }
}
