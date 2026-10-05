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
