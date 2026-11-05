import LudeumCore
import SwiftUI

/// Naming a new List.
struct NewListSheet: View {
    let services: Services
    /// Called with the List once it's made.
    let created: (GameList) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        Form {
            TextField("Name", text: $name)
            if let error { ErrorText(error) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create List", action: create).keyboardShortcut(.defaultAction).disabled(name.trimmed.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
    }

    private func create() {
        guard let journal = services.journal else { return }
        do {
            let list = try journal.createList(named: name)
            services.changes.changed()
            created(list)
            dismiss()
        } catch {
            self.error = journalErrorText(error)
        }
    }
}

/// Game detail's Lists: the ones it's in, each opening the List and with a button to take it out, and adding it to another.
struct GameListsSection: View {
    let services: Services
    let game: GameID
    /// Shows a List's Games.
    let open: (GameList) -> Void

    @State private var lists: [GameList] = []
    @State private var memberOf: [GameList] = []
    @State private var creating = false
    @State private var error: String?

    var body: some View {
        Section("Lists") {
            ForEach(memberOf) { list in
                HStack {
                    Button(list.name) { open(list) }
                        .buttonStyle(.link).help("Show this List")
                    Spacer()
                    Button("Remove from \(list.name)", systemImage: "xmark") {
                        save { try $0.removeGame(game, fromList: list.id) }
                    }
                    .labelStyle(.iconOnly).buttonStyle(.hover).help("Take it out of this List")
                }
            }
            Menu("Add to List", systemImage: "plus") {
                let others = lists.filter { !memberOf.contains($0) }
                ForEach(others) { list in
                    Button(list.name) { save { try $0.addGame(game, toList: list.id) } }
                }
                if !others.isEmpty { Divider() }
                Button("New List…") { creating = true }
            }
            .menuStyle(.borderlessButton).fixedSize()
            .sheet(isPresented: $creating) {
                NewListSheet(services: services) { list in save { try $0.addGame(game, toList: list.id) } }
            }
            if let error { ErrorText(error) }
        }
        .task(id: services.changes.revision) {
            lists = (try? services.journal?.lists()) ?? []
            memberOf = (try? services.journal?.lists(containing: game)) ?? []
        }
    }

    private func save(_ change: (LudeumStore) throws -> Void) {
        guard let journal = services.journal else { return }
        do {
            try change(journal)
            error = nil
            services.changes.changed()
        } catch {
            self.error = journalErrorText(error)
        }
    }
}
