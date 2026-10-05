import JournalCore
import SwiftUI

/// The Library (or one List): every Game, as a table or as covers, filtered and sorted.
struct LibraryScreen: View {
    let services: Services
    /// Set when showing one List: its Games, with the List filter fixed.
    var list: GameList?
    var title: String?
    @Binding var selection: GameID?
    @State private var filter: LibraryFilter
    @State private var sort = LibrarySort.name
    @State private var ascending = true
    // Remembered across screens and launches, shared by the Library and every List.
    @AppStorage("libraryShowsCovers") private var showCovers = false
    /// Cover width in the Covers view, in points.
    @AppStorage("libraryCoverWidth") private var coverWidth = 120.0
    @State private var rows: [LibraryRow] = []
    @State private var platforms: [IGDBPlatform] = []
    @State private var lists: [GameList] = []
    @State private var error: String?
    /// IGDB genres and themes by IGDB game id, for the Genre and Theme filters.
    @State private var facts: [Int64: GameFacts] = [:]
    /// False until the first load, so an empty screen isn't mistaken for "No Games match".
    @State private var loaded = false

    /// `initialFilter` is where to start, e.g. Year in review's "no dates" link.
    /// `title` replaces "Library", e.g. for a Platform opened from the sidebar.
    init(
        services: Services, list: GameList? = nil, selection: Binding<GameID?>, initialFilter: LibraryFilter = LibraryFilter(),
        title: String? = nil
    ) {
        self.services = services
        self.list = list
        self.title = title
        _selection = selection
        _filter = State(initialValue: initialFilter)
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
                    ContentUnavailableView(
                        filter == LibraryFilter() ? "No Games yet" : "No Games match", systemImage: "books.vertical",
                        description: Text(filter == LibraryFilter() ? "Add one with +." : "Try fewer filters."))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.top, 24)
            } else if showCovers {
                CoversGrid(services: services, rows: rows, width: coverWidth, selection: $selection)
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
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterSummary(filter: $filter, platforms: platforms, lists: lists, count: rows.count)
        }
        .navigationTitle(list?.name ?? title ?? "Library")
        .toolbar { toolbar }
        .task(id: Reload(revision: services.changes.revision, filter: filter, sort: sort, ascending: ascending, list: list?.id)) {
            await load()
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
        // The search field in a group of its own, so the window's Add button doesn't join it.
        if #available(macOS 26, *) { ToolbarSpacer(.fixed) }
        ToolbarItem {
            TextField("Search", text: $filter.name)
                .help("Names, companies, franchises and series")
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .overlay(alignment: .trailing) {
                    if !filter.name.isEmpty {
                        Button("Clear search", systemImage: "xmark.circle.fill") { filter.name = "" }
                            .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary).padding(.trailing, 5)
                    }
                }
        }
        ToolbarItemGroup {
            LibraryFilterMenu(
                filter: $filter, platforms: platforms, lists: list == nil ? lists : nil,
                genres: Set(facts.values.flatMap(\.genres)).sorted(), themes: Set(facts.values.flatMap(\.themes)).sorted())
            LibrarySortMenu(sort: Binding($sort), ascending: $ascending)
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
        var effective = filter
        if let list { effective.listId = list.id }
        do {
            if !filter.usesIGDBFacts, filter.name.trimmed.isEmpty {
                // Show the rows now; the Genre and Theme menus' choices can follow.
                rows = try journal.library(effective, sort: sort, ascending: ascending)
                loaded = true
                facts = await services.memory.facts(services)
            } else {
                // A search also matches companies, franchises and series, which live in the cache.
                facts = await services.memory.facts(services)
                rows = try journal.library(effective, sort: sort, ascending: ascending, facts: facts)
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

/// The Library's filter menu, shared by the screens that filter like it.
struct LibraryFilterMenu: View {
    @Binding var filter: LibraryFilter
    let platforms: [IGDBPlatform]
    /// Nil hides the List filter (when showing one List).
    let lists: [GameList]?
    /// Top-rated offers only Platform, List and Childhood.
    var ratedOnly = false
    /// Nil hides the Genre and Theme filters (screens that don't apply them).
    var genres: [String]? = nil
    var themes: [String]? = nil

    var body: some View {
        Menu(
            "Filter",
            systemImage: filter == LibraryFilter() ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
        ) {
            Picker("Platform", selection: $filter.platformId) {
                Text("Any").tag(Int64?.none)
                ForEach(platforms) { Text($0.name).tag(Int64?.some($0.id)) }
            }
            if !ratedOnly {
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
            }
            if let lists {
                Picker("List", selection: $filter.listId) {
                    Text("Any").tag(Int64?.none)
                    ForEach(lists, id: \.id) { Text($0.name).tag(Int64?.some($0.id)) }
                }
            }
            if let genres, !genres.isEmpty {
                Picker("Genre", selection: $filter.genre) {
                    Text("Any").tag(String?.none)
                    ForEach(genres, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            if let themes, !themes.isEmpty {
                Picker("Theme", selection: $filter.theme) {
                    Text("Any").tag(String?.none)
                    ForEach(themes, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            if !ratedOnly {
                Picker("Played", selection: $filter.outcome) {
                    Text("Any").tag(OutcomeFilter?.none)
                    Text("Playing").tag(OutcomeFilter?.some(.playing))
                    Text("Finished").tag(OutcomeFilter?.some(.finished))
                    Text("Dropped").tag(OutcomeFilter?.some(.dropped))
                    Text("Not played").tag(OutcomeFilter?.some(.notPlayed))
                }
            }
            Picker("Childhood", selection: $filter.childhood) {
                Text("Any").tag(Bool?.none)
                Text("Childhood").tag(Bool?.some(true))
                Text("Not childhood").tag(Bool?.some(false))
            }
            Toggle("Playthroughs with no dates", isOn: $filter.undatedPlaythroughs)
            Divider()
            Button("Clear filters") { filter = LibraryFilter() }
        }
    }
}

/// The Library's sort menu. Nil is What to play next's "Default", offered only with `offersDefault`.
struct LibrarySortMenu: View {
    @Binding var sort: LibrarySort?
    @Binding var ascending: Bool
    var offersDefault = false

    var body: some View {
        Menu("Sort", systemImage: "arrow.up.arrow.down") {
            // Choosing a sort also sets its usual order; Order can still flip it.
            Picker(
                "Sort by",
                selection: Binding(
                    get: { sort },
                    set: { new in
                        sort = new
                        if let new { ascending = new.defaultAscending }
                    })
            ) {
                if offersDefault { Text("Default").tag(LibrarySort?.none) }
                ForEach(LibrarySort.allCases, id: \.self) { Text(sortText($0)).tag(LibrarySort?.some($0)) }
            }
            Picker("Order", selection: $ascending) {
                Text("Ascending").tag(true)
                Text("Descending").tag(false)
            }
            .disabled(sort == nil)
        }
    }
}

func sortText(_ sort: LibrarySort) -> String {
    switch sort {
    case .name: "Name"
    case .platform: "Platform"
    case .rating: "Rating"
    case .intentSet: "Intent set"
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: width), spacing: 16, alignment: .top)], spacing: 16) {
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

/// What the filters are showing, in words, above a filtered screen: one chip per active filter,
/// each clearable, plus Clear all. Nothing when no filter is set.
struct FilterSummary: View {
    @Binding var filter: LibraryFilter
    let platforms: [IGDBPlatform]
    let lists: [GameList]
    /// How many Games are shown, when the screen has a simple count.
    var count: Int?

    var body: some View {
        let chips = self.chips
        if !chips.isEmpty {
            HStack(spacing: 6) {
                Text(count.map { "Showing \($0) Game\($0 == 1 ? "" : "s"):" } ?? "Showing:").foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chips, id: \.text) { chip in
                            HStack(spacing: 4) {
                                Text(chip.text)
                                Button("Remove filter", systemImage: "xmark") { chip.clear(&filter) }
                                    .labelStyle(.iconOnly).buttonStyle(.hover).imageScale(.small)
                            }
                            .padding(.leading, 8).padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                        }
                    }
                }
                Button("Clear all") { filter = LibraryFilter() }.buttonStyle(.hover)
            }
            .font(.callout)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.bar)
        }
    }

    private struct Chip {
        let text: String
        let clear: (inout LibraryFilter) -> Void
    }

    private var chips: [Chip] {
        var c: [Chip] = []
        if let id = filter.platformId {
            c.append(Chip(text: platforms.first { $0.id == id }?.name ?? "One Platform") { $0.platformId = nil })
        }
        switch filter.rating {
        case .unrated: c.append(Chip(text: "Unrated") { $0.rating = nil })
        case .atLeast(let r): c.append(Chip(text: "Rated \(ratingText(r)) or more") { $0.rating = nil })
        case nil: break
        }
        switch filter.intent {
        case .some(nil): c.append(Chip(text: "No Intent") { $0.intent = nil })
        case .some(.some(let i)): c.append(Chip(text: intentText(i)) { $0.intent = nil })
        case nil: break
        }
        if let id = filter.listId {
            c.append(Chip(text: "In \(lists.first { $0.id == id }?.name ?? "a List")") { $0.listId = nil })
        }
        if let o = filter.outcome {
            let text =
                switch o {
                case .playing: "Playing"
                case .finished: "Finished"
                case .dropped: "Dropped"
                case .notPlayed: "Not played"
                }
            c.append(Chip(text: text) { $0.outcome = nil })
        }
        if let ch = filter.childhood {
            c.append(Chip(text: ch ? "Childhood" : "Not childhood") { $0.childhood = nil })
        }
        if filter.undatedPlaythroughs {
            c.append(Chip(text: "Playthroughs with no dates") { $0.undatedPlaythroughs = false })
        }
        if let genre = filter.genre { c.append(Chip(text: genre) { $0.genre = nil }) }
        if let theme = filter.theme { c.append(Chip(text: theme) { $0.theme = nil }) }
        if let franchise = filter.franchise { c.append(Chip(text: "Franchise: \(franchise)") { $0.franchise = nil }) }
        if let series = filter.series { c.append(Chip(text: "Series: \(series)") { $0.series = nil }) }
        if let company = filter.company { c.append(Chip(text: "Company: \(company)") { $0.company = nil }) }
        return c
    }
}
