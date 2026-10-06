import LudeumCore
import SwiftUI

/// Top-rated: every rated Game by current Rating, highest first. Ties share a rank.
struct TopRatedScreen: View {
    let services: Services
    @Binding var selection: GameID?

    @State private var filter = LibraryFilter()
    @State private var rows: [TopRatedRow] = []
    @State private var platforms: [IGDBPlatform] = []
    @State private var lists: [GameList] = []
    @State private var players: [Player] = []
    @State private var error: String?
    // Shared with the Library: one choice of view and Cover size everywhere.
    @AppStorage("libraryShowsCovers") private var showCovers = false
    @AppStorage("libraryCoverWidth") private var coverWidth = 120.0

    var body: some View {
        Group {
            if let error {
                ContentUnavailableView("Couldn't read the journal", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if rows.isEmpty {
                EmptyResults(
                    title: "No rated Games", systemImage: "star",
                    description: filter == LibraryFilter() ? "Rate a Game in its detail." : "Try fewer filters.",
                    clearFilters: filter == LibraryFilter() ? nil : { filter = LibraryFilter() })
            } else if showCovers {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: coverWidth), spacing: 24, alignment: .top)], spacing: 24) {
                        ForEach(rows, id: \.game.id) { row in
                            CoverCell(services: services, row: row.game, width: coverWidth, selection: $selection, rank: row.rank)
                        }
                    }
                    .padding()
                }
            } else {
                Table(rows, selection: $selection) {
                    TableColumn("#") { Text("\($0.rank)").monospacedDigit() }.width(40)
                    TableColumn("Name") { Text($0.game.name) }
                    TableColumn("Rating") { row in
                        Text(row.game.rating.map(ratingText) ?? "").monospacedDigit()
                    }
                    .width(60)
                    TableColumn("Platform") { Text($0.game.platformName) }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterBar(
                count: rows.count, filter: $filter, kinds: [.platform, .list, .player, .childhood], platforms: platforms, lists: lists,
                players: players)
        }
        .navigationTitle("Top-rated")
        .viewShortcuts(showCovers: $showCovers)
        .toolbar {
            ToolbarItemGroup {
                Picker("View", selection: $showCovers) {
                    Label("Table", systemImage: "list.bullet").tag(false)
                    Label("Covers", systemImage: "square.grid.2x2").tag(true)
                }
                .pickerStyle(.segmented)
                if showCovers { CoverSizeSlider(width: $coverWidth) }
            }
        }
        .task(id: Reload(revision: services.changes.revision, filter: filter)) { load() }
    }

    private struct Reload: Equatable {
        let revision: Int
        let filter: LibraryFilter
    }

    private func load() {
        guard let journal = services.journal else { return }
        do {
            rows = try journal.topRated(filter)
            (platforms, lists, players) = try filterChoices(journal)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
