import LudeumCore
import SwiftUI

/// The main window: sidebar, the selected screen, and the Game detail pane.
struct MainWindow: View {
    let services: Services
    let importModel: ImportModel
    @State private var selectedGame: GameID?
    /// The selected screen and Game, kept for the next launch.
    @AppStorage("mainSelectedScreen") private var savedScreen = Data()
    @AppStorage("mainSelectedGame") private var savedGame = 0
    @State private var igdbQuery = ""
    /// What's typed in the toolbar's Search, until Return opens it in the Library.
    @State private var searchText = ""
    @State private var searchFocused = false
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
    /// The journal still has OpenEmu ROMs: `migrate-openemu` hasn't run.
    @State private var needsOpenEmuMigration = false

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

    /// A Search: the Library with every filter cleared, and the text as its Text filter.
    private func search() {
        showInLibrary(LibraryFilter(name: searchText.trimmed))
        searchText = ""
        searchFocused = false
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(
                services: services, selection: $selection, lists: lists, platforms: platformCounts, pins: pins,
                reviewQueueCount: reviewQueueCount
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BackgroundTasksPanel(tasks: services.tasks, work: services.work, journal: services.journal, open: openGame)
            }
            // The sidebar is always shown: no toggle to hide it.
            .toolbar(removing: .sidebarToggle)
            // Never narrower than this: it's what I go by most.
            .navigationSplitViewColumnWidth(min: 300, ideal: 300, max: 400)
        } content: {
            Group {
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
                        .navigationSubtitle(Emulator.of(platformId: id)?.name ?? "")
                        .id(selection)
                case .pinned(let pin):
                    LibraryScreen(services: services, selection: $selectedGame, scope: pin.filter, title: pin.name)
                        .id(selection)
                case .list(let id, _):
                    if let list = lists.first(where: { $0.id == id }) {
                        LibraryScreen(services: services, selection: $selectedGame, scope: LibraryFilter(listId: id), title: list.name).id(
                            id)
                    }
                case .whatToPlayNext:
                    WhatToPlayNextScreen(services: services, selection: $selectedGame)
                case .topRated:
                    TopRatedScreen(services: services, selection: $selectedGame)
                case .yearInReview:
                    YearInReviewScreen(services: services, selection: $selectedGame)
                case .igdb:
                    IGDBScreen(services: services, query: $igdbQuery, shown: $igdbResult, open: openGame)
                case .reviewQueue:
                    ReviewQueueScreen(services: services, checkAgain: { importModel.importNow() }, shownGame: $selectedGame)
                        .disabled(services.work.journalLocked)
                case let screen?:
                    PlaceholderScreen(screen: screen)
                case nil:
                    ContentUnavailableView("Nothing selected", systemImage: "sidebar.left")
                }
            }
            // The rest of the window, after the sidebar and the Game. The Review queue's three columns need more.
            .navigationSplitViewColumnWidth(min: selection == .reviewQueue ? ReviewQueueScreen.minWidth : 400, ideal: 800)
        } detail: {
            Group {
                if selection == .igdb, let igdbResult {
                    IGDBGameDetailView(services: services, result: igdbResult, browse: showInLibrary, open: openGame)
                        .id(igdbResult.id)
                } else if let selectedGame {
                    // A delete finishes off the main thread, and by then another Game may be the one selected.
                    GameDetailView(services: services, id: selectedGame, browse: showInLibrary) {
                        if self.selectedGame == selectedGame { self.selectedGame = nil }
                    }
                    .id(selectedGame)
                    .disabled(services.work.journalLocked)
                } else {
                    GameDetailPlaceholder()
                }
            }
            .navigationSplitViewColumnWidth(min: 360, ideal: 600, max: 900)
        }
        .modifier(ImportBanners(model: importModel, needsOpenEmuMigration: needsOpenEmuMigration) { selectedGame = $0 })
        .onChange(of: selection) {
            if selection != .library { libraryFilter = LibraryFilter() }
            savedScreen = (try? JSONEncoder().encode(selection)) ?? Data()
        }
        .onChange(of: selectedGame) { savedGame = Int(selectedGame ?? 0) }
        .onAppear {
            if let screen = try? JSONDecoder().decode(Screen?.self, from: savedScreen) { selection = screen }
            if savedGame != 0 { selectedGame = GameID(savedGame) }
        }
        .background(WindowFrameAutosave(name: "main"))
        .modifier(ImportOnLaunch(model: importModel))
        .modifier(CacheRefreshOnLaunch(services: services))
        .modifier(EmulatorVersionsOnLaunch(services: services))
        .modifier(SystemToolsOnLaunch())
        .sheet(isPresented: Bindable(services.sheets).emulators) { EmulatorsSheet(services: services) }
        .sheet(isPresented: Bindable(services.sheets).players) { PlayersSheet(services: services) }
        .sheet(isPresented: Bindable(services.sheets).storageStats) { StorageStatsSheet(services: services) }
        .toolbar {
            ToolbarItem {
                HStack(spacing: 6) {
                    if services.work.journalLocked {
                        Text("Can't edit while the Import writes").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Add Game", systemImage: "plus") { selection = .igdb }
                        .help("Search IGDB to add a Game")
                }
            }
        }
        .searchable(text: $searchText, isPresented: $searchFocused, placement: .toolbar, prompt: "Search the Library")
        .onSubmit(of: .search, search)
        .focusedSceneValue(\.focusSearch) { searchFocused = true }
        .task(id: services.changes.revision) {
            lists = (try? services.journal?.lists()) ?? []
            reviewQueueCount = (try? services.journal?.reviewQueue().count) ?? 0
            platformCounts = (try? services.journal?.platformCounts()) ?? []
            pins = (try? services.journal?.pins()) ?? []
            needsOpenEmuMigration = (try? services.journal?.needsOpenEmuMigration()) == true
            if case .pinned(let pin) = selection, !pins.contains(pin) { selection = .library }
            if case .list(let id, _) = selection, !lists.contains(where: { $0.id == id }) { selection = .library }
            if case .platform(let id, _) = selection, !platformCounts.contains(where: { $0.id == id }) { selection = .library }
            if let game = selectedGame, (try? services.journal?.game(game)) == nil { selectedGame = nil }
        }
    }
}

/// Saves the window's frame as it's moved and resized, and opens it there next launch.
private struct WindowFrameAutosave: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window, window.frameAutosaveName != name else { return }
            window.setFrameAutosaveName(name)
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
                // Its Check again runs an Import, so it shows while one runs.
                row(.reviewQueue, badge: reviewQueueCount, running: services.work.importing)
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
        }
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
            Button("Delete List", role: .destructive) { if let list = deleting { delete(list) } }
        } message: {
            Text("Its Games stay in the journal. There's no undo; a backup is taken first.")
        }
        .alert("Couldn't change the List", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: {
            Text(error ?? "")
        }
    }

    /// `running` animates the icon while an Import runs.
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
        .help(running ? "Import running" : "")
        .badge(badge).tag(screen)
    }

    private func save(_ change: (LudeumStore) throws -> Void) {
        error = apply(change)
    }

    /// Off the main thread, as a backup of the whole journal is taken first.
    private func delete(_ list: GameList) {
        guard let journal = services.journal else { return }
        let id = list.id
        Task {
            do {
                try await offMain { try journal.deleteList(id) }
                services.changes.changed()
            } catch {
                self.error = journalErrorText(error)
            }
        }
    }

    /// Runs a journal change and reloads the screens, or returns what went wrong.
    private func apply(_ change: (LudeumStore) throws -> Void) -> String? {
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
