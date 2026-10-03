import Testing

@testable import JournalCore

@Suite struct RatingTests {
    let h: JournalHarness
    let game: GameID

    init() throws {
        h = try JournalHarness()
        game = try h.addGame()
    }

    private func history() throws -> [String] {
        try h.journal.ratingHistory(game).map {
            "\($0.day) \($0.rating.map { String($0.tenths) } ?? "unrated")\($0.imported ? " imported" : "")"
        }
    }

    @Test func aRatingIsTheLatestEntryInItsHistory() throws {
        try h.journal.setRating(game, Rating(tenths: 85))
        h.clock.advance(days: 3)
        try h.journal.setRating(game, Rating(tenths: 90))

        #expect(try h.journal.game(game).rating == Rating(tenths: 90))
        // The clock starts at 2027-01-15 19:00 in Sydney.
        #expect(try history() == ["2027-01-18 90", "2027-01-15 85"])
    }

    @Test func entriesAreDatedByTheLocalDay() throws {
        h.clock.advance(seconds: 6 * 3600)  // 01:00 the next day in Sydney, still the 15th in UTC

        try h.journal.setRating(game, Rating(tenths: 70))

        #expect(try history() == ["2027-01-16 70"])
    }

    @Test func changingItAgainTheSameDayReplacesThatDaysEntry() throws {
        try h.journal.setRating(game, Rating(tenths: 85))
        h.clock.advance(seconds: 3600)

        try h.journal.setRating(game, Rating(tenths: 80))

        #expect(try history() == ["2027-01-15 80"])
    }

    @Test func reEnteringTheCurrentValueDoesNothing() throws {
        try h.journal.setRating(game, Rating(tenths: 85))
        h.clock.advance(days: 2)

        try h.journal.setRating(game, Rating(tenths: 85))

        #expect(try history() == ["2027-01-15 85"])
    }

    @Test func zeroIsARatingAndClearingAddsAnUnratedEntry() throws {
        try h.journal.setRating(game, Rating(tenths: 0))
        #expect(try h.journal.game(game).rating == Rating(tenths: 0))
        h.clock.advance(days: 1)

        try h.journal.setRating(game, nil)

        #expect(try h.journal.game(game).rating == nil)
        #expect(try history() == ["2027-01-16 unrated", "2027-01-15 0"])
    }

    @Test func anImportedRatingIsNeverReplacedAndRatingThatDayIsCurrent() throws {
        try h.journal.importRating(game, Rating(tenths: 60)!)
        #expect(try h.journal.game(game).ratingImported)

        try h.journal.setRating(game, Rating(tenths: 75))

        #expect(try h.journal.game(game).rating == Rating(tenths: 75))
        #expect(try !h.journal.game(game).ratingImported)
        #expect(try history() == ["2027-01-15 75", "2027-01-15 60 imported"])
    }

    @Test func deletingTheLatestEntryMakesThePreviousOneTheRating() throws {
        try h.journal.setRating(game, Rating(tenths: 85))
        h.clock.advance(days: 1)
        try h.journal.setRating(game, Rating(tenths: 40))

        try h.journal.deleteRatingEntry(h.journal.ratingHistory(game)[0].id)

        #expect(try h.journal.game(game).rating == Rating(tenths: 85))
        #expect(try history() == ["2027-01-15 85"])
    }

    @Test func refusesRatingsOutsideZeroToTen() {
        #expect(Rating(tenths: 101) == nil)
        #expect(Rating(tenths: -1) == nil)
        #expect(Rating(tenths: 100) != nil)
    }
}
