import JournalCore
import SwiftUI

/// What to play next: Playing, Up next and Backlog, each Game once. A plain view, no suggestions.
struct WhatToPlayNextScreen: View {
    let services: Services
    @Binding var selection: GameID?

    @State private var filter = LibraryFilter()
    /// Nil is each section's default order.
    @State private var sort: LibrarySort?
    @State private var ascending = true
    @State private var next = PlayNext<LibraryRow>(playing: [], upNext: [], backlog: [])
    @State private var platforms: [IGDBPlatform] = []
    @State private var lists: [GameList] = []
    @State private var error: String?
    // Shared with the Library: one choice of view and Cover size everywhere.
    @AppStorage("libraryShowsCovers") private var showCovers = false
    @AppStorage("libraryCoverWidth") private var coverWidth = 120.0

    var body: some View {
        Group {
            if let error {
                ContentUnavailableView("Couldn't read the journal", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if next.playing.isEmpty, next.upNext.isEmpty, next.backlog.isEmpty {
                ContentUnavailableView(
                    "Nothing to play next", systemImage: "play.circle",
                    description: Text(filter == LibraryFilter() ? "Set a Game's Intent to Up next or Backlog." : "Try fewer filters."))
            } else if showCovers {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Each section's covers, a rule between sections.
                        let sections = [("Playing", next.playing, false), ("Up next", next.upNext, true), ("Backlog", next.backlog, true)]
                            .filter { !$0.1.isEmpty }
                        ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                            if index > 0 { Divider() }
                            Text("\(section.0) (\(section.1.count))").font(.headline)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: coverWidth), spacing: 16, alignment: .top)], spacing: 16) {
                                ForEach(section.1) { row in
                                    CoverCell(services: services, row: row, width: coverWidth, selection: $selection)
                                        .contextMenu { if section.2 { Button("Start playing") { startPlaying(row.id) } } }
                                }
                            }
                        }
                    }
                    .padding()
                }
            } else {
                List(selection: $selection) {
                    section("Playing", next.playing, canStart: false)
                    section("Up next", next.upNext, canStart: true)
                    section("Backlog", next.backlog, canStart: true)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterBar(
                filter: $filter, kinds: FilterKind.library.subtracting([.genre, .theme]), platforms: platforms, lists: lists
            ) {
                LibrarySortMenu(
                    sort: $sort, ascending: $ascending, sorts: LibrarySort.allCases.filter { $0 != .year && $0 != .players },
                    offersDefault: true)
            }
        }
        .navigationTitle("What to play next")
        .toolbar {
            ToolbarItemGroup {
                Picker("View", selection: $showCovers) {
                    Label("List", systemImage: "list.bullet").tag(false)
                    Label("Covers", systemImage: "square.grid.2x2").tag(true)
                }
                .pickerStyle(.segmented)
                if showCovers { CoverSizeSlider(width: $coverWidth) }
            }
        }
        .task(id: Reload(revision: services.changes.revision, filter: filter, sort: sort, ascending: ascending)) { load() }
    }

    private struct Reload: Equatable {
        let revision: Int
        let filter: LibraryFilter
        let sort: LibrarySort?
        let ascending: Bool
    }

    @ViewBuilder private func section(_ title: String, _ rows: [LibraryRow], canStart: Bool) -> some View {
        if !rows.isEmpty {
            Section("\(title) (\(rows.count))") {
                ForEach(rows) { row in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(row.name)
                            Text(detail(row)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if canStart {
                            Button("Start playing") { startPlaying(row.id) }
                                .help("Adds a Playthrough starting today and clears the Intent")
                        }
                    }
                    .tag(row.id)
                    .contextMenu {
                        if canStart { Button("Start playing") { startPlaying(row.id) } }
                    }
                }
            }
        }
    }

    private func detail(_ row: LibraryRow) -> String {
        var parts = [row.platformName]
        if let since = row.playingSince { parts.append("since \(since.text)") }
        if let rating = row.rating { parts.append(ratingText(rating)) }
        return parts.joined(separator: " · ")
    }

    private func startPlaying(_ game: GameID) {
        guard let journal = services.journal else { return }
        do {
            try journal.startPlaying(game)
            services.changes.changed()
        } catch {
            self.error = journalErrorText(error)
        }
    }

    private func load() {
        guard let journal = services.journal else { return }
        do {
            next = try journal.whatToPlayNext(filter, sort: sort, ascending: ascending)
            (platforms, lists) = try filterChoices(journal)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
