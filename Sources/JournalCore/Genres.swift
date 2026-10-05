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

extension LibraryFilter {
    /// Whether it filters on facts from the cache, which `having(_:in:)` applies.
    public var usesIGDBFacts: Bool { genre != nil || theme != nil || franchise != nil || series != nil || company != nil }
}

extension GameFacts {
    /// Whether a company, franchise or series contains `text`, ignoring case.
    func mentions(_ text: String) -> Bool {
        credits.contains { $0.name.localizedCaseInsensitiveContains(text) }
            || franchises.contains { $0.localizedCaseInsensitiveContains(text) }
            || series.contains { $0.localizedCaseInsensitiveContains(text) }
    }
}

extension JournalStore {
    /// The Library with the IGDB facts applied: the filter's genre, theme, franchise, series and
    /// company, and a search that also matches the Game's companies, franchises and series. It stops
    /// early with `CancellationError` when its task is cancelled (a newer search replaced it).
    public func library(_ filter: LibraryFilter, sort: LibrarySort, ascending: Bool, facts: [Int64: GameFacts]) throws
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
