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

/// A Game's tracked OpenEmu play time credited to one year.
public struct GamePlayTime: Sendable, Equatable, Identifiable {
    public let game: LibraryRow
    public let seconds: Double
    public var id: GameID { game.id }
}

public struct PlatformYear: Sendable, Equatable {
    public let name: String
    /// Playthroughs under Finished, Dropped or Also played.
    public let playthroughs: Int
    public let playTimeSeconds: Double
}

public struct YearSummary: Sendable, Equatable {
    public let finished: Int
    public let dropped: Int
    /// Playthroughs whose start date is in the year.
    public let started: Int
    public let playTimeSeconds: Double
    /// Most Playthroughs first, then most play time, then by name.
    public let platforms: [PlatformYear]
}

/// One year: Finished, Dropped, Also played, OpenEmu play time and summary numbers.
public struct YearInReview: Sendable, Equatable {
    public let year: Int
    /// The current year is labelled "so far".
    public let isCurrentYear: Bool
    public let finished: [YearPlaythrough]
    public let dropped: [YearPlaythrough]
    public let alsoPlayed: [YearPlaythrough]
    /// Most first.
    public let playTime: [GamePlayTime]
    public let summary: YearSummary
    /// Playthroughs (matching the filter) with no dates, which appear in no year.
    public let undatedPlaythroughs: Int
}

extension JournalStore {
    /// The years with something in them (a Playthrough or tracked play time), newest first.
    public func yearsInReview(_ filter: LibraryFilter) throws -> [Int] {
        let games = Set(try library(filter, sort: .name, ascending: true).map(\.id))
        let current = calendar.component(.year, from: clock.now())
        var years = Set<Int>()
        for (game, p) in try allPlaythroughs() where games.contains(game) {
            if let span = Self.years(of: p.draft, current: current) { years.formUnion(span) }
        }
        for (game, byYear) in try playTimeCredits() where games.contains(game) {
            years.formUnion(byYear.filter { $0.value > 0 }.keys)
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
        var undated = 0
        for (game, p) in try allPlaythroughs() {
            guard let row = rows[game] else { continue }
            let d = p.draft
            if d.start == nil, d.end == nil { undated += 1 }
            if Self.year(d.start) == year { started += 1 }
            guard let span = Self.years(of: d, current: current), span.contains(year) else { continue }
            let entry = YearPlaythrough(game: row, playthrough: p, endDateUnknown: d.outcome != nil && d.end == nil)
            switch year == span.upperBound ? d.outcome : nil {
            case .finished: finished.append(entry)
            case .dropped: dropped.append(entry)
            case nil: alsoPlayed.append(entry)
            }
        }
        let playTime = try playTimeCredits().compactMap { game, byYear -> GamePlayTime? in
            guard let row = rows[game], let seconds = byYear[year], seconds > 0 else { return nil }
            return GamePlayTime(game: row, seconds: seconds)
        }
        .sorted { ($0.seconds, $1.game.name.lowercased()) > ($1.seconds, $0.game.name.lowercased()) }

        // By end (else start) date, then name.
        let byEnd: (YearPlaythrough, YearPlaythrough) -> Bool = {
            let a = $0.playthrough.draft
            let b = $1.playthrough.draft
            return ((a.end ?? a.start)?.text ?? "", $0.game.name.lowercased()) < ((b.end ?? b.start)?.text ?? "", $1.game.name.lowercased())
        }
        let sections = [finished, dropped, alsoPlayed].map { $0.sorted(by: byEnd) }
        var platforms: [String: (playthroughs: Int, seconds: Double)] = [:]
        for entry in sections.joined() { platforms[entry.game.platformName, default: (0, 0)].playthroughs += 1 }
        for entry in playTime { platforms[entry.game.platformName, default: (0, 0)].seconds += entry.seconds }
        let summary = YearSummary(
            finished: finished.count, dropped: dropped.count, started: started,
            playTimeSeconds: playTime.map(\.seconds).reduce(0, +),
            platforms: platforms.map { PlatformYear(name: $0.key, playthroughs: $0.value.playthroughs, playTimeSeconds: $0.value.seconds) }
                .sorted { ($0.playthroughs, $0.playTimeSeconds, $1.name) > ($1.playthroughs, $1.playTimeSeconds, $0.name) })
        return YearInReview(
            year: year, isCurrentYear: year == current, finished: sections[0], dropped: sections[1], alsoPlayed: sections[2],
            playTime: playTime, summary: summary, undatedPlaythroughs: undated)
    }

    /// The Game's play time in the first Import's snapshot, which has no year.
    public func playTimeBeforeTracking(_ game: GameID) throws -> Double {
        try db.read { db in
            try Double.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(SUM(a.playTimeSeconds), 0) FROM activitySnapshot a
                    JOIN import i ON i.id = a.importId AND i.isFirst
                    JOIN rom r ON r.id = a.romId WHERE r.gameId = ?
                    """, arguments: [game]) ?? 0
        }
    }

    // MARK: Which years

    private static func year(_ date: PartialDate?) -> Int? { date.flatMap { Int($0.text.prefix(4)) } }

    /// The years a Playthrough counts for: start year to end year (to `current` while in progress).
    /// Ended with no end date: its start year. No start date: its end year. No dates: none.
    static func years(of d: PlaythroughDraft, current: Int) -> ClosedRange<Int>? {
        switch (year(d.start), year(d.end)) {
        case (let start?, let end?): start...max(start, end)
        case (let start?, nil): d.outcome == nil ? start...max(start, current) : start...start
        case (nil, let end?): end...end
        case (nil, nil): nil
        }
    }

    private func allPlaythroughs() throws -> [(GameID, Playthrough)] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM playthrough ORDER BY id").map { row in
                (
                    row["gameId"],
                    Playthrough(
                        id: row["id"],
                        PlaythroughDraft(
                            start: (row["start"] as String?).flatMap(PartialDate.init),
                            end: (row["end"] as String?).flatMap(PartialDate.init),
                            outcome: (row["outcome"] as String?).flatMap(Outcome.init(rawValue:)),
                            notes: row["notes"], version: row["version"], playedVia: row["playedVia"]))
                )
            }
        }
    }

    // MARK: Crediting Activity

    /// Tracked play time per Game per year. Per ROM, the time added since its previous snapshot
    /// goes to one year: the Imports' year if both are in it, else the year of the ROM's
    /// last-played date at the later snapshot. A ROM first seen after the first Import counts from
    /// zero since the previous Import. Time going down credits nothing and resets the baseline.
    /// Snapshot rows exist only for new or changed ROMs, so a missing ROM simply adds nothing.
    func playTimeCredits() throws -> [GameID: [Int: Double]] {
        try db.read { db in
            let imports = try Row.fetchAll(db, sql: "SELECT id, startedAt, isFirst FROM import ORDER BY startedAt, id")
            let importIDs = imports.map { $0["id"] as Int64 }
            let importAt = Dictionary(uniqueKeysWithValues: imports.map { ($0["id"] as Int64, $0["startedAt"] as Date) })
            let firstImports = Set(imports.filter { $0["isFirst"] }.map { $0["id"] as Int64 })
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT r.gameId, a.romId, a.importId, a.lastPlayedAt, a.playTimeSeconds
                    FROM activitySnapshot a JOIN rom r ON r.id = a.romId
                    WHERE r.gameId IS NOT NULL
                    """)
            var credits: [GameID: [Int: Double]] = [:]
            for (_, snapshots) in Dictionary(grouping: rows, by: { $0["romId"] as Int64 }) {
                let ordered = snapshots.sorted { importIDs.firstIndex(of: $0["importId"])! < importIDs.firstIndex(of: $1["importId"])! }
                var previous: (at: Date, seconds: Double)?
                for s in ordered {
                    let importId: Int64 = s["importId"]
                    let at = importAt[importId]!
                    let seconds: Double = s["playTimeSeconds"]
                    defer { previous = (at, seconds) }
                    if previous == nil, firstImports.contains(importId) { continue }  // before tracking
                    // A ROM first seen later: from zero, since the Import before this one.
                    let base =
                        previous
                        ?? importIDs.firstIndex(of: importId).flatMap { $0 > 0 ? (importAt[importIDs[$0 - 1]]!, 0) : nil }
                        ?? (at, 0)
                    let added = seconds - base.seconds
                    guard added > 0 else { continue }
                    let before = calendar.component(.year, from: base.at)
                    let after = calendar.component(.year, from: at)
                    let lastPlayed = (s["lastPlayedAt"] as Date?).map { calendar.component(.year, from: $0) }
                    let year = before == after ? after : lastPlayed ?? after
                    credits[s["gameId"], default: [:]][year, default: 0] += added
                }
            }
            return credits
        }
    }
}
