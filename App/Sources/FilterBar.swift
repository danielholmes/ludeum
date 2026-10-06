import LudeumCore
import SwiftUI

/// The kinds of filter the Add filter menu offers. A screen offers the ones it applies, less the
/// ones its scope already fixes.
enum FilterKind: CaseIterable {
    case platform, rating, intent, list, player, genre, theme, played, childhood, roms

    /// What every Library-shaped screen offers.
    static let library = Set(allCases)

    /// The kinds a scope already sets, so the menu doesn't offer them again.
    static func fixed(by scope: LibraryFilter) -> Set<FilterKind> {
        var k: Set<FilterKind> = []
        if scope.platformId != nil { k.insert(.platform) }
        if scope.rating != nil { k.insert(.rating) }
        if scope.intent != nil { k.insert(.intent) }
        if scope.listId != nil { k.insert(.list) }
        if scope.player != nil { k.insert(.player) }
        if scope.genre != nil { k.insert(.genre) }
        if scope.theme != nil { k.insert(.theme) }
        if scope.outcome != nil { k.insert(.played) }
        if scope.childhood != nil { k.insert(.childhood) }
        if scope.roms != nil { k.insert(.roms) }
        return k
    }
}

/// The bar above a screen's Games, reading left to right: the Text filter (where the screen has one), how
/// many, the screen's fixed scope (no ×), the filters I've added (each removable), Add filter, and on the
/// right the screen's own controls (the sort, Table or Covers).
struct FilterBar<Trailing: View>: View {
    /// Nil where the screen doesn't count Games (Year in review, What to play next's sections).
    var count: Int?
    var busy = false
    /// The screen's scope, e.g. "SNES" or "Finished". It can't be removed.
    var scope: String?
    @Binding var filter: LibraryFilter
    var kinds = FilterKind.library
    let platforms: [IGDBPlatform]
    let lists: [GameList]
    var players: [Player] = []
    var genres: [String] = []
    var themes: [String] = []
    /// The Text filter's typing, where the screen has one; ⌥⌘F focuses it.
    var text: Binding<String>?
    var textFocused: FocusState<Bool>.Binding?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            if let text, let textFocused {
                TextField("Filter by text", text: text)
                    .focused(textFocused)
                    .help("Narrow this view by names, companies, franchises, series and keywords (⌥⌘F)")
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onExitCommand { textFocused.wrappedValue = false }
                    .overlay(alignment: .trailing) {
                        if !text.wrappedValue.isEmpty {
                            Button("Clear text filter", systemImage: "xmark.circle.fill") { text.wrappedValue = "" }
                                .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary).padding(.trailing, 5)
                        }
                    }
            }
            if let count { Text("\(count) Game\(count == 1 ? "" : "s")").foregroundStyle(.secondary).fixedSize() }
            if busy { ProgressView().controlSize(.small) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let scope {
                        Text(scope).foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: .capsule)
                            .help("What this screen shows")
                    }
                    ForEach(filterChips(filter, platforms: platforms, lists: lists, players: players), id: \.text) { chip in
                        HStack(spacing: 4) {
                            Text(chip.text)
                            Button("Remove filter", systemImage: "xmark") { chip.clear(&filter) }
                                .labelStyle(.iconOnly).buttonStyle(.hover).imageScale(.small)
                        }
                        .padding(.leading, 8).padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                    }
                    if !kinds.isEmpty {
                        AddFilterMenu(
                            filter: $filter, kinds: kinds, platforms: platforms, lists: lists, players: players, genres: genres,
                            themes: themes)
                    }
                }
            }
            trailing()
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
    }
}

extension FilterBar where Trailing == EmptyView {
    init(
        count: Int? = nil, busy: Bool = false, scope: String? = nil, filter: Binding<LibraryFilter>, kinds: Set<FilterKind>,
        platforms: [IGDBPlatform], lists: [GameList], players: [Player] = []
    ) {
        self.init(
            count: count, busy: busy, scope: scope, filter: filter, kinds: kinds, platforms: platforms, lists: lists,
            players: players, trailing: { EmptyView() })
    }
}

/// Adds one filter (replacing any of the same kind) as a pill.
private struct AddFilterMenu: View {
    @Binding var filter: LibraryFilter
    let kinds: Set<FilterKind>
    let platforms: [IGDBPlatform]
    let lists: [GameList]
    let players: [Player]
    let genres: [String]
    let themes: [String]

    var body: some View {
        Menu("Filter", systemImage: "plus") {
            if kinds.contains(.platform) {
                Menu("Platform") { ForEach(platforms) { p in Button(p.name) { filter.platformId = p.id } } }
            }
            if kinds.contains(.rating) {
                Menu("Rating") {
                    Button("Unrated") { filter.rating = .unrated }
                    ForEach([9, 8, 7, 6, 5], id: \.self) { n in
                        Button("\(n).0 or more") { filter.rating = .atLeast(Rating(tenths: n * 10)!) }
                    }
                }
            }
            if kinds.contains(.intent) {
                Menu("Intent") {
                    Button("None") { filter.intent = .some(nil) }
                    Button("Backlog") { filter.intent = .backlog }
                    Button("Up next") { filter.intent = .upNext }
                }
            }
            if kinds.contains(.list), !lists.isEmpty {
                Menu("List") { ForEach(lists, id: \.id) { l in Button(l.name) { filter.listId = l.id } } }
            }
            if kinds.contains(.player), !players.isEmpty {
                Menu("Player") {
                    Button("Solo") { filter.player = .solo }
                    Divider()
                    ForEach(players) { p in Button(p.draft.fullName) { filter.player = .player(p.id) } }
                }
            }
            if kinds.contains(.genre), !genres.isEmpty {
                Menu("Genre") { ForEach(genres, id: \.self) { g in Button(g) { filter.genre = g } } }
            }
            if kinds.contains(.theme), !themes.isEmpty {
                Menu("Theme") { ForEach(themes, id: \.self) { t in Button(t) { filter.theme = t } } }
            }
            if kinds.contains(.played) {
                Menu("Played") {
                    Button("Playing") { filter.outcome = .playing }
                    Button("Finished") { filter.outcome = .finished }
                    Button("Dropped") { filter.outcome = .dropped }
                    Button("Not played") { filter.outcome = .notPlayed }
                }
            }
            if kinds.contains(.childhood) {
                Menu("Childhood") {
                    Button("Childhood") { filter.childhood = true }
                    Button("Not childhood") { filter.childhood = false }
                }
            }
            if kinds.contains(.roms) {
                Menu("ROMs") {
                    Button("Playable") { filter.roms = .playable }
                    Button("Archived") { filter.roms = .archived }
                }
            }
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Add a filter")
    }
}

/// The sort, as the bar shows it: "Year ↑", a menu to change it. Nil is What to play next's
/// "Default", offered only with `offersDefault`.
struct LibrarySortMenu: View {
    @Binding var sort: LibrarySort?
    @Binding var ascending: Bool
    /// What it offers: Year only where the screen has IGDB's facts to sort by.
    var sorts = LibrarySort.allCases
    var offersDefault = false

    private var status: String { sort.map { "\(sortText($0)) \(ascending ? "↑" : "↓")" } ?? "Default order" }

    var body: some View {
        Menu(status) {
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
                ForEach(sorts, id: \.self) { Text(sortText($0)).tag(LibrarySort?.some($0)) }
            }
            Picker("Order", selection: $ascending) {
                Text("Ascending").tag(true)
                Text("Descending").tag(false)
            }
            .disabled(sort == nil)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Sort")
    }
}

/// One filter as a pill: what it says, and how to remove it.
struct FilterChip {
    let text: String
    let clear: (inout LibraryFilter) -> Void
}

func filterChips(_ filter: LibraryFilter, platforms: [IGDBPlatform], lists: [GameList], players: [Player]) -> [FilterChip] {
    typealias Chip = FilterChip
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
    switch filter.player {
    case .solo: c.append(Chip(text: "Solo") { $0.player = nil })
    case .player(let id):
        c.append(Chip(text: "With \(players.first { $0.id == id }?.draft.fullName ?? "a Player")") { $0.player = nil })
    case nil: break
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
    switch filter.roms {
    case .playable: c.append(Chip(text: "Playable") { $0.roms = nil })
    case .archived: c.append(Chip(text: "Archived") { $0.roms = nil })
    case nil: break
    }
    if let genre = filter.genre { c.append(Chip(text: genre) { $0.genre = nil }) }
    if let theme = filter.theme { c.append(Chip(text: theme) { $0.theme = nil }) }
    if let franchise = filter.franchise { c.append(Chip(text: "Franchise: \(franchise)") { $0.franchise = nil }) }
    if let series = filter.series { c.append(Chip(text: "Series: \(series)") { $0.series = nil }) }
    if let company = filter.company { c.append(Chip(text: "Company: \(company)") { $0.company = nil }) }
    return c
}

/// An empty screen: what's missing and why, with Clear filters when filters are why.
struct EmptyResults: View {
    let title: String
    let systemImage: String
    let description: String
    /// Set when filters are hiding Games.
    var clearFilters: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        } actions: {
            if let clearFilters { Button("Clear filters", action: clearFilters) }
        }
    }
}

extension View {
    /// ⌘1 for Table and ⌘2 for Covers.
    func viewShortcuts(showCovers: Binding<Bool>) -> some View {
        background {
            ZStack {
                Button("Show as Table") { showCovers.wrappedValue = false }.keyboardShortcut("1")
                Button("Show as Covers") { showCovers.wrappedValue = true }.keyboardShortcut("2")
            }
            .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
    }
}

/// Table or Covers, and with Covers their size: in the FilterBar, as they act on that view's Games.
struct ViewModeControls: View {
    @Binding var showCovers: Bool
    @Binding var coverWidth: Double

    var body: some View {
        HStack(spacing: 6) {
            if showCovers { CoverSizeSlider(width: $coverWidth) }
            Picker("View", selection: $showCovers) {
                Label("Table", systemImage: "list.bullet").labelStyle(.iconOnly).help("Table (⌘1)").tag(false)
                Label("Covers", systemImage: "square.grid.2x2").labelStyle(.iconOnly).help("Covers (⌘2)").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }
}

extension FocusedValues {
    /// Focuses the window's Search field (⌘F).
    @Entry var focusSearch: (() -> Void)?
    /// Focuses the shown screen's Text filter (⌥⌘F).
    @Entry var focusTextFilter: (() -> Void)?
}

/// Edit ▸ Search (⌘F) and Filter by Text (⌥⌘F).
struct SearchCommands: Commands {
    @FocusedValue(\.focusSearch) private var focusSearch
    @FocusedValue(\.focusTextFilter) private var focusTextFilter

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Search") { focusSearch?() }.keyboardShortcut("f").disabled(focusSearch == nil)
            Button("Filter by Text") { focusTextFilter?() }.keyboardShortcut("f", modifiers: [.command, .option]).disabled(
                focusTextFilter == nil)
        }
    }
}
