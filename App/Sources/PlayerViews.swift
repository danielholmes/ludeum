import LudeumCore
import SwiftUI

extension PlayerColour {
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        }
    }
}

/// A Player as a badge: their initials in their colour, the full name on hover.
struct PlayerBadge: View {
    let player: PlayerDraft
    var size: CGFloat = 20

    var body: some View {
        Text(player.initials)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(player.colour.color.gradient, in: .circle)
            .help(player.fullName)
            .accessibilityLabel(player.fullName)
    }
}

/// A row of badges for the Players with these ids.
struct PlayerBadges: View {
    let ids: [Int64]
    let players: [Player]
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ids.compactMap { id in players.first { $0.id == id } }) { PlayerBadge(player: $0.draft, size: size) }
        }
    }
}

/// Settings' Players: add, edit and delete the people I play with.
struct PlayersSection: View {
    let journal: LudeumStore?

    @State private var players: [Player] = []
    @State private var editing: PlayerEdit?
    @State private var deleting: Player?
    @State private var deletingCount = 0
    @State private var error: String?

    var body: some View {
        Section {
            ForEach(players) { p in
                HStack {
                    PlayerBadge(player: p.draft)
                    Text(p.draft.fullName)
                    Spacer()
                    Button("Edit…") { editing = PlayerEdit(id: p.id, draft: p.draft) }
                    Button("Delete…", role: .destructive) {
                        deletingCount = (try? journal?.playthroughCount(with: p.id)) ?? 0
                        deleting = p
                    }
                }
            }
            Button("Add Player…", systemImage: "plus") {
                editing = PlayerEdit(
                    id: nil, draft: PlayerDraft(firstName: "", lastName: "", colour: (try? journal?.nextPlayerColour()) ?? .red))
            }
            .disabled(journal == nil)
            if let error { Text(error).foregroundStyle(.red) }
        } header: {
            Text("Players")
        } footer: {
            Text("The people I play with. I'm on every Playthrough, so one with no Players is Solo.").foregroundStyle(.secondary)
        }
        .onAppear(perform: load)
        .sheet(item: $editing) { edit in
            if let journal { PlayerSheet(journal: journal, edit: edit, done: load) }
        }
        .confirmationDialog(
            "Delete \(deleting?.draft.fullName ?? "this Player")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("Delete Player", role: .destructive) {
                guard let p = deleting, let journal else { return }
                do {
                    try journal.deletePlayer(p.id)
                    load()
                } catch {
                    self.error = journalErrorText(error)
                }
            }
        } message: {
            Text(
                deletingCount == 0
                    ? "They aren't on any Playthroughs."
                    : "They'll be taken off \(deletingCount) Playthrough\(deletingCount == 1 ? "" : "s"). A backup is taken first.")
        }
    }

    private func load() {
        players = (try? journal?.players()) ?? []
    }
}

struct PlayerEdit: Identifiable {
    /// Nil for a new Player.
    let id: Int64?
    let draft: PlayerDraft
}

/// Adding or editing a Player: both names and a colour.
struct PlayerSheet: View {
    let journal: LudeumStore
    let edit: PlayerEdit
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var colour = PlayerColour.red
    @State private var error: String?

    private var draft: PlayerDraft { PlayerDraft(firstName: firstName, lastName: lastName, colour: colour) }

    var body: some View {
        Form {
            TextField("First name", text: $firstName)
            TextField("Last name", text: $lastName)
            LabeledContent("Colour") {
                HStack(spacing: 4) {
                    ForEach(PlayerColour.allCases, id: \.self) { c in
                        Button {
                            colour = c
                        } label: {
                            Circle().fill(c.color.gradient).frame(width: 18, height: 18)
                                .overlay { if c == colour { Circle().strokeBorder(.primary, lineWidth: 2) } }
                        }
                        .buttonStyle(.plain)
                        .help(c.rawValue.capitalized)
                    }
                }
            }
            LabeledContent("Badge") { PlayerBadge(player: draft, size: 28) }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .onAppear {
            firstName = edit.draft.firstName
            lastName = edit.draft.lastName
            colour = edit.draft.colour
        }
    }

    private func save() {
        do {
            if let id = edit.id { try journal.updatePlayer(id, draft) } else { try journal.addPlayer(draft) }
            done()
            dismiss()
        } catch {
            self.error = journalErrorText(error)
        }
    }
}

/// Choosing a Playthrough's Players: a checkbox each.
struct PlayerPicker: View {
    let players: [Player]
    @Binding var selected: Set<Int64>

    var body: some View {
        LabeledContent("Players") {
            if players.isEmpty {
                Text("Add Players in Settings").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(players) { p in
                        Toggle(
                            isOn: Binding(
                                get: { selected.contains(p.id) },
                                set: { on in if on { selected.insert(p.id) } else { selected.remove(p.id) } })
                        ) {
                            HStack(spacing: 6) {
                                PlayerBadge(player: p.draft, size: 18)
                                Text(p.draft.fullName)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
        }
    }
}
