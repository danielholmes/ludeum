import Foundation
import GRDB

/// A Playthrough as one year's review shows it, with its Game.
public struct YearPlaythrough: Sendable, Equatable, Identifiable {
    public let game: LibraryRow
    public let playthrough: Playthrough
    /// Ended, with a start date but no end date: counted in its start year.
    public let endDateUnknown: Bool
    public var id: Int64 { playthrough.id }
}

public struct PlatformYear: Sendable, Equatable {
    public let name: String
    /// Playthroughs under Finished, Dropped or Also played.
    public let playthroughs: Int
}

public struct PlayerYear: Sendable, Equatable {
    public let player: Player
    /// Playthroughs under Finished, Dropped or Also played that include them.
    public let playthroughs: Int
}

public struct YearSummary: Sendable, Equatable {
    public let finished: Int
    public let dropped: Int
    /// Playthroughs whose start date is in the year.
    public let started: Int
    /// Most Playthroughs first, then by name.
    public let platforms: [PlatformYear]
    /// Most Playthroughs first, then by name.
    public let players: [PlayerYear]
    /// Playthroughs with no Players, and with at least one.
    public let solo: Int
    public let withOthers: Int
}

/// One year: Finished, Dropped, Also played and summary numbers.
public struct YearInReview: Sendable, Equatable {
    public let year: Int
    /// The current year is labelled "so far".
    public let isCurrentYear: Bool
    public let finished: [YearPlaythrough]
    public let dropped: [YearPlaythrough]
    public let alsoPlayed: [YearPlaythrough]
    public let summary: YearSummary
}

/// Year in review in one read: the years with a Playthrough in them, how many each Finished, and one of them in full.
public struct ReviewedYears: Sendable, Equatable {
    /// Newest first.
    public let years: [Int]
    /// Finished Playthroughs by year.
    public let finished: [Int: Int]
    /// The year asked for, or the newest when that one has nothing in it; nil when no year has.
    public let shown: YearInReview?
}

extension LudeumStore {
    /// The years with a Playthrough in them, newest first.
    public func yearsInReview(_ filter: LibraryFilter) throws -> [Int] { try reviewSource(filter).years }

    public func yearInReview(_ year: Int, _ filter: LibraryFilter) throws -> YearInReview { try reviewSource(filter).review(year) }

    /// Everything the Year in review screen shows, from one read of the Library and its Playthroughs however many
    /// years there are.
    public func yearsInReview(_ filter: LibraryFilter, showing year: Int?) throws -> ReviewedYears {
        let source = try reviewSource(filter)
        let years = source.years
        var finished: [Int: Int] = [:]
        for (_, p) in source.playthroughs where p.draft.outcome == .finished {
            finished[Self.years(of: p.draft, current: source.current).upperBound, default: 0] += 1
        }
        let shown = year.flatMap { years.contains($0) ? $0 : nil } ?? years.first
        return ReviewedYears(years: years, finished: finished, shown: shown.map(source.review))
    }

    private func reviewSource(_ filter: LibraryFilter) throws -> ReviewSource {
        let rows = Dictionary(uniqueKeysWithValues: try library(filter, sort: .name, ascending: true).map { ($0.id, $0) })
        let playthroughs = try db.read { db in try Self.playthroughs(db).sorted { $0.1.id < $1.1.id } }
        return ReviewSource(
            rows: rows, playthroughs: playthroughs.filter { rows[$0.0] != nil }, players: try players(),
            current: calendar.component(.year, from: clock.now()))
    }

    // MARK: Which years

    fileprivate static func year(_ date: PartialDate) -> Int { Int(date.text.prefix(4))! }

    /// The years a Playthrough counts for: start year to end year (to `current` while in progress).
    /// Ended with no end date: its start year.
    static func years(of d: PlaythroughDraft, current: Int) -> ClosedRange<Int> {
        let start = year(d.start)
        if let end = d.end { return start...max(start, year(end)) }
        return d.outcome == nil ? start...max(start, current) : start...start
    }
}

/// The Library's Games (with a filter) and their Playthroughs, read once to review any number of years from.
private struct ReviewSource {
    let rows: [GameID: LibraryRow]
    /// Those Games' Playthroughs, oldest first.
    let playthroughs: [(GameID, Playthrough)]
    let players: [Player]
    let current: Int

    /// The years with a Playthrough in them, newest first.
    var years: [Int] {
        var years = Set<Int>()
        for (_, p) in playthroughs { years.formUnion(LudeumStore.years(of: p.draft, current: current)) }
        return years.sorted(by: >)
    }

    func review(_ year: Int) -> YearInReview {
        var finished: [YearPlaythrough] = []
        var dropped: [YearPlaythrough] = []
        var alsoPlayed: [YearPlaythrough] = []
        var started = 0
        for (game, p) in playthroughs {
            guard let row = rows[game] else { continue }
            let d = p.draft
            if LudeumStore.year(d.start) == year { started += 1 }
            let span = LudeumStore.years(of: d, current: current)
            guard span.contains(year) else { continue }
            let entry = YearPlaythrough(game: row, playthrough: p, endDateUnknown: d.outcome != nil && d.end == nil)
            switch year == span.upperBound ? d.outcome : nil {
            case .finished: finished.append(entry)
            case .dropped: dropped.append(entry)
            case nil: alsoPlayed.append(entry)
            }
        }
        // By end (else start) date, then name.
        let byEnd: (YearPlaythrough, YearPlaythrough) -> Bool = {
            let a = $0.playthrough.draft
            let b = $1.playthrough.draft
            return ((a.end ?? a.start).text, $0.game.name.lowercased()) < ((b.end ?? b.start).text, $1.game.name.lowercased())
        }
        let sections = [finished, dropped, alsoPlayed].map { $0.sorted(by: byEnd) }
        var platforms: [String: Int] = [:]
        for entry in sections.joined() { platforms[entry.game.platformName, default: 0] += 1 }
        var perPlayer: [Int64: Int] = [:]
        for entry in sections.joined() { for id in entry.playthrough.draft.players { perPlayer[id, default: 0] += 1 } }
        let solo = sections.joined().count { $0.playthrough.draft.players.isEmpty }
        let summary = YearSummary(
            finished: finished.count, dropped: dropped.count, started: started,
            platforms: platforms.map { PlatformYear(name: $0.key, playthroughs: $0.value) }
                .sorted { ($0.playthroughs, $1.name) > ($1.playthroughs, $0.name) },
            players: players.compactMap { p in perPlayer[p.id].map { PlayerYear(player: p, playthroughs: $0) } }
                .enumerated().sorted { ($0.element.playthroughs, $1.offset) > ($1.element.playthroughs, $0.offset) }.map(\.element),
            solo: solo, withOthers: sections.joined().count - solo)
        return YearInReview(
            year: year, isCurrentYear: year == current, finished: sections[0], dropped: sections[1], alsoPlayed: sections[2],
            summary: summary)
    }
}
