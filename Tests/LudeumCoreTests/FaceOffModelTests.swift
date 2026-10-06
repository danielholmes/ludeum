import Testing

@testable import LudeumCore

/// The Face-off model on its own: Ratings and Battles in, Disagreements and the next pair out.
@Suite struct FaceOffModelTests {
    private var games: [FaceOffGame] = []
    private var battles: [FaceOffBattle] = []

    @discardableResult
    private mutating func game(_ name: String, _ tenths: Int) -> GameID {
        let id = GameID(games.count + 1)
        games.append(FaceOffGame(id: id, name: name, platformName: "SNES", rating: Rating(tenths: tenths)!))
        return id
    }

    /// `winner` beat `loser` (or, with `same`, they were About the same), `day` days into the test.
    private mutating func battle(_ winner: GameID, beat loser: GameID, same: Bool = false, day: Int = 0) {
        battles.append(
            FaceOffBattle(id: Int64(battles.count + 1), a: winner, b: loser, result: same ? .same : .a, day: day))
    }

    private var skips: [FaceOffSkip] = []

    /// The names of the next pair, in name order.
    private func nextPair(today: Int = 0) -> [String]? {
        var rng = SeededGenerator()
        return FaceOffModel.nextPair(games: games, battles: battles, skips: skips, today: today, using: &rng)
            .map { [$0.left.name, $0.right.name].sorted() }
    }

    private func disagreements(today: Int = 0, kept: [GameID: Int64] = [:]) -> [Disagreement] {
        FaceOffModel.disagreements(games: games, battles: battles, today: today, kept: kept)
    }

    @Test mutating func aGameThatLosesToLowerRatedGamesIsRatedTooHigh() {
        let x = game("Rated too high", 90)
        for (name, tenths) in [("A", 80), ("B", 80), ("C", 75), ("D", 75)] { battle(game(name, tenths), beat: x) }
        for name in ["E", "F"] { battle(x, beat: game(name, 60)) }

        let found = disagreements()

        #expect(found.map(\.game.id) == [x])
        #expect(found[0].direction == .tooHigh)
        guard case .around(let from, let to) = found[0].placement else {
            Issue.record("expected a placement between two Ratings, got \(found[0].placement)")
            return
        }
        #expect(from > Rating(tenths: 60)! && to < Rating(tenths: 80)!)
    }

    @Test mutating func withNoWinYetItOnlySaysBelowTheLowestRatingItLostTo() {
        let x = game("Lost every time", 90)
        for (name, tenths) in [("A", 90), ("B", 90), ("C", 85), ("D", 85), ("E", 85)] { battle(game(name, tenths), beat: x) }

        #expect(disagreements().first { $0.game.id == x }?.placement == .below(Rating(tenths: 85)!))
    }

    @Test mutating func oneUpsetIsNotADisagreement() {
        let x = game("X", 80)
        battle(game("Rated lower", 70), beat: x)

        #expect(disagreements().isEmpty)
    }

    @Test mutating func preferringOneOfTwoEquallyRatedGamesEveryTimeIsADisagreement() {
        let x = game("Always preferred", 80)
        for name in ["A", "B", "C", "D", "E", "F"] { battle(x, beat: game(name, 80)) }

        #expect(disagreements().first?.game.id == x)
        #expect(disagreements().first?.direction == .tooLow)
    }

    @Test mutating func aboutTheSameAsGamesRatedFarHigherIsRatedTooLow() {
        let x = game("Underrated", 60)
        for name in ["A", "B", "C"] { battle(game(name, 85), beat: x, same: true) }

        let found = disagreements().first { $0.game.id == x }
        #expect(found?.direction == .tooLow)
        guard case .around(let from, _)? = found?.placement else {
            Issue.record("expected a placement between two Ratings, got \(String(describing: found?.placement))")
            return
        }
        #expect(from > Rating(tenths: 70)!)
    }

    @Test mutating func battlesFadeHalfAWeekSoOldEvidenceStopsFlagging() {
        let x = game("Rated too high, weeks ago", 90)
        for (name, tenths) in [("A", 80), ("B", 80), ("C", 75), ("D", 75)] { battle(game(name, tenths), beat: x) }
        for name in ["E", "F"] { battle(x, beat: game(name, 60)) }

        #expect(disagreements(today: 7).map(\.game.id) == [x])
        #expect(disagreements(today: 21).isEmpty)
    }

    @Test mutating func aKeptRatingIsSetAsideUntilItsGameFightsAnotherBattle() {
        let x = game("Kept", 90)
        for (name, tenths) in [("A", 80), ("B", 80), ("C", 75), ("D", 75)] { battle(game(name, tenths), beat: x) }
        for name in ["E", "F"] { battle(x, beat: game(name, 60)) }
        let kept = [x: battles.last!.id]

        battle(game("G", 50), beat: game("H", 40))
        #expect(disagreements(kept: kept).isEmpty)

        battle(game("I", 70), beat: x)
        #expect(disagreements(kept: kept).map(\.game.id) == [x])
    }

    @Test mutating func withNoBattlesItPairsTwoGamesWithTheSameRating() {
        for (name, tenths) in [("A", 90), ("B", 50), ("C", 90), ("D", 20)] { game(name, tenths) }

        #expect(nextPair() == ["A", "C"])
    }

    @Test mutating func anUpsetIsChasedBeforeUnfoughtGames() {
        let x = game("X", 80)
        battle(game("Y", 70), beat: x)
        for (name, tenths) in [("P", 50), ("Q", 50), ("R", 30), ("S", 30)] { game(name, tenths) }

        let pair = nextPair()

        #expect(pair?.contains("X") == true || pair?.contains("Y") == true)
    }

    @Test mutating func aPairIsntFoughtAgainWithinTwoWeeks() {
        battle(game("A", 70), beat: game("B", 70))

        #expect(nextPair(today: 13) == nil)
        #expect(nextPair(today: 14) == ["A", "B"])
    }

    @Test mutating func everyEighthPairOfADayIsFarApart() {
        let (a, b) = (game("A", 90), game("B", 90))
        for (name, tenths) in [("C", 89), ("D", 40)] { game(name, tenths) }
        for _ in 1...6 { battle(a, beat: b) }
        #expect(nextPair().map { $0.contains("D") } == false)

        battle(a, beat: b)
        #expect(nextPair()?.contains("D") == true)
    }

    @Test mutating func aSkippedPairStaysAwayForTheDay() {
        skips.append(FaceOffSkip(a: game("A", 90), b: game("B", 90), day: 0))

        #expect(nextPair(today: 0) == nil)
        #expect(nextPair(today: 1) == ["A", "B"])
    }

    @Test mutating func gamesIveSkippedAreOfferedLess() {
        let (a, b) = (game("A", 90), game("B", 90))
        for (name, tenths) in [("C", 70), ("D", 70)] { game(name, tenths) }
        skips.append(FaceOffSkip(a: a, b: b, day: 0))

        #expect(nextPair(today: 1) == ["C", "D"])
    }

    @Test mutating func aDisagreementShowsItsBattlesNewestFirstWithHowMuchEachStillCounts() {
        let x = game("X", 90)
        battle(x, beat: game("Old win", 60), day: 0)
        battle(x, beat: game("Win", 60), day: 7)
        for (day, name) in [(7, "A"), (7, "B"), (14, "C"), (14, "D")] { battle(game(name, 75), beat: x, day: day) }

        let evidence = disagreements(today: 14).first?.evidence.map { "\($0.opponent.name) \($0.outcome) \($0.counts)" }

        #expect(evidence == ["D lost 1.0", "C lost 1.0", "B lost 0.5", "A lost 0.5", "Win won 0.5", "Old win won 0.25"])
    }
}
