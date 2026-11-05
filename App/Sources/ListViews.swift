import LudeumCore
import SwiftUI

/// Naming a new List, or renaming one.
struct ListNameSheet: View {
    let services: Services
    /// The List to rename; nil makes a new one.
    let renaming: GameList?
    /// Called with a new List once it's made.
    let created: (GameList) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var error: String?

    init(services: Services, renaming: GameList? = nil, created: @escaping (GameList) -> Void = { _ in }) {
        self.services = services
        self.renaming = renaming
        self.created = created
        _name = State(initialValue: renaming?.name ?? "")
    }

    var body: some View {
        Form {
            TextField("Name", text: $name)
            if let error { ErrorText(error) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(renaming == nil ? "Create List" : "Rename List", action: save)
                    .keyboardShortcut(.defaultAction).disabled(name.trimmed.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
    }

    private func save() {
        guard let journal = services.journal else { return }
        do {
            if let renaming {
                try journal.renameList(renaming.id, to: name)
                services.changes.changed()
            } else {
                let list = try journal.createList(named: name)
                services.changes.changed()
                created(list)
            }
            dismiss()
        } catch {
            self.error = journalErrorText(error)
        }
    }
}

/// Game detail's Lists: a pill for each one it's in, which opens the List and has an × to take it out, then adding it to
/// another, all in one wrapping line.
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
            FlowLayout(spacing: 4) {
                ForEach(memberOf) { list in
                    ListPill(name: list.name) {
                        open(list)
                    } remove: {
                        save { try $0.removeGame(game, fromList: list.id) }
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
                // A row's views line up along their tops, and a pill is this much taller.
                .padding(.vertical, 2)
            }
            .sheet(isPresented: $creating) {
                ListNameSheet(services: services) { list in save { try $0.addGame(game, toList: list.id) } }
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

/// A List a Game is in: its name opens it, and the × takes the Game out.
private struct ListPill: View {
    let name: String
    let open: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(name, action: open).buttonStyle(.plain).help("Show this List")
            Button("Remove from \(name)", systemImage: "xmark", action: remove)
                .labelStyle(.iconOnly).buttonStyle(.hover).imageScale(.small).help("Take it out of this List")
        }
        .font(FactStyle.value)
        .padding(.leading, 8).padding(.vertical, 2)
        .background(.quaternary, in: .capsule)
    }
}
