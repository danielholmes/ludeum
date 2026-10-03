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

/// A Game on Top-rated, with its rank. Ties share a rank (1, 2, 2, 4).
public struct TopRatedRow: Sendable, Equatable, Identifiable {
    public let rank: Int
    public let game: LibraryRow
    public var id: GameID { game.id }
}

extension JournalStore {
    /// What to play next, filtered like the Library. With no `sort`, Playing goes by the latest
    /// in-progress start and Up next and Backlog by when the Intent was set, newest first, with
    /// undated Intent last; ties go by name.
    public func whatToPlayNext(_ filter: LibraryFilter, sort: LibrarySort?, ascending: Bool) throws -> PlayNext<LibraryRow> {
        let rows = try library(filter, sort: sort ?? .intentSet, ascending: sort == nil ? false : ascending)
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
                let since = (a.playingSince?.text ?? "", b.playingSince?.text ?? "")
                if since.0 != since.1 { return since.0 > since.1 }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
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

    /// Every rated Game matching `filter`, by current Rating, highest first; ties by name.
    /// A Rating of 0.0 counts; unrated Games never appear.
    public func topRated(_ filter: LibraryFilter) throws -> [TopRatedRow] {
        let rows = try library(filter, sort: .rating, ascending: false).filter { $0.rating != nil }
        var ranked: [TopRatedRow] = []
        for (index, row) in rows.enumerated() {
            let rank = index > 0 && rows[index - 1].rating == row.rating ? ranked[index - 1].rank : index + 1
            ranked.append(TopRatedRow(rank: rank, game: row))
        }
        return ranked
    }
}
