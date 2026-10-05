import JournalCore
import SwiftUI

/// The main window: sidebar, the selected screen, and the Game detail pane.
struct MainWindow: View {
    let services: Services
    let importModel: ImportModel
    let syncModel: SyncModel
    @State private var selectedGame: GameID?
    @State private var igdbQuery = ""
    /// The IGDB screen's selected result, shown in the detail column instead of a Game.
    @State private var igdbResult: GameSearchResult?
    @State private var selection: Screen? = .library
    /// A filter another screen asked the Library to open with, bumping `libraryRequest` to apply it.
    @State private var libraryFilter = LibraryFilter()
    @State private var libraryRequest = 0
    @State private var lists: [GameList] = []
    @State private var reviewQueueCount = 0
    @State private var platformCounts: [PlatformCount] = []
    @State private var pins: [Pin] = []

    /// Opens a Game in the detail column, leaving any IGDB result.
    private func openGame(_ id: GameID) {
        igdbResult = nil
        selectedGame = id
    }

    /// Opens the Library with `filter`, keeping the selected Game.
    private func showInLibrary(_ filter: LibraryFilter) {
        libraryFilter = filter
        libraryRequest += 1
        selection = .library
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(
                services: services, selection: $selection, lists: lists, platforms: platformCounts, pins: pins,
                reviewQueueCount: reviewQueueCount)
        } content: {
            switch selection {
            case .library:
                LibraryScreen(services: services, selection: $selectedGame, initialFilter: libraryFilter)
                    .id(libraryRequest)
            case .finished, .childhood:
                if let screen = selection, let scope = screen.shortcutFilter {
                    LibraryScreen(services: services, selection: $selectedGame, scope: scope, title: screen.title).id(selection)
                }
            case .platform(let id, let name):
                LibraryScreen(services: services, selection: $selectedGame, scope: LibraryFilter(platformId: id), title: name)
                    .id(selection)
            case .pinned(let pin):
                LibraryScreen(services: services, selection: $selectedGame, scope: pin.filter, title: pin.name)
                    .id(selection)
            case .list(let id, _):
                if let list = lists.first(where: { $0.id == id }) {
                    LibraryScreen(services: services, selection: $selectedGame, scope: LibraryFilter(listId: id), title: list.name).id(id)
                }
            case .whatToPlayNext:
                WhatToPlayNextScreen(services: services, selection: $selectedGame)
            case .topRated:
                TopRatedScreen(services: services, selection: $selectedGame)
            case .yearInReview:
                YearInReviewScreen(services: services, selection: $selectedGame, openLibrary: showInLibrary)
            case .igdb:
                IGDBScreen(services: services, query: $igdbQuery, shown: $igdbResult, open: openGame)
            case .reviewQueue:
                ReviewQueueScreen(services: services, checkAgain: importModel.importNow, shownGame: $selectedGame)
                    .disabled(services.work.journalLocked)
            case .syncPage:
                SyncPage(model: syncModel)
            case .importPage:
                ImportPage(model: importModel)
            case let screen?:
                PlaceholderScreen(screen: screen)
            case nil:
                ContentUnavailableView("Nothing selected", systemImage: "sidebar.left")
            }
        } detail: {
            if selection == .igdb, let igdbResult {
                IGDBGameDetailView(services: services, result: igdbResult, browse: showInLibrary, open: openGame)
                    .id(igdbResult.id)
            } else if let selectedGame {
                GameDetailView(services: services, id: selectedGame, browse: showInLibrary) { self.selectedGame = nil }
                    .id(selectedGame)
                    .disabled(services.work.journalLocked)
            } else {
                GameDetailPlaceholder()
            }
        }
        .overlay(alignment: .bottom) {
            if let summary = importModel.summary {
                ImportSummaryBanner(summary: summary, open: { selectedGame = $0 }, dismiss: { importModel.summary = nil })
                    .frame(maxWidth: 520)
            }
        }
        .onChange(of: selection) { if selection != .library { libraryFilter = LibraryFilter() } }
        .modifier(OngoingImportTriggers(model: importModel))
        .modifier(CacheRefreshOnLaunch(services: services))
        .toolbar {
            ToolbarItem(placement: .status) { RefreshStatus(work: services.work) }
            ToolbarItem {
                HStack(spacing: 6) {
                    if services.work.journalLocked {
                        Text("Can't edit while the Import writes").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Add Game", systemImage: "plus") { selection = .igdb }
                        .help("Search IGDB to add a Game")
                }
            }
            // Its own group, apart from the screen's search and filters that follow it.
            if #available(macOS 26, *) { ToolbarSpacer(.fixed) }
        }
        .task(id: services.changes.revision) {
            lists = (try? services.journal?.lists()) ?? []
            reviewQueueCount = (try? services.journal?.reviewQueue().count) ?? 0
            platformCounts = (try? services.journal?.platformCounts()) ?? []
            pins = (try? services.journal?.pins()) ?? []
            if case .pinned(let pin) = selection, !pins.contains(pin) { selection = .library }
            if case .list(let id, _) = selection, !lists.contains(where: { $0.id == id }) { selection = .library }
        }
    }
}

struct Sidebar: View {
    let services: Services
    @Binding var selection: Screen?
    let lists: [GameList]
    let platforms: [PlatformCount]
    let pins: [Pin]
    let reviewQueueCount: Int

    @State private var naming: ListNaming?
    @State private var deleting: GameList?
    @State private var error: String?

    var body: some View {
        List(selection: $selection) {
            Section("Journal") {
                ForEach(Screen.journal, id: \.self) { row($0) }
            }
            Section("OpenEmu") {
                row(.reviewQueue, badge: reviewQueueCount)
                row(.importPage, running: services.work.exclusive == .importing)
                row(.syncPage, running: services.work.exclusive == .syncing)
            }
            if !platforms.isEmpty {
                Section("Platforms") {
                    ForEach(platforms, id: \.id) { p in
                        row(.platform(id: p.id, name: p.name), badge: p.games)
                    }
                }
            }
            if !pins.isEmpty {
                Section("Pinned") {
                    ForEach(pins, id: \.self) { pin in
                        row(.pinned(pin))
                            .help(pin.kind.rawValue.capitalized)
                            .contextMenu { Button("Unpin") { save { try $0.unpin(pin) } } }
                    }
                }
            }
            Section {
                ForEach(lists, id: \.id) { list in
                    row(.list(id: list.id, name: list.name))
                        .contextMenu {
                            Button("Rename…") { naming = ListNaming(list: list, name: list.name) }
                            Button("Delete…", role: .destructive) { deleting = list }
                        }
                        .disabled(services.work.journalLocked)
                }
            } header: {
                HStack {
                    Text("Lists")
                    Spacer()
                    Button("New List", systemImage: "plus") { naming = ListNaming(list: nil, name: "") }
                        .labelStyle(.iconOnly).buttonStyle(.hover)
                        .disabled(services.journal == nil || services.work.journalLocked)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        .sheet(item: $naming) { naming in
            ListNameSheet(naming: naming) { name in
                apply {
                    if let list = naming.list {
                        try $0.renameList(list.id, name)
                    } else {
                        let id = try $0.createList(name)
                        selection = .list(id: id, name: name)
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete the List \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("Delete List", role: .destructive) { if let list = deleting { save { try $0.deleteList(list.id) } } }
        } message: {
            Text(
                "Its Games stay in the journal. The next Sync deletes its collection in OpenEmu. There's no undo; a backup is taken first.")
        }
        .alert("Couldn't change the List", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: {
            Text(error ?? "")
        }
    }

    /// `running` animates the icon while that screen's work (Import, Sync) runs.
    private func row(_ screen: Screen, badge: Int = 0, running: Bool = false) -> some View {
        // The badge goes inside the tag: a badge outside it hides the tag, and the row can't be selected.
        Label {
            Text(screen.title)
        } icon: {
            if case .platform(let id, _) = screen {
                PlatformIcon(platformId: id)
            } else {
                Image(systemName: running ? "arrow.triangle.2.circlepath" : screen.systemImage)
                    .symbolEffect(.rotate, isActive: running)
            }
        }
        .help(running ? "\(screen.title) running" : "")
        .badge(badge).tag(screen)
    }

    private func save(_ change: (JournalStore) throws -> Void) {
        error = apply(change)
    }

    /// Runs a journal change and reloads the screens, or returns what went wrong.
    private func apply(_ change: (JournalStore) throws -> Void) -> String? {
        guard let journal = services.journal else { return nil }
        do {
            try change(journal)
            services.changes.changed()
            return nil
        } catch {
            return journalErrorText(error)
        }
    }
}

struct ListNaming: Identifiable {
    /// Nil for a new List.
    let list: GameList?
    let name: String
    var id: Int64 { list?.id ?? -1 }
}

/// Naming a new List, or renaming one. `save` returns an error to show, or nil when done.
struct ListNameSheet: View {
    let naming: ListNaming
    let save: (String) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        Form {
            TextField("Name", text: $name)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(naming.list == nil ? "Create" : "Rename") {
                    error = save(name.trimmed)
                    if error == nil { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmed.isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear { name = naming.name }
    }
}

struct PlaceholderScreen: View {
    let screen: Screen

    var body: some View {
        ContentUnavailableView(screen.title, systemImage: screen.systemImage, description: Text("Coming soon."))
            .navigationTitle(screen.title)
    }
}

struct GameDetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView("No Game selected", systemImage: "gamecontroller")
    }
}
