import LudeumCore
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
    @FocusState private var textFilterFocused: Bool
    // Remembered across screens and launches, shared by the Library and every scoped view of it.
    @AppStorage("librarySort") private var sort = LibrarySort.name
    @AppStorage("librarySortAscending") private var ascending = true
    @AppStorage("libraryShowsCovers") private var showCovers = false
    /// Cover width in the Covers view, in points.
    @AppStorage(CoverTileSize.widthKey) private var coverWidth = CoverTileSize.defaultWidth
    @State private var rows: [LibraryRow] = []
    /// The order `rows` came in, set along with them. The table starts afresh when it changes: moving its rows into a new
    /// order can keep the main thread for a minute (`NSTableView` building and removing a view for row after row).
    @State private var rowsOrder: RowsOrder?
    @State private var platforms: [IGDBPlatform] = []
    @State private var players: [Player] = []
    @State private var error: String?
    /// IGDB facts by IGDB game id, for genre, theme and company filters and searches.
    @State private var facts: [Int64: GameFacts] = [:]
    /// False until the first load, so an empty screen isn't mistaken for "No Games match".
    @State private var loaded = false
    /// A reload is running.
    @State private var loading = false

    /// The Games are being found: shown as a spinner.
    private var busy: Bool { loading }

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
    }

    var body: some View {
        // One container, not a Group: a Group would give each branch its own FilterBar, and the Text filter
        // would lose focus as the Games come and go.
        ZStack {
            if let error {
                ContentUnavailableView("Couldn't read the journal", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                // At the top, where the Games would be, not centred.
                VStack {
                    EmptyResults(
                        title: filter != LibraryFilter()
                            ? "No Games match"
                            : scope.listId != nil ? "No Games in this List" : "No Games yet",
                        systemImage: "books.vertical",
                        description: filter != LibraryFilter()
                            ? "Try fewer filters or another search."
                            : scope.listId != nil ? "Add a Game from the Game's page, under Lists." : "Add one with +.",
                        clearFilters: filter == LibraryFilter()
                            ? nil
                            : { filter = LibraryFilter() }
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
                            if row.wantToBuy {
                                Image(systemName: wantToBuySymbol).foregroundStyle(.blue).help("Want to buy")
                            }
                            if let badge = ROMBadge(row) {
                                Image(systemName: badge.symbol).foregroundStyle(badge.color).help(badge.help)
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
                    TableColumn("IGDB", sortUsing: KeyPathComparator(\LibraryRow.igdbPlayersSortKey)) {
                        PlayersScoreCell(score: $0.igdbPlayerScore)
                    }
                    .width(60)
                    TableColumn("LaunchBox", sortUsing: KeyPathComparator(\LibraryRow.launchBoxPlayersSortKey)) {
                        PlayersScoreCell(score: $0.launchBoxPlayerScore)
                    }
                    .width(85)
                    TableColumn("Intent", sortUsing: KeyPathComparator(\LibraryRow.intentSetSortKey)) {
                        Text($0.intent.map(intentText) ?? "")
                    }.width(70)
                    TableColumn("Played", sortUsing: KeyPathComparator(\LibraryRow.playedSortKey)) { Text(playedText($0)) }.width(110)
                    TableColumn("Childhood", sortUsing: KeyPathComparator(\LibraryRow.childhoodSortKey)) { Text($0.childhood ? "Yes" : "") }
                        .width(70)
                }
                .id(rowsOrder)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterBar(
                count: rows.count, busy: busy, scope: scope == LibraryFilter() ? nil : title, filter: $filter,
                kinds: FilterKind.library.subtracting(FilterKind.fixed(by: scope)), platforms: platforms, players: players,
                genres: Set(facts.values.flatMap(\.genres)).sorted(), themes: Set(facts.values.flatMap(\.themes)).sorted(),
                text: $filter.name, textFocused: $textFilterFocused
            ) {
                LibrarySortMenu(sort: Binding($sort), ascending: $ascending)
                ViewModeControls(showCovers: $showCovers, coverWidth: $coverWidth)
            }
        }
        .navigationTitle(title ?? "Library")
        .viewShortcuts(showCovers: $showCovers)
        .focusedSceneValue(\.focusTextFilter) { textFilterFocused = true }
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
                case .igdbPlayers: [KeyPathComparator(\LibraryRow.igdbPlayersSortKey, order: order)]
                case .launchBoxPlayers: [KeyPathComparator(\LibraryRow.launchBoxPlayersSortKey, order: order)]
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
                    case \LibraryRow.igdbPlayersSortKey: .igdbPlayers
                    case \LibraryRow.launchBoxPlayersSortKey: .launchBoxPlayers
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

    private struct RowsOrder: Hashable {
        let sort: LibrarySort
        let ascending: Bool
    }

    private struct Reload: Equatable {
        let revision: Int
        let filter: LibraryFilter
        let sort: LibrarySort
        let ascending: Bool
        let scope: LibraryFilter
    }

    private func load() async {
        guard let journal = services.journal else { return }
        loading = true
        defer { if !Task.isCancelled { loading = false } }
        let effective = filter.scoped(by: scope)
        do {
            let (effective, sort, ascending) = (effective, sort, ascending)
            if !effective.usesIGDBFacts, effective.name.trimmed.isEmpty, !sort.comesFromCache {
                let found = try await offMain {
                    try journal.library(effective, sort: sort, ascending: ascending)
                }
                // A newer reload has started: its rows win.
                guard !Task.isCancelled else { return }
                rows = found
                rowsOrder = RowsOrder(sort: sort, ascending: ascending)
                loaded = true
                // The Year, IGDB and LaunchBox columns and the Add filter menu's genres and themes can follow.
                facts = await services.memory.facts(services)
                let launchBox = await services.memory.launchBoxScores(services, facts: facts)
                guard !Task.isCancelled else { return }
                rows = found.withIGDBFacts(facts, launchBox: launchBox)
            } else {
                // A search also matches companies, franchises and series, Year sorts by IGDB's release year, and
                // IGDB and LaunchBox by their players' scores: all live in the cache.
                facts = await services.memory.facts(services)
                let facts = facts
                let launchBox = await services.memory.launchBoxScores(services, facts: facts)
                // Off the main thread, so typing stays smooth while it filters.
                let found = try await offMain {
                    try journal.library(effective, sort: sort, ascending: ascending, facts: facts, launchBox: launchBox)
                }
                guard !Task.isCancelled else { return }
                rows = found
                rowsOrder = RowsOrder(sort: sort, ascending: ascending)
                loaded = true
            }
            (platforms, players) = try filterChoices(journal)
            error = nil
        } catch {
            // A newer reload replaced this one, and its search stopped early with `CancellationError`: not
            // a failure, so the newer reload's rows, or its error, win.
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}

/// A Library row's IGDB or LaunchBox players' score, greyed when it's from too few ratings to rank by.
private struct PlayersScoreCell: View {
    let score: CommunityScore?

    var body: some View {
        if let score {
            Text(ratingText(score.rating)).foregroundStyle(score.isReliable ? .primary : .tertiary)
                .help(score.countText("player rating") + (score.isReliable ? "" : ". Too few to rank by"))
        }
    }
}

/// The Platforms, Lists and Players the filter menu offers.
func filterChoices(_ journal: LudeumStore) throws -> ([IGDBPlatform], [Player]) {
    (try journal.shownPlatforms(), try journal.players())
}

func sortText(_ sort: LibrarySort) -> String {
    switch sort {
    case .name: "Name"
    case .platform: "Platform"
    case .rating: "Rating"
    case .intentSet: "Intent set"
    case .year: "Year"
    case .igdbPlayers: "IGDB players' score"
    case .launchBoxPlayers: "LaunchBox players' score"
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

/// A Game in a covers grid: its Cover with badges and its name; clicking selects it, and double-clicking one that
/// offers Play Plays it, as Game detail's Play does.
struct CoverCell: View {
    let services: Services
    let row: LibraryRow
    let width: Double
    @Binding var selection: GameID?
    /// Top-rated's rank, shown before the name.
    var rank: Int? = nil
    /// Why a double-click's Play didn't open, or a version check's warning.
    @State private var playProblem: (title: String, message: String)?
    /// What a double-click starts from (its Resume state, or a multi-disc ROM's Disc), read on hovering, as a Play or a
    /// deleted state may have changed it since.
    @State private var start: PlayStart?

    var body: some View {
        VStack(spacing: 4) {
            CoverTile(services: services, row: row, width: width)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selection == row.id ? Color.accentColor : .clear, lineWidth: 3))
                .onHover { inside in
                    guard inside, row.offersPlay, let play = try? libraryPlay(row, services: services) else { return }
                    Task { start = await playStart(of: play, services: services) }
                }
                .help(start.map { $0 == .rom ? "" : $0.title } ?? "")
            Text(rank.map { "\($0). \(row.name)" } ?? row.name).font(.subheadline).lineLimit(2).multilineTextAlignment(.center)
        }
        .onTapGesture { selection = row.id }
        // Simultaneous, so the first click still selects at once rather than waiting to see if a second follows.
        .simultaneousGesture(TapGesture(count: 2).onEnded { play() }, isEnabled: row.offersPlay)
        .errorAlert($playProblem)
    }

    private func play() {
        startPlay(
            row, services: services, refused: { playProblem = ("Can't Play \(row.name)", $0) }, alert: { playProblem = ($0, $1) })
    }
}

/// The covers grids' size slider, beside Table or Covers.
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
        .frame(width: 220)
        .padding(.horizontal, 8)
        .help("Cover size")
    }
}

struct CoverTile: View {
    let services: Services
    let row: LibraryRow
    let width: Double

    var body: some View {
        // Every badge is this tall (the Rating's pill as wide as its text needs), growing with the Cover, and sits the
        // same margin in from the Cover's edges.
        let height = max(24, width / 5.5)
        let margin = 5.0
        CoverView(services: services, game: row.id, name: row.name)
            .frame(width: width, height: width * 4 / 3)
            .overlay(alignment: .bottomLeading) {
                if let rating = row.rating {
                    Text(ratingText(rating))
                        .font(.system(size: height * 0.64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ratingColor(rating))
                        .padding(.horizontal, height * 0.3)
                        .frame(height: height)
                        // A dark pill, so the Rating's colour reads the same over any cover, light or dark.
                        .background(.black.opacity(0.75), in: .capsule)
                        .padding(margin)
                        .help("Rating")
                        .accessibilityLabel("Rating \(ratingText(rating))")
                }
            }
            .overlay(alignment: .topLeading) {
                if row.outcomes.contains(.finished) {
                    // Grey, as green is Playing's.
                    RoundBadge(symbol: "checkmark", color: .secondary, side: height, weight: .bold)
                        .padding(margin)
                        .help("Finished")
                        .accessibilityLabel("Finished")
                }
            }
            .overlay(alignment: .topTrailing) {
                if let status = CoverStatus(row) {
                    status.badge(height: height)
                        .padding(margin)
                        .help(status.help)
                        .accessibilityLabel(status.help)
                }
            }
            .overlay {
                // Not owned: dimmed, as only a journal entry, with no badge of its own (the table, which can't dim, has
                // one). One flat translucent layer under the other badges: a lowered opacity would either let the Cover
                // show through them or need them drawn offscreen as one.
                if ROMBadge(row) == .notOwned {
                    RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.45)).allowsHitTesting(false)
                        .accessibilityLabel(ROMBadge.notOwned.help)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let badge = OwningBadge(row) {
                    RoundBadge(symbol: badge.symbol, color: badge.color, side: height)
                        .padding(margin)
                        .help(badge.help)
                        .accessibilityLabel(badge.help)
                }
            }
    }
}

/// A Cover's bottom trailing badge, of owning the Game (ADR 0043): a missing ROM's warning, as it's something to fix, else
/// Want to buy's cart, else Archived. Not owned has only its dimming. The table's Name column shows the same symbols.
private struct OwningBadge {
    let symbol: String
    let color: Color
    let help: String

    init?(_ row: LibraryRow) {
        switch (ROMBadge(row), row.wantToBuy) {
        case (.missing?, _), (.archived?, false):
            let rom = ROMBadge(row)!
            (symbol, color, help) = (rom.symbol, rom.color, rom.help)
        case (_, true):
            (symbol, color, help) = (wantToBuySymbol, .blue, "Want to buy")
        default:
            return nil
        }
    }
}

private let wantToBuySymbol = "cart.fill"

/// A Library row's ROM badge: Archived, a missing ROM, or Not owned (no ROM and no Copy that isn't Gone: a plain
/// journal entry); none for a Playable Game, or one with no ROM that I own some other way.
private enum ROMBadge {
    case archived, missing, notOwned

    init?(_ row: LibraryRow) {
        switch row.roms {
        case .playable: return nil
        case .archived: self = .archived
        case .missing: self = .missing
        case .noROMs:
            guard !row.owned else { return nil }
            self = .notOwned
        }
    }

    var symbol: String {
        switch self {
        case .archived: "archivebox"
        case .missing: "exclamationmark.triangle.fill"
        case .notOwned: "book.closed"
        }
    }

    var color: Color {
        switch self {
        case .archived, .notOwned: .secondary
        case .missing: .orange
        }
    }

    var help: String {
        switch self {
        case .archived: "Archived: unarchive to play"
        case .missing: "A ROM is missing from its ROM folder"
        case .notOwned: "Not owned: no ROM, no Copy"
        }
    }
}

/// A Cover's status badge: Playing, else its Intent (Up next or Backlog); none otherwise. Finished has its own badge, at
/// the top leading corner, and Want to buy at the bottom trailing.
private enum CoverStatus {
    case playing, upNext, backlog

    init?(_ row: LibraryRow) {
        if row.isPlaying {
            self = .playing
        } else if row.intent == .upNext {
            self = .upNext
        } else if row.intent == .backlog {
            self = .backlog
        } else {
            return nil
        }
    }

    @ViewBuilder
    func badge(height: Double) -> some View {
        switch self {
        case .playing:
            Bookmark().fill(Color(red: 0.13, green: 0.6, blue: 0.27))
                .frame(width: height * 0.6, height: height)
                .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
        // Green is Playing's alone. Up next has an arrow too, so it isn't told from Backlog by colour alone.
        case .upNext:
            PostIt(color: Color(red: 0.6, green: 0.4, blue: 0.9), side: height, symbol: "arrow.right")
        case .backlog:
            PostIt(color: Color(red: 1, green: 0.62, blue: 0.22), side: height)
        }
    }

    var help: String {
        switch self {
        case .playing: "Playing"
        case .upNext: "Up next"
        case .backlog: "Backlog"
        }
    }
}

/// A symbol on a disc of frosted glass, for the badges that aren't a bookmark or post-it.
private struct RoundBadge: View {
    let symbol: String
    let color: Color
    let side: Double
    var weight: Font.Weight = .regular

    var body: some View {
        Image(systemName: symbol).font(.system(size: side * 0.5, weight: weight)).foregroundStyle(color)
            .frame(width: side, height: side)
            .background(.regularMaterial, in: .circle)
    }
}

/// A square note with its bottom trailing corner folded over, and a symbol written on it if it has one.
private struct PostIt: View {
    let color: Color
    let side: Double
    var symbol: String? = nil

    var body: some View {
        ZStack {
            Sheet().fill(color)
            Fold().fill(.black.opacity(0.18))
            if let symbol {
                // Up and to the leading side of centre, clear of the fold.
                Image(systemName: symbol).font(.system(size: side * 0.45, weight: .heavy)).foregroundStyle(.white)
                    .offset(x: -side * 0.06, y: -side * 0.06)
            }
        }
        .frame(width: side, height: side)
        .compositingGroup()
        .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
    }

    private nonisolated static func foldLength(_ rect: CGRect) -> Double { rect.width / 4 }

    /// The note, less its folded corner.
    private struct Sheet: Shape {
        func path(in rect: CGRect) -> Path {
            let fold = PostIt.foldLength(rect)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - fold))
            path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }

    /// The folded corner's underside, lying on the note.
    private struct Fold: Shape {
        func path(in rect: CGRect) -> Path {
            let fold = PostIt.foldLength(rect)
            var path = Path()
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - fold))
            path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.maxY - fold))
            path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

/// A ribbon with a notch cut into its foot.
private struct Bookmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.width * 0.4))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension LibraryRow {
    /// For the table's Rating column: unrated below 0.0.
    var ratingSortKey: Int { rating?.tenths ?? -1 }
    /// For the table's Intent column: when the Intent was set, undated or none first.
    var intentSetSortKey: Date { intentSetAt ?? .distantPast }
    /// For the table's Year column (the Library sorts it, with no year last).
    var yearSortKey: Int { releaseYear ?? 0 }
    /// For the table's IGDB and LaunchBox columns (the Library sorts them, ranking only scores with 10 or more ratings).
    var igdbPlayersSortKey: Double { igdbPlayerScore.map(\.score) ?? 0 }
    var launchBoxPlayersSortKey: Double { launchBoxPlayerScore.map(\.score) ?? 0 }
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
