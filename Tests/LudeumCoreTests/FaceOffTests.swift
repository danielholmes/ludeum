import Foundation
import Testing

@testable import LudeumCore

/// Face-off through the journal: Battles, Skips, Undo and Keep are kept, and read back as Disagreements.
@Suite struct FaceOffTests {
    let h: LudeumHarness

    init() throws { h = try LudeumHarness() }

    private func rated(_ name: String, _ tenths: Int) throws -> GameID {
        let id = try h.addGame(name)
        try h.journal.setRating(id, Rating(tenths: tenths))
        return id
    }

    private func pair(_ left: GameID, _ right: GameID) throws -> FaceOffPair {
        let games = try h.journal.faceOffGames()
        return FaceOffPair(left: games.first { $0.id == left }!, right: games.first { $0.id == right }!)
    }

    /// `winner` beats `loser`.
    @discardableResult
    private func battle(_ winner: GameID, beat loser: GameID) throws -> FaceOffPick {
        try h.journal.recordBattle(pair(winner, loser), .a)
    }

    /// Rated 9.0, but loses to two 8.0s and two 7.5s and beats two 6.0s.
    private func ratedTooHigh() throws -> GameID {
        let x = try rated("Rated too high", 90)
        for (name, tenths) in [("A", 80), ("B", 80), ("C", 75), ("D", 75)] { try battle(rated(name, tenths), beat: x) }
        for name in ["E", "F"] { try battle(x, beat: rated(name, 60)) }
        return x
    }

    @Test func battlesFindADisagreementAndSettingItsRatingSettlesIt() throws {
        let x = try ratedTooHigh()
        #expect(try h.journal.disagreements().map(\.game.id) == [x])

        try h.journal.setRating(x, Rating(tenths: 70))

        #expect(try h.journal.disagreements().isEmpty)
    }

    @Test func undoTakesBackAMisPressedBattle() throws {
        let x = try ratedTooHigh()
        let misPress = try battle(rated("G", 50), beat: x)
        #expect(try h.journal.battlesToday() == 7)

        try h.journal.undo(misPress)

        #expect(try h.journal.battlesToday() == 6)
    }

    @Test func undoTakesBackASkipSoThePairCanComeBackToday() throws {
        let (a, b) = (try rated("A", 70), try rated("B", 70))
        var rng = SeededGenerator()
        let skipped = try h.journal.skip(pair(a, b))
        #expect(try h.journal.nextFaceOffPair(using: &rng) == nil)

        try h.journal.undo(skipped)

        #expect(try h.journal.nextFaceOffPair(using: &rng).map { Set([$0.left.id, $0.right.id]) } == [a, b])
    }

    @Test func aKeptRatingStaysAsideAcrossLaunchesUntilItsGameFightsAgain() throws {
        let x = try ratedTooHigh()
        try h.journal.keepRating(x)
        try h.reopen()
        #expect(try h.journal.disagreements().isEmpty)

        try battle(rated("G", 70), beat: x)

        #expect(try h.journal.disagreements().map(\.game.id) == [x])
    }

    @Test func anUnratedGameSitsOutButKeepsItsBattlesForWhenItsRatedAgain() throws {
        let x = try ratedTooHigh()
        h.clock.advance(days: 1)
        try h.journal.setRating(x, nil)
        #expect(try h.journal.disagreements().isEmpty)
        #expect(try !h.journal.faceOffGames().contains { $0.id == x })

        h.clock.advance(days: 1)
        try h.journal.setRating(x, Rating(tenths: 90))

        #expect(try h.journal.disagreements().map(\.game.id) == [x])
    }

    @Test func deletingAGameDeletesItsBattles() throws {
        let x = try ratedTooHigh()

        try h.journal.deleteGame(x)

        #expect(try h.journal.battlesToday() == 0)
    }

    @Test func battlesCountHalfAWeekOfLocalDaysLater() throws {
        let x = try ratedTooHigh()
        h.clock.advance(days: 7)

        #expect(try h.journal.disagreements().first { $0.game.id == x }?.evidence.map(\.counts) == Array(repeating: 0.5, count: 6))
    }
}
