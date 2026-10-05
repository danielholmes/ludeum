import Foundation

/// IGDB's genres, themes, franchises, series and companies for linked Games, from their cached records. They live in the cache,
/// not the journal, so the Library filters on them after its query.
public struct LibraryFacts: Sendable {
    let igdb: IGDBClient

    public init(igdb: IGDBClient) { self.igdb = igdb }

    /// Each Game's facts, by IGDB game id. Games IGDB doesn't know are absent.
    public func byGame(_ igdbGameIDs: [Int64]) async throws -> [Int64: GameFacts] {
        let records = try await igdb.games(ids: igdbGameIDs.map(Int.init))
        return Dictionary(uniqueKeysWithValues: records.map { (Int64($0.key), $0.value.facts) })
    }
}

extension Array where Element == LibraryRow {
    /// The rows matching the filter's IGDB facts: genre, theme, franchise and series (each ignored
    /// when nil). Unlinked Games have none.
    public func having(_ filter: LibraryFilter, in facts: [Int64: GameFacts]) -> [LibraryRow] {
        guard filter.usesIGDBFacts else { return self }
        return self.filter { row in
            guard let f = row.igdbGameId.flatMap({ facts[$0] }) else { return false }
            return filter.genre.map(f.genres.contains) ?? true && filter.theme.map(f.themes.contains) ?? true
                && filter.franchise.map(f.franchises.contains) ?? true && filter.series.map(f.series.contains) ?? true
                && filter.company.map(f.companies.contains) ?? true
        }
    }
}

extension [LibraryRow] {
    /// The rows with IGDB's release year and players' rating filled in from the facts.
    public func withIGDBFacts(_ facts: [Int64: GameFacts]) -> [LibraryRow] {
        map { row in
            var row = row
            let f = row.igdbGameId.flatMap { facts[$0] }
            row.releaseYear = f?.releaseYear
            row.playerScore = f?.playerScore
            return row
        }
    }
}

extension LibraryFilter {
    /// Whether it filters on facts from the cache, which `having(_:in:)` applies.
    public var usesIGDBFacts: Bool { genre != nil || theme != nil || franchise != nil || series != nil || company != nil }
}

extension GameFacts {
    /// Whether a company, franchise, series or keyword contains `text`, ignoring case.
    func mentions(_ text: String) -> Bool {
        credits.contains { $0.name.localizedCaseInsensitiveContains(text) }
            || franchises.contains { $0.localizedCaseInsensitiveContains(text) }
            || series.contains { $0.localizedCaseInsensitiveContains(text) }
            || keywords.contains { $0.localizedCaseInsensitiveContains(text) }
    }
}

extension LudeumStore {
    /// The Library with the IGDB facts applied: the filter's genre, theme, franchise, series and
    /// company, and a search that also matches the Game's companies, franchises and series. It stops
    /// early with `CancellationError` when its task is cancelled (a newer search replaced it).
    public func library(_ filter: LibraryFilter, sort: LibrarySort, ascending: Bool, facts: [Int64: GameFacts]) throws
        -> [LibraryRow]
    {
        let rows = try matching(filter, sort: sort, ascending: ascending, facts: facts).withIGDBFacts(facts)
        switch sort {
        case .year: return rows.sorted(by: { $0.releaseYear.map(Double.init) }, ascending: ascending)
        case .players: return rows.sorted(by: { $0.playerScore.flatMap { $0.isReliable ? $0.score : nil } }, ascending: ascending)
        default: return rows
        }
    }

    private func matching(_ filter: LibraryFilter, sort: LibrarySort, ascending: Bool, facts: [Int64: GameFacts]) throws
        -> [LibraryRow]
    {
        let text = filter.name.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return try library(filter, sort: sort, ascending: ascending).having(filter, in: facts) }
        var withoutSearch = filter
        withoutSearch.name = ""
        let byName = Set(try library(filter, sort: sort, ascending: ascending).map(\.id))
        try Task.checkCancellation()
        return try library(withoutSearch, sort: sort, ascending: ascending)
            .filter { row in
                try Task.checkCancellation()
                return byName.contains(row.id) || (row.igdbGameId.flatMap { facts[$0] }?.mentions(text) ?? false)
            }
            .having(filter, in: facts)
    }
}

extension [LibraryRow] {
    /// Sorted by a value from the cache. Rows without one go last, by name as they came, and equal
    /// values keep their order.
    func sorted(by key: (LibraryRow) -> Double?, ascending: Bool) -> [LibraryRow] {
        var keyed: [KeyedRow] = []
        for (index, row) in enumerated() {
            if let k = key(row) { keyed.append(KeyedRow(index: index, key: k, row: row)) }
        }
        keyed.sort { a, b in
            if a.key == b.key { return a.index < b.index }
            return ascending ? a.key < b.key : a.key > b.key
        }
        let unkeyed: [LibraryRow] = filter { key($0) == nil }
        return keyed.map { $0.row } + unkeyed
    }
}

private struct KeyedRow {
    let index: Int
    let key: Double
    let row: LibraryRow
}
