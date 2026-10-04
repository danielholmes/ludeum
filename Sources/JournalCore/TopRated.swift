import Foundation

/// A Game on Top-rated, with its rank. Ties share a rank (1, 2, 2, 4).
public struct TopRatedRow: Sendable, Equatable, Identifiable {
    public let rank: Int
    public let game: LibraryRow
    public var id: GameID { game.id }
}

extension JournalStore {
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
