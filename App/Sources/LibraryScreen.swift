import JournalCore
import SwiftUI

/// The Library (or one List): every Game, as a table or as covers, filtered and sorted.
struct LibraryScreen: View {
    let services: Services
    /// Set when showing one List: its Games, with the List filter fixed.
    var list: GameList?
    @Binding var selection: GameID?

    @State private var filter = LibraryFilter()
    @State private var sort = LibrarySort.name
    @State private var ascending = true
    @State private var showCovers = false
    @State private var rows: [LibraryRow] = []
    @State private var platforms: [IGDBPlatform] = []
    @State private var lists: [GameList] = []
    @State private var error: String?

    var body: some View {
        Group {
            if let error {
                ContentUnavailableView("Couldn't read the journal", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if rows.isEmpty {
                ContentUnavailableView(
                    filter == LibraryFilter() ? "No Games yet" : "No Games match", systemImage: "books.vertical",
                    description: Text(filter == LibraryFilter() ? "Add one with +." : "Try fewer filters."))
            } else if showCovers {
                CoversGrid(services: services, rows: rows, selection: $selection)
            } else {
                Table(rows, selection: $selection) {
                    TableColumn("Name") { row in
                        HStack(spacing: 4) {
                            Text(row.name)
                            if row.noROMInOpenEmu {
                                Image(systemName: "externaldrive.badge.xmark").foregroundStyle(.secondary).help("No ROM in OpenEmu")
                            }
                        }
                    }
                    TableColumn("Platform", value: \.platformName)
                    TableColumn("Rating") { Text($0.rating.map(ratingText) ?? "–") }.width(60)
                    TableColumn("Intent") { Text($0.intent.map(intentText) ?? "") }.width(70)
                    TableColumn("Played") { Text(playedText($0)) }.width(110)
                    TableColumn("Childhood") { Text($0.childhood ? "Yes" : "") }.width(70)
                }
            }
        }
        .navigationTitle(list?.name ?? "Library")
        .toolbar { toolbar }
        .task(id: Reload(revision: services.changes.revision, filter: filter, sort: sort, ascending: ascending, list: list?.id)) {
            load()
        }
    }

    private struct Reload: Equatable {
        let revision: Int
        let filter: LibraryFilter
        let sort: LibrarySort
        let ascending: Bool
        let list: Int64?
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu(
                "Filter",
                systemImage: filter == LibraryFilter() ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
            ) {
                Picker("Platform", selection: $filter.platformId) {
                    Text("Any").tag(Int64?.none)
                    ForEach(platforms) { Text($0.name).tag(Int64?.some($0.id)) }
                }
                Picker("Rating", selection: $filter.rating) {
                    Text("Any").tag(RatingFilter?.none)
                    Text("Unrated").tag(RatingFilter?.some(.unrated))
                    ForEach([9, 8, 7, 6, 5], id: \.self) {
                        Text("\($0).0 or more").tag(RatingFilter?.some(.atLeast(Rating(tenths: $0 * 10)!)))
                    }
                }
                Picker("Intent", selection: $filter.intent) {
                    Text("Any").tag(Intent??.none)
                    Text("None").tag(Intent??.some(nil))
                    Text("Backlog").tag(Intent??.some(.backlog))
                    Text("Up next").tag(Intent??.some(.upNext))
                }
                if list == nil {
                    Picker("List", selection: $filter.listId) {
                        Text("Any").tag(Int64?.none)
                        ForEach(lists, id: \.id) { Text($0.name).tag(Int64?.some($0.id)) }
                    }
                }
                Picker("Played", selection: $filter.outcome) {
                    Text("Any").tag(OutcomeFilter?.none)
                    Text("Playing").tag(OutcomeFilter?.some(.playing))
                    Text("Finished").tag(OutcomeFilter?.some(.finished))
                    Text("Dropped").tag(OutcomeFilter?.some(.dropped))
                    Text("Not played").tag(OutcomeFilter?.some(.notPlayed))
                }
                Picker("Childhood", selection: $filter.childhood) {
                    Text("Any").tag(Bool?.none)
                    Text("Childhood").tag(Bool?.some(true))
                    Text("Not childhood").tag(Bool?.some(false))
                }
                Divider()
                Button("Clear filters") { filter = LibraryFilter() }
            }
            Menu("Sort", systemImage: "arrow.up.arrow.down") {
                Picker("Sort by", selection: $sort) {
                    Text("Name").tag(LibrarySort.name)
                    Text("Platform").tag(LibrarySort.platform)
                    Text("Rating").tag(LibrarySort.rating)
                    Text("Intent set").tag(LibrarySort.intentSet)
                }
                Picker("Order", selection: $ascending) {
                    Text("Ascending").tag(true)
                    Text("Descending").tag(false)
                }
            }
            Picker("View", selection: $showCovers) {
                Label("Table", systemImage: "list.bullet").tag(false)
                Label("Covers", systemImage: "square.grid.2x2").tag(true)
            }
            .pickerStyle(.segmented)
        }
    }

    private func load() {
        guard let journal = services.journal else { return }
        var effective = filter
        if let list { effective.listId = list.id }
        do {
            rows = try journal.library(effective, sort: sort, ascending: ascending)
            platforms = try journal.usedPlatformIDs().compactMap { try journal.platform($0) }.sorted { $0.name < $1.name }
            lists = try journal.lists()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

func ratingText(_ rating: Rating) -> String { String(format: "%.1f", Double(rating.tenths) / 10) }

func intentText(_ intent: Intent) -> String {
    switch intent {
    case .backlog: "Backlog"
    case .upNext: "Up next"
    }
}

private func playedText(_ row: LibraryRow) -> String {
    var parts: [String] = []
    if row.isPlaying { parts.append("Playing") }
    if row.outcomes.contains(.finished) { parts.append("Finished") }
    if row.outcomes.contains(.dropped) { parts.append("Dropped") }
    return parts.joined(separator: ", ")
}

/// Games as covers. Linked Games show IGDB's cover from the cache; the rest a named tile.
private struct CoversGrid: View {
    let services: Services
    let rows: [LibraryRow]
    @Binding var selection: GameID?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 16)], spacing: 16) {
                ForEach(rows) { row in
                    VStack(spacing: 4) {
                        CoverTile(services: services, row: row)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6).stroke(selection == row.id ? Color.accentColor : .clear, lineWidth: 3))
                        Text(row.name).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                    }
                    .onTapGesture { selection = row.id }
                }
            }
            .padding()
        }
    }
}

private struct CoverTile: View {
    let services: Services
    let row: LibraryRow

    var body: some View {
        CoverView(services: services, game: row.id, name: row.name)
            .frame(width: 120, height: 160)
    }
}
