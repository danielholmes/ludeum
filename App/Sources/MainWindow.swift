import JournalCore
import SwiftUI

/// The main window: sidebar, the selected screen, and the Game detail pane.
struct MainWindow: View {
    let services: Services
    @State private var selectedGame: GameID?
    @State private var adding = false
    @State private var selection: Screen? = .library
    @State private var lists: [GameList] = []
    // Filled in by a later slice.
    @State private var reviewQueueCount = 0

    var body: some View {
        NavigationSplitView {
            Sidebar(services: services, selection: $selection, lists: lists, reviewQueueCount: reviewQueueCount)
        } content: {
            switch selection {
            case .library:
                LibraryScreen(services: services, selection: $selectedGame)
            case .list(let id, _):
                if let list = lists.first(where: { $0.id == id }) {
                    LibraryScreen(services: services, list: list, selection: $selectedGame).id(id)
                }
            case let screen?:
                PlaceholderScreen(screen: screen)
            case nil:
                ContentUnavailableView("Nothing selected", systemImage: "sidebar.left")
            }
        } detail: {
            if let selectedGame {
                GameDetailView(services: services, id: selectedGame) { self.selectedGame = nil }.id(selectedGame)
            } else {
                GameDetailPlaceholder()
            }
        }
        .toolbar {
            Button("Add Game", systemImage: "plus") { adding = true }
                .disabled(services.journal == nil)
        }
        .sheet(isPresented: $adding) {
            AddGameSheet(services: services) {
                selectedGame = $0
                services.changes.changed()
            }
        }
        .task(id: services.changes.revision) {
            lists = (try? services.journal?.lists()) ?? []
            if case .list(let id, _) = selection, !lists.contains(where: { $0.id == id }) { selection = .library }
        }
    }
}

struct Sidebar: View {
    let services: Services
    @Binding var selection: Screen?
    let lists: [GameList]
    let reviewQueueCount: Int

    @State private var naming: ListNaming?
    @State private var deleting: GameList?
    @State private var error: String?

    var body: some View {
        List(selection: $selection) {
            Section("Journal") {
                ForEach(Screen.journal, id: \.self) { row($0) }
            }
            Section {
                ForEach(lists, id: \.id) { list in
                    row(.list(id: list.id, name: list.name))
                        .contextMenu {
                            Button("Rename…") { naming = ListNaming(list: list, name: list.name) }
                            Button("Delete…", role: .destructive) { deleting = list }
                        }
                }
            } header: {
                HStack {
                    Text("Lists")
                    Spacer()
                    Button("New List", systemImage: "plus") { naming = ListNaming(list: nil, name: "") }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                        .disabled(services.journal == nil)
                }
            }
            Section("OpenEmu") {
                row(.reviewQueue)
                    .badge(reviewQueueCount)
                row(.importPage)
                row(.syncPage)
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

    private func row(_ screen: Screen) -> some View {
        Label(screen.title, systemImage: screen.systemImage).tag(screen)
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
