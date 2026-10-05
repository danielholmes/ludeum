import JournalCore
import SwiftUI

/// The Library, or a scoped view of it (a Platform, a List, a Pinned item, Finished, Childhood): every
/// Game, as a table or as covers, filtered and sorted.
struct LibraryScreen: View {
    let services: Services
    /// What this screen always shows, e.g. one Platform. Shown as a fixed chip, never removed.
    var scope = LibraryFilter()
    var title: String?
    @Binding var selection: GameID?
    @State private var filter: LibraryFilter
    /// What's typed in the search field; it reaches `filter.name` after a pause in typing.
    @State private var searchText: String
    @FocusState private var searchFocused: Bool
    // Remembered across screens and launches, shared by the Library and every List.
    @AppStorage("librarySort") private var sort = LibrarySort.name
    @AppStorage("librarySortAscending") private var ascending = true
    @AppStorage("libraryShowsCovers") private var showCovers = false
    /// Cover width in the Covers view, in points.
    @AppStorage("libraryCoverWidth") private var coverWidth = 120.0
    @State private var rows: [LibraryRow] = []
    @State private var platforms: [IGDBPlatform] = []
    @State private var lists: [GameList] = []
    @State private var error: String?
    /// IGDB facts by IGDB game id, for genre, theme and company filters and searches.
    @State private var facts: [Int64: GameFacts] = [:]
    /// False until the first load, so an empty screen isn't mistaken for "No Games match".
    @State private var loaded = false
    /// A reload is running.
    @State private var loading = false

    /// Typing hasn't reached the filter yet, or the Games are being found: shown as spinners.
    private var busy: Bool { loading || searchText != filter.name }

    /// `initialFilter` is where to start, e.g. Year in review's "no dates" link: removable pills.
    /// `title` replaces "Library", and names the `scope` chip.
    init(
        services: Services, selection: Binding<GameID?>, initialFilter: LibraryFilter = LibraryFilter(),
        scope: LibraryFilter = LibraryFilter(), title: String? = nil
    ) {
        self.services = services
        self.scope = scope
        self.title = title
        _selection = selection
        _filter = State(initialValue: initialFilter)
        _searchText = State(initialValue: initialFilter.name)
    }

    var body: some View {
        Group {
            if let error {
                ContentUnavailableView("Couldn't read the journal", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                // At the top, where the Games would be, not centred.
                VStack {
                    EmptyResults(
                        title: filter == LibraryFilter() ? "No Games yet" : "No Games match", systemImage: "books.vertical",
                        description: filter == LibraryFilter() ? "Add one with +." : "Try fewer filters or another search.",
                        clearFilters: filter == LibraryFilter()
                            ? nil
                            : {
                                filter = LibraryFilter()
                                searchText = ""
                            }
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.top, 24)
            } else if showCovers {
                CoversGrid(services: services, rows: rows, width: coverWidth, selection: $selection)
            } else {
                Table(rows, selection: $selection, sortOrder: columnSort) {
                    TableColumn("Name", sortUsing: KeyPathComparator(\LibraryRow.name)) { row in
                        HStack(spacing: 4) {
                            Text(row.name)
                            if row.noROMInOpenEmu {
                                Image(systemName: "externaldrive.badge.xmark").foregroundStyle(.secondary).help("No ROM in OpenEmu")
                            }
                        }
                    }
                    TableColumn("Platform", value: \.platformName)
                    TableColumn("Year", sortUsing: KeyPathComparator(\LibraryRow.yearSortKey)) {
                        Text($0.releaseYear.map(String.init) ?? "")
                    }
                    .width(50)
                    TableColumn("Rating", sortUsing: KeyPathComparator(\LibraryRow.ratingSortKey)) {
                        Text($0.rating.map(ratingText) ?? "–")
                    }.width(60)
                    TableColumn("Players", sortUsing: KeyPathComparator(\LibraryRow.playersSortKey)) { row in
                        if let p = row.playerScore {
                            Text(ratingText(p.rating)).foregroundStyle(p.isReliable ? .primary : .tertiary)
                                .help(
                                    "\(p.count) player rating\(p.count == 1 ? "" : "s") on IGDB\(p.isReliable ? "" : ": too few to rank by")"
                                )
                        }
                    }
                    .width(60)
                    TableColumn("Intent", sortUsing: KeyPathComparator(\LibraryRow.intentSetSortKey)) {
                        Text($0.intent.map(intentText) ?? "")
                    }.width(70)
                    TableColumn("Played", sortUsing: KeyPathComparator(\LibraryRow.playedSortKey)) { Text(playedText($0)) }.width(110)
                    TableColumn("Childhood", sortUsing: KeyPathComparator(\LibraryRow.childhoodSortKey)) { Text($0.childhood ? "Yes" : "") }
                        .width(70)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterBar(
                count: rows.count, busy: busy, scope: scope == LibraryFilter() ? nil : title, filter: $filter,
                kinds: FilterKind.library.subtracting(FilterKind.fixed(by: scope)), platforms: platforms, lists: lists,
                genres: Set(facts.values.flatMap(\.genres)).sorted(), themes: Set(facts.values.flatMap(\.themes)).sorted()
            ) {
                LibrarySortMenu(sort: Binding($sort), ascending: $ascending)
            }
        }
        .navigationTitle(title ?? "Library")
        .viewShortcuts(showCovers: $showCovers, search: $searchFocused)
        .toolbar { toolbar }
        .task(id: searchText) {
            // Debounced: the Library reloads 300 ms after the last keystroke, not on every one.
            guard searchText != filter.name else { return }
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { filter.name = searchText }
        }
        .task(id: Reload(revision: services.changes.revision, filter: filter, sort: sort, ascending: ascending, scope: scope)) {
            await load()
        }
    }

    /// The table's header clicks, as the Library's sort: Name, Platform, Rating and Intent (when it was set)
    /// sort; a newly clicked column starts in its usual order, and clicking it again flips it.
    private var columnSort: Binding<[KeyPathComparator<LibraryRow>]> {
        Binding(
            get: {
                let order: SortOrder = ascending ? .forward : .reverse
                return switch sort {
                case .year: [KeyPathComparator(\LibraryRow.yearSortKey, order: order)]
                case .players: [KeyPathComparator(\LibraryRow.playersSortKey, order: order)]
                case .played: [KeyPathComparator(\LibraryRow.playedSortKey, order: order)]
                case .childhood: [KeyPathComparator(\LibraryRow.childhoodSortKey, order: order)]
                case .name: [KeyPathComparator(\LibraryRow.name, order: order)]
                case .platform: [KeyPathComparator(\LibraryRow.platformName, order: order)]
                case .rating: [KeyPathComparator(\LibraryRow.ratingSortKey, order: order)]
                case .intentSet: [KeyPathComparator(\LibraryRow.intentSetSortKey, order: order)]
                }
            },
            set: { new in
                guard let first = new.first else { return }
                let chosen: LibrarySort? =
                    switch first.keyPath {
                    case \LibraryRow.name: .name
                    case \LibraryRow.platformName: .platform
                    case \LibraryRow.ratingSortKey: .rating
                    case \LibraryRow.intentSetSortKey: .intentSet
                    case \LibraryRow.yearSortKey: .year
                    case \LibraryRow.playersSortKey: .players
                    case \LibraryRow.playedSortKey: .played
                    case \LibraryRow.childhoodSortKey: .childhood
                    default: nil
                    }
                guard let chosen else { return }
                if chosen == sort {
                    ascending = first.order == .forward
                } else {
                    sort = chosen
                    ascending = chosen.defaultAscending
                }
            })
    }

    private struct Reload: Equatable {
        let revision: Int
        let filter: LibraryFilter
        let sort: LibrarySort
        let ascending: Bool
        let scope: LibraryFilter
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        // The search field in a group of its own, so the window's Add button doesn't join it.
        if #available(macOS 26, *) { ToolbarSpacer(.fixed) }
        ToolbarItem {
            TextField("Search", text: $searchText)
                .focused($searchFocused)
                .help("Names, companies, franchises, series and keywords (⌘F)")
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .overlay(alignment: .trailing) {
                    if busy {
                        ProgressView().controlSize(.mini).padding(.trailing, searchText.isEmpty ? 5 : 22)
                    }
                    if !searchText.isEmpty {
                        Button("Clear search", systemImage: "xmark.circle.fill") {
                            searchText = ""
                            filter.name = ""
                        }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary).padding(.trailing, 5)
                    }
                }
        }
        ToolbarItemGroup {
            Picker("View", selection: $showCovers) {
                Label("Table", systemImage: "list.bullet").tag(false)
                Label("Covers", systemImage: "square.grid.2x2").tag(true)
            }
            .pickerStyle(.segmented)
            if showCovers { CoverSizeSlider(width: $coverWidth) }
        }
    }

    private func load() async {
        guard let journal = services.journal else { return }
        loading = true
        defer { if !Task.isCancelled { loading = false } }
        let effective = filter.scoped(by: scope)
        do {
            let (effective, sort, ascending) = (effective, sort, ascending)
            if !effective.usesIGDBFacts, effective.name.trimmed.isEmpty, sort != .year, sort != .players {
                let found = try await offMain {
                    try journal.library(effective, sort: sort, ascending: ascending)
                }
                // A newer reload has started: its rows win.
                guard !Task.isCancelled else { return }
                rows = found
                loaded = true
                // The Year column and the Add filter menu's genres and themes can follow.
                facts = await services.memory.facts(services)
                guard !Task.isCancelled else { return }
                rows = found.withIGDBFacts(facts)
            } else {
                // A search also matches companies, franchises and series, and Year and Players sort by IGDB's
                // release year and rating: all live in the cache.
                facts = await services.memory.facts(services)
                let facts = facts
                // Off the main thread, so typing stays smooth while it filters.
                let found = try await offMain {
                    try journal.library(effective, sort: sort, ascending: ascending, facts: facts)
                }
                guard !Task.isCancelled else { return }
                rows = found
                loaded = true
            }
            (platforms, lists) = try filterChoices(journal)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The Platforms and Lists the filter menu offers.
func filterChoices(_ journal: JournalStore) throws -> ([IGDBPlatform], [GameList]) {
    (try journal.shownPlatforms(), try journal.lists())
}

func sortText(_ sort: LibrarySort) -> String {
    switch sort {
    case .name: "Name"
    case .platform: "Platform"
    case .rating: "Rating"
    case .intentSet: "Intent set"
    case .year: "Year"
    case .players: "Players' rating"
    case .played: "Played"
    case .childhood: "Childhood"
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

/// Games as covers: each Game's Cover (see `Covers`), else a named tile.
private struct CoversGrid: View {
    let services: Services
    let rows: [LibraryRow]
    let width: Double
    @Binding var selection: GameID?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: width), spacing: 24, alignment: .top)], spacing: 24) {
                ForEach(rows) { row in CoverCell(services: services, row: row, width: width, selection: $selection) }
            }
            .padding()
        }
    }
}

/// A Game in a covers grid: its Cover with badges and its name; clicking selects it.
struct CoverCell: View {
    let services: Services
    let row: LibraryRow
    let width: Double
    @Binding var selection: GameID?
    /// Top-rated's rank, shown before the name.
    var rank: Int? = nil

    var body: some View {
        VStack(spacing: 4) {
            CoverTile(services: services, row: row, width: width)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selection == row.id ? Color.accentColor : .clear, lineWidth: 3))
            Text(rank.map { "\($0). \(row.name)" } ?? row.name).font(.subheadline).lineLimit(2).multilineTextAlignment(.center)
        }
        .onTapGesture { selection = row.id }
    }
}

/// The covers grids' size slider, for the toolbar.
struct CoverSizeSlider: View {
    @Binding var width: Double

    var body: some View {
        Slider(value: $width, in: 80...300) {
            Text("Cover size")
        } minimumValueLabel: {
            Image(systemName: "photo").imageScale(.small)
        } maximumValueLabel: {
            Image(systemName: "photo").imageScale(.large)
        }
        .frame(width: 140)
        .padding(.horizontal, 8)
        .help("Cover size")
    }
}

private struct CoverTile: View {
    let services: Services
    let row: LibraryRow
    let width: Double

    var body: some View {
        CoverView(services: services, game: row.id, name: row.name)
            .frame(width: width, height: width * 4 / 3)
            .overlay(alignment: .bottomLeading) {
                if let rating = row.rating {
                    // Grows with the Cover: about a ninth of its width, never under 13 pt.
                    // An imported Rating (from OpenEmu stars, approximate) is amber with "≈", so it stands out to re-rate.
                    Text(row.ratingImported ? "≈\(ratingText(rating))" : ratingText(rating))
                        .font(.system(size: max(13, width / 9), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(row.ratingImported ? Color.black : ratingColor(rating))
                        .padding(.horizontal, max(6, width / 24)).padding(.vertical, 2)
                        .background {
                            // A dark pill, so the Rating's colour reads the same over any cover, light or dark.
                            if row.ratingImported { Capsule().fill(Color.orange) } else { Capsule().fill(.black.opacity(0.75)) }
                        }
                        .padding(5)
                        .help(row.ratingImported ? "Rating \(ratingText(rating)), imported from OpenEmu stars" : "Rating")
                }
            }
            .overlay(alignment: .topTrailing) {
                if let status = CoverStatus(row) {
                    Image(systemName: status.symbol).font(.system(size: 20, weight: .bold)).foregroundStyle(status.color)
                        .padding(8)
                        .background(.regularMaterial, in: .circle)
                        .padding(5)
                        .help(status.help)
                }
            }
    }
}

/// A Cover's status badge: Playing, else Finished, else Up next, else Backlog; none otherwise.
private enum CoverStatus {
    case playing, finished, upNext, backlog

    init?(_ row: LibraryRow) {
        if row.isPlaying {
            self = .playing
        } else if row.outcomes.contains(.finished) {
            self = .finished
        } else if row.intent == .upNext {
            self = .upNext
        } else if row.intent == .backlog {
            self = .backlog
        } else {
            return nil
        }
    }

    var symbol: String {
        switch self {
        case .playing: "play.fill"
        case .finished: "checkmark"
        case .upNext: "arrow.up.forward"
        case .backlog: "tray.full"
        }
    }

    var color: Color {
        switch self {
        case .playing: .blue
        case .finished: .green
        case .upNext: .orange
        case .backlog: .secondary
        }
    }

    var help: String {
        switch self {
        case .playing: "Playing"
        case .finished: "Finished"
        case .upNext: "Up next"
        case .backlog: "Backlog"
        }
    }
}

extension LibraryRow {
    /// For the table's Rating column: unrated below 0.0.
    var ratingSortKey: Int { rating?.tenths ?? -1 }
    /// For the table's Intent column: when the Intent was set, undated or none first.
    var intentSetSortKey: Date { intentSetAt ?? .distantPast }
    /// For the table's Year column (the Library sorts it, with no year last).
    var yearSortKey: Int { releaseYear ?? 0 }
    /// For the table's Players column (the Library sorts it, ranking only scores with 10 or more ratings).
    var playersSortKey: Double { playerScore.map(\.score) ?? 0 }
    /// For the table's Played and Childhood columns (the Library sorts them).
    var playedSortKey: Int { isPlaying ? 3 : outcomes.contains(.finished) ? 2 : outcomes.contains(.dropped) ? 1 : 0 }
    var childhoodSortKey: Int { childhood ? 1 : 0 }
}

/// Runs `work` on a background thread. Cancelling the caller cancels it, so work that checks
/// for cancellation (a search) stops when a newer one replaces it.
func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    let task = Task.detached(priority: .userInitiated) { try work() }
    return try await withTaskCancellationHandler {
        try await task.value
    } onCancel: {
        task.cancel()
    }
}
