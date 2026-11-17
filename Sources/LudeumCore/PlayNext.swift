import Foundation
import GRDB

/// What to play next: each Game once, in the first section that fits.
public struct PlayNext<Item> {
    /// A Playthrough in progress.
    public var playing: [Item]
    public var upNext: [Item]
    public var backlog: [Item]

    public init(playing: [Item], upNext: [Item], backlog: [Item]) {
        self.playing = playing
        self.upNext = upNext
        self.backlog = backlog
    }

    public func map<T>(_ transform: (Item) throws -> T) rethrows -> PlayNext<T> {
        PlayNext<T>(playing: try playing.map(transform), upNext: try upNext.map(transform), backlog: try backlog.map(transform))
    }
}

extension PlayNext: Equatable where Item: Equatable {}
extension PlayNext: Sendable where Item: Sendable {}

/// About how long some Games take to beat, main story only.
public struct BeatEstimate: Sendable, Equatable {
    public let seconds: Int
    /// How many of the Games have no time of their own, so were counted at the average.
    public let averaged: Int

    public init(seconds: Int, averaged: Int) {
        self.seconds = seconds
        self.averaged = averaged
    }
}

/// About how long each section of What to play next takes to beat, and all of them: the sections' sum.
public struct PlayNextBeatEstimates: Sendable, Equatable {
    public let playing: BeatEstimate
    public let upNext: BeatEstimate
    public let backlog: BeatEstimate
    public let total: BeatEstimate
    /// The average of the Games' known times: what each Game without one is counted at.
    public let averageSeconds: Int
}

extension PlayNext {
    /// How long each section takes to beat, from each Game's own time (`time`, in seconds), else the average of every
    /// section's known times. Nil when no Game has a time.
    public func beatEstimates(_ time: (Item) -> Int?) -> PlayNextBeatEstimates? {
        let times = map(time)
        let known = (times.playing + times.upNext + times.backlog).compactMap { $0 }
        guard !known.isEmpty else { return nil }
        let average = Double(known.reduce(0, +)) / Double(known.count)
        func estimate(_ times: [Int?]) -> BeatEstimate {
            let averaged = times.filter { $0 == nil }.count
            let seconds = Double(times.compactMap { $0 }.reduce(0, +)) + Double(averaged) * average
            return BeatEstimate(seconds: Int(seconds.rounded()), averaged: averaged)
        }
        let sections = [estimate(times.playing), estimate(times.upNext), estimate(times.backlog)]
        // Summed rather than worked out afresh, so the headings always add up to it.
        let total = BeatEstimate(seconds: sections.map(\.seconds).reduce(0, +), averaged: sections.map(\.averaged).reduce(0, +))
        return PlayNextBeatEstimates(
            playing: sections[0], upNext: sections[1], backlog: sections[2], total: total, averageSeconds: Int(average.rounded()))
    }
}

extension TimeToBeat {
    /// The main story alone: IGDB's rushed time, to the credits without the side quests.
    public var mainStory: Int? { hastily }
}

extension LudeumStore {
    /// What to play next, filtered like the Library. With no `sort`, Playing goes by the latest
    /// in-progress start and Up next and Backlog by when the Intent was set, newest first, with
    /// undated Intent last; ties go by name.
    public func whatToPlayNext(_ filter: LibraryFilter, sort: LibrarySort?, ascending: Bool) throws -> PlayNext<LibraryRow> {
        // With no sort, rows come by name and the stable sorts below keep name order for ties.
        let rows = try library(filter, sort: sort ?? .name, ascending: sort == nil ? true : ascending)
        var next = PlayNext<LibraryRow>(playing: [], upNext: [], backlog: [])
        for row in rows {
            if row.isPlaying {
                next.playing.append(row)
            } else if row.intent == .upNext {
                next.upNext.append(row)
            } else if row.intent == .backlog {
                next.backlog.append(row)
            }
        }
        if sort == nil {
            // Every in-progress Playthrough has a start, so `playingSince` is always set here.
            next.playing.sort { a, b in
                guard let a = a.playingSince, let b = b.playingSince else { return false }
                return a > b
            }
            let newestIntentFirst = { (a: LibraryRow, b: LibraryRow) -> Bool in
                switch (a.intentSetAt, b.intentSetAt) {
                case (let a?, let b?): a > b
                case (_?, nil): true
                default: false
                }
            }
            next.upNext.sort(by: newestIntentFirst)
            next.backlog.sort(by: newestIntentFirst)
        }
        return next
    }

    /// Starts playing in one step: an in-progress Playthrough from today (day precision), and no Intent.
    public func startPlaying(_ game: GameID) throws {
        try db.write { db in
            try db.execute(
                sql: "INSERT INTO playthrough (gameId, start) VALUES (?, ?)", arguments: [game, today()])
            try db.execute(sql: "UPDATE game SET intent = NULL, intentSetAt = NULL WHERE id = ?", arguments: [game])
        }
    }
}
