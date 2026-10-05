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

public struct YearSummary: Sendable, Equatable {
    public let finished: Int
    public let dropped: Int
    /// Playthroughs whose start date is in the year.
    public let started: Int
    /// Most Playthroughs first, then by name.
    public let platforms: [PlatformYear]
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

extension LudeumStore {
    /// The years with a Playthrough in them, newest first.
    public func yearsInReview(_ filter: LibraryFilter) throws -> [Int] {
        let games = Set(try library(filter, sort: .name, ascending: true).map(\.id))
        let current = calendar.component(.year, from: clock.now())
        var years = Set<Int>()
        for (game, p) in try allPlaythroughs() where games.contains(game) {
            years.formUnion(Self.years(of: p.draft, current: current))
        }
        return years.sorted(by: >)
    }

    public func yearInReview(_ year: Int, _ filter: LibraryFilter) throws -> YearInReview {
        let rows = Dictionary(uniqueKeysWithValues: try library(filter, sort: .name, ascending: true).map { ($0.id, $0) })
        let current = calendar.component(.year, from: clock.now())
        var finished: [YearPlaythrough] = []
        var dropped: [YearPlaythrough] = []
        var alsoPlayed: [YearPlaythrough] = []
        var started = 0
        for (game, p) in try allPlaythroughs() {
            guard let row = rows[game] else { continue }
            let d = p.draft
            if Self.year(d.start) == year { started += 1 }
            let span = Self.years(of: d, current: current)
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
        let summary = YearSummary(
            finished: finished.count, dropped: dropped.count, started: started,
            platforms: platforms.map { PlatformYear(name: $0.key, playthroughs: $0.value) }
                .sorted { ($0.playthroughs, $1.name) > ($1.playthroughs, $0.name) })
        return YearInReview(
            year: year, isCurrentYear: year == current, finished: sections[0], dropped: sections[1], alsoPlayed: sections[2],
            summary: summary)
    }

    // MARK: Which years

    private static func year(_ date: PartialDate) -> Int { Int(date.text.prefix(4))! }

    /// The years a Playthrough counts for: start year to end year (to `current` while in progress).
    /// Ended with no end date: its start year.
    static func years(of d: PlaythroughDraft, current: Int) -> ClosedRange<Int> {
        let start = year(d.start)
        if let end = d.end { return start...max(start, year(end)) }
        return d.outcome == nil ? start...max(start, current) : start...start
    }

    private func allPlaythroughs() throws -> [(GameID, Playthrough)] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM playthrough ORDER BY id").map { row in
                (
                    row["gameId"],
                    Playthrough(
                        id: row["id"],
                        PlaythroughDraft(
                            start: PartialDate(row["start"])!,
                            end: (row["end"] as String?).flatMap(PartialDate.init),
                            outcome: (row["outcome"] as String?).flatMap(Outcome.init(rawValue:)),
                            notes: row["notes"], version: row["version"], playedVia: row["playedVia"]))
                )
            }
        }
    }
}
