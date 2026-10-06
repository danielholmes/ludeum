import Foundation

/// A rated Game as a Face-off sees it.
public struct FaceOffGame: Sendable, Equatable, Identifiable {
    public let id: GameID
    public let name: String
    public let platformName: String
    public let rating: Rating

    public init(id: GameID, name: String, platformName: String, rating: Rating) {
        self.id = id
        self.name = name
        self.platformName = platformName
        self.rating = rating
    }
}

/// How a Battle went: Game `a` won, Game `b` won, or they were About the same.
public enum BattleResult: String, Sendable {
    case a, b, same
}

/// A Battle, fought on `day` (days since 1970, local).
public struct FaceOffBattle: Sendable, Equatable {
    public let id: Int64
    public let a: GameID
    public let b: GameID
    public let result: BattleResult
    public let day: Int

    public init(id: Int64, a: GameID, b: GameID, result: BattleResult, day: Int) {
        self.id = id
        self.a = a
        self.b = b
        self.result = result
        self.day = day
    }
}

/// A pair I skipped on `day`. It isn't a Battle: it only keeps the pair away for the day, and Games I keep skipping
/// are offered less.
public struct FaceOffSkip: Sendable, Equatable {
    public let a: GameID
    public let b: GameID
    public let day: Int

    public init(a: GameID, b: GameID, day: Int) {
        self.a = a
        self.b = b
        self.day = day
    }
}

/// The next two Games to Battle, in the order to show them.
public struct FaceOffPair: Sendable, Equatable {
    public let left: FaceOffGame
    public let right: FaceOffGame
}

/// A rated Game whose Battles consistently place it among different Ratings than the one it has.
public struct Disagreement: Sendable, Equatable, Identifiable {
    public enum Direction: Sendable { case tooHigh, tooLow }

    /// Where its Battles place it among the other Ratings. Until it has a Battle on the far side too (a win, or
    /// About the same, for one rated too high; a loss for one rated too low), only which way.
    public enum Placement: Sendable, Equatable {
        case around(Rating, Rating)
        case below(Rating)
        case above(Rating)
    }

    /// One of its Battles: who against, how it went for this Game, and how much it still counts (1 today, 0.5 a
    /// week on).
    public struct Evidence: Sendable, Equatable {
        public enum Outcome: String, Sendable { case won, lost, same }
        public let opponent: FaceOffGame
        public let outcome: Outcome
        public let counts: Double
    }

    public let game: FaceOffGame
    public let direction: Direction
    public let placement: Placement
    /// Its Battles, newest first.
    public let evidence: [Evidence]
    public var id: GameID { game.id }
}

/// The Face-off model. Each rated Game has a hidden place on the Rating scale, believed before any Battles to be
/// its Rating, give or take `priorSD`. Each Battle nudges the two Games' places (Bradley–Terry on the Rating scale;
/// About the same pulls them together). A Game is a Disagreement once it's fairly sure (`flagZ`) its place is on
/// the other side of its Rating. Tuned against a simulated me on branch `prototype/face-off`.
public enum FaceOffModel {
    /// How noisy my picks are, in Rating points: a 0.4 gap is picked right about 73% of the time.
    static let tau = 0.4
    /// About the same says the two are within about this much.
    static let sameSD = 0.3
    /// How far a Game's place may be from its Rating, before any Battles.
    static let priorSD = 0.5
    /// About 95% sure the Rating is on the wrong side of the Game's place.
    static let flagZ = 1.64
    /// A Battle counts half as much after a week, a quarter after two.
    static let halfLifeDays = 7.0

    /// A pair isn't fought again within this many days.
    static let repeatDays = 14
    /// Every 8th pair of a day is two Ratings at least `farApart` apart, to catch big errors.
    static let farApartEvery = 8
    static let farApart = 2.0
    /// How doubtful a Game's Rating must be (its `z`) to be chased.
    static let suspectZ = 0.3
    /// A suspect still unsettled after this many Battles in a day waits for another day.
    static let maxChasePerDay = 6

    /// How much a Battle fought on `day` counts on `today`.
    static func weight(day: Int, today: Int) -> Double { pow(0.5, Double(today - day) / halfLifeDays) }

    /// A Game's place: where its Battles put it (`mu`), how sure that is (`sd`), and how many standard deviations
    /// that is from its Rating (`z`, negative when it's rated too high).
    struct Place {
        let game: FaceOffGame
        let mu: Double
        let sd: Double
        var z: Double { (mu - game.rating.points) / sd }
    }

    /// Every Game's place, in the order of `games`. A Battle with a Game that isn't in `games` sits out.
    static func places(games: [FaceOffGame], battles: [FaceOffBattle], today: Int) -> [Place] {
        let index = Dictionary(uniqueKeysWithValues: games.enumerated().map { ($1.id, $0) })
        struct Edge {
            let a: Int
            let b: Int
            let result: BattleResult
            let weight: Double
        }
        var edges = Array(repeating: [Edge](), count: games.count)
        for battle in battles {
            guard let a = index[battle.a], let b = index[battle.b] else { continue }
            let edge = Edge(a: a, b: b, result: battle.result, weight: weight(day: battle.day, today: today))
            edges[a].append(edge)
            edges[b].append(edge)
        }
        var mu = games.map(\.rating.points)
        var precision = Array(repeating: 1 / (priorSD * priorSD), count: games.count)
        // Newton steps, one Game at a time, until nothing moves.
        for _ in 0..<100 {
            var biggest = 0.0
            for k in games.indices {
                var gradient = -(mu[k] - games[k].rating.points) / (priorSD * priorSD)
                var hessian = 1 / (priorSD * priorSD)
                for edge in edges[k] {
                    let other = edge.a == k ? edge.b : edge.a
                    let gap = mu[k] - mu[other]
                    if edge.result == .same {
                        gradient -= edge.weight * gap / (sameSD * sameSD)
                        hessian += edge.weight / (sameSD * sameSD)
                    } else {
                        let won = (edge.result == .a) == (edge.a == k) ? 1.0 : 0.0
                        let p = sigmoid(gap / tau)
                        gradient += edge.weight * (won - p) / tau
                        hessian += edge.weight * p * (1 - p) / (tau * tau)
                    }
                }
                let step = max(-1, min(1, gradient / hessian))
                mu[k] += step
                precision[k] = hessian
                biggest = max(biggest, abs(step))
            }
            if biggest < 1e-4 { break }
        }
        return games.indices.map { Place(game: games[$0], mu: mu[$0], sd: 1 / precision[$0].squareRoot()) }
    }

    /// The Disagreements, biggest gap first. `kept` holds each Kept Game's latest Battle when I Kept its Rating:
    /// it's set aside until it fights another.
    public static func disagreements(games: [FaceOffGame], battles: [FaceOffBattle], today: Int, kept: [GameID: Int64])
        -> [Disagreement]
    {
        let byId = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0) })
        return places(games: games, battles: battles, today: today)
            .filter { abs($0.z) >= flagZ && rounded($0.mu) != $0.game.rating }
            .filter { place in
                guard let keptAt = kept[place.game.id] else { return true }
                return battles.contains { $0.id > keptAt && ($0.a == place.game.id || $0.b == place.game.id) }
            }
            .sorted { abs($0.mu - $0.game.rating.points) > abs($1.mu - $1.game.rating.points) }
            .map { place in
                let direction: Disagreement.Direction = place.z < 0 ? .tooHigh : .tooLow
                let fought = battles.compactMap { battle in Fought(battle, for: place.game.id, among: byId, today: today) }
                return Disagreement(
                    game: place.game, direction: direction, placement: placement(direction, place.game, fought),
                    evidence: fought.reversed().map { .init(opponent: $0.opponent, outcome: $0.outcome, counts: $0.weight) })
            }
    }

    /// One of a Game's Battles from its side: the opponent's Rating, and whether it won, lost or was About the same.
    struct Fought {
        typealias Outcome = Disagreement.Evidence.Outcome
        let opponent: FaceOffGame
        let outcome: Outcome
        let weight: Double

        init?(_ battle: FaceOffBattle, for game: GameID, among games: [GameID: FaceOffGame], today: Int) {
            guard battle.a == game || battle.b == game,
                let opponent = games[battle.a == game ? battle.b : battle.a], games[game] != nil
            else { return nil }
            self.opponent = opponent
            outcome = battle.result == .same ? .same : (battle.result == .a) == (battle.a == game) ? .won : .lost
            weight = FaceOffModel.weight(day: battle.day, today: today)
        }
    }

    /// Where a Game's Battles place it among its opponents' Ratings, from those Battles alone (no pull back to its
    /// own Rating). Without a Battle on the far side its place has no bound that way, so only the direction is told:
    /// below the lowest Rating it lost to, or above the highest it beat.
    static func placement(_ direction: Disagreement.Direction, _ game: FaceOffGame, _ fought: [Fought]) -> Disagreement.Placement {
        let bounded = fought.contains { direction == .tooHigh ? $0.outcome != .lost : $0.outcome != .won }
        guard bounded else {
            switch direction {
            case .tooHigh:
                return .below(min(game.rating, fought.filter { $0.outcome == .lost }.map(\.opponent.rating).min() ?? game.rating))
            case .tooLow:
                return .above(max(game.rating, fought.filter { $0.outcome == .won }.map(\.opponent.rating).max() ?? game.rating))
            }
        }
        var place = game.rating.points
        var hessian = 1.0
        for _ in 0..<100 {
            var gradient = 0.0
            hessian = 1e-6
            for f in fought {
                let gap = place - f.opponent.rating.points
                switch f.outcome {
                case .same:
                    gradient -= f.weight * gap / (sameSD * sameSD)
                    hessian += f.weight / (sameSD * sameSD)
                case .won, .lost:
                    let p = sigmoid(gap / tau)
                    gradient += f.weight * ((f.outcome == .won ? 1 : 0) - p) / tau
                    hessian += f.weight * p * (1 - p) / (tau * tau)
                }
            }
            let step = max(-1, min(1, gradient / hessian))
            place = max(0, min(10, place + step))
            if abs(step) < 1e-4 { break }
        }
        let sd = 1 / hessian.squareRoot()
        return .around(rounded(place - sd), rounded(place + sd))
    }

    /// The next pair to show, or nil when every pair is kept away today. It chases the most doubtful suspect (a Game
    /// an Upset has put in doubt, or a Disagreement with no Battle on the far side yet) with the opponent that would
    /// say most about it; otherwise it covers the Games with least evidence first. Every 8th pair of a day is far
    /// apart instead.
    public static func nextPair(
        games: [FaceOffGame], battles: [FaceOffBattle], skips: [FaceOffSkip], today: Int,
        using rng: inout some RandomNumberGenerator
    ) -> FaceOffPair? {
        let games = games.sorted { $0.id < $1.id }
        let byId = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0) })
        let places = places(games: games, battles: battles, today: today)
        let keptAway = Set(
            battles.filter { today - $0.day < repeatDays }.map { Pair($0.a, $0.b) }
                + skips.filter { $0.day == today }.map { Pair($0.a, $0.b) })
        var evidence: [GameID: Double] = [:]
        var foughtToday: [GameID: Int] = [:]
        for battle in battles where byId[battle.a] != nil && byId[battle.b] != nil {
            for id in [battle.a, battle.b] {
                evidence[id, default: 0] += weight(day: battle.day, today: today)
                if battle.day == today { foughtToday[id, default: 0] += 1 }
            }
        }
        var skipped: [GameID: Double] = [:]
        for skip in skips { for id in [skip.a, skip.b] { skipped[id, default: 0] += weight(day: skip.day, today: today) } }
        let todays = battles.filter { $0.day == today }.count

        func settled(_ place: Place) -> Bool {
            guard abs(place.z) >= flagZ, rounded(place.mu) != place.game.rating else { return false }
            let fought = battles.compactMap { Fought($0, for: place.game.id, among: byId, today: today) }
            return fought.contains { place.z < 0 ? $0.outcome != .lost : $0.outcome != .won }
        }
        let suspect =
            places
            .filter { abs($0.z) >= suspectZ && foughtToday[$0.game.id, default: 0] < maxChasePerDay && !settled($0) }
            .max { abs($0.z) < abs($1.z) }
        let leastEvidence = places.map { evidence[$0.game.id, default: 0] + skipped[$0.game.id, default: 0] }.min() ?? 0
        func uncovered(_ place: Place) -> Bool {
            evidence[place.game.id, default: 0] + skipped[place.game.id, default: 0] <= leastEvidence + 0.5
        }

        func best(_ mode: Mode) -> (Place, Place)? {
            var best: (score: Double, x: Place, y: Place)?
            for i in places.indices {
                for j in places.indices where j > i {
                    let (x, y) = (places[i], places[j])
                    if keptAway.contains(Pair(x.game.id, y.game.id)) { continue }
                    let spread = x.sd * x.sd + y.sd * y.sd
                    let p = sigmoid((x.mu - y.mu) / (tau * tau + spread).squareRoot())
                    // How much one pick would settle about these two.
                    let information = p * (1 - p) * spread
                    let jitter = 1 + 0.05 * Double.random(in: 0..<1, using: &rng)
                    let score: Double
                    switch mode {
                    case .farApart:
                        guard abs(x.game.rating.points - y.game.rating.points) >= farApart else { continue }
                        score = spread * Double.random(in: 0..<1, using: &rng)
                    case .chase(let suspect):
                        guard x.game.id == suspect.game.id || y.game.id == suspect.game.id else { continue }
                        score = information * jitter
                    case .cover:
                        guard uncovered(x) || uncovered(y) else { continue }
                        score =
                            information * (uncovered(x) && uncovered(y) ? 1.5 : 1)
                            * pow(0.5, skipped[x.game.id, default: 0] + skipped[y.game.id, default: 0]) * jitter
                    }
                    if score > (best?.score ?? -1) { best = (score, x, y) }
                }
            }
            return best.map { ($0.x, $0.y) }
        }

        let modes: [Mode] =
            (todays + 1) % farApartEvery == 0 ? [.farApart, .cover] : suspect.map { [.chase($0), .cover] } ?? [.cover]
        var chosen: (Place, Place)?
        for mode in modes where chosen == nil { chosen = best(mode) }
        guard let (x, y) = chosen else { return nil }
        return Bool.random(using: &rng) ? FaceOffPair(left: x.game, right: y.game) : FaceOffPair(left: y.game, right: x.game)
    }

    /// Two Games, either way round.
    private struct Pair: Hashable {
        let a: GameID
        let b: GameID
        init(_ x: GameID, _ y: GameID) { (a, b) = x < y ? (x, y) : (y, x) }
    }

    /// What the next pair is for.
    private enum Mode {
        case farApart
        case chase(Place)
        case cover
    }

    static func sigmoid(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

    /// The nearest Rating to a place on the scale.
    static func rounded(_ points: Double) -> Rating { Rating(tenths: Int((max(0, min(10, points)) * 10).rounded()))! }
}

extension Rating {
    /// The Rating on the 0–10 scale.
    var points: Double { Double(tenths) / 10 }
}
