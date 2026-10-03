import JournalCore
import SwiftUI

/// The main window: sidebar, the selected screen, and the Game detail pane.
struct MainWindow: View {
    let services: Services
    @State private var selectedGame: GameID?
    @State private var adding = false
    @State private var selection: Screen? = .library
    // Filled in by later slices; empty until the journal is wired up.
    @State private var lists: [Screen] = []
    @State private var reviewQueueCount = 0

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection, lists: lists, reviewQueueCount: reviewQueueCount)
        } content: {
            if let selection {
                PlaceholderScreen(screen: selection)
            } else {
                ContentUnavailableView("Nothing selected", systemImage: "sidebar.left")
            }
        } detail: {
            if let selectedGame {
                GameDetailView(services: services, id: selectedGame).id(selectedGame)
            } else {
                GameDetailPlaceholder()
            }
        }
        .toolbar {
            Button("Add Game", systemImage: "plus") { adding = true }
                .disabled(services.journal == nil)
        }
        .sheet(isPresented: $adding) {
            AddGameSheet(services: services) { selectedGame = $0 }
        }
    }
}

struct Sidebar: View {
    @Binding var selection: Screen?
    let lists: [Screen]
    let reviewQueueCount: Int

    var body: some View {
        List(selection: $selection) {
            Section("Journal") {
                ForEach(Screen.journal, id: \.self) { row($0) }
            }
            Section("Lists") {
                ForEach(lists, id: \.self) { row($0) }
            }
            Section("OpenEmu") {
                row(.reviewQueue)
                    .badge(reviewQueueCount)
                row(.importPage)
                row(.syncPage)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }

    private func row(_ screen: Screen) -> some View {
        Label(screen.title, systemImage: screen.systemImage).tag(screen)
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
