import JournalCore
import SwiftUI

/// A Rating's colour: red at 0, through yellow at 5, to green at 10.
func ratingColor(_ rating: Rating) -> Color {
    Color(hue: Double(rating.tenths) / 100 / 3, saturation: 0.85, brightness: 0.9)
}

/// The current Rating, big, or "Unrated".
struct RatingBadge: View {
    let rating: Rating?
    let imported: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let rating {
                Text(ratingText(rating)).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(ratingColor(rating))
                Text("/ 10").foregroundStyle(.secondary)
                if imported { Text("≈ from OpenEmu stars").font(.caption).foregroundStyle(.secondary) }
            } else {
                Text("Unrated").font(.title2).foregroundStyle(.secondary)
            }
        }
    }
}

/// A label and its values as pills, wrapping. With `open`, each pill is a link.
struct PillRow: View {
    let title: String
    let items: [String]
    /// What each pill says; the item itself by default.
    var label: (String) -> String = { $0 }
    /// A last pill, "+N more", that shows the hidden items.
    var more: (count: Int, show: () -> Void)? = nil
    var open: ((String) -> Void)? = nil
    /// With `togglePin`, each pill's context menu pins or unpins it; `pinned` are the pinned names.
    var pinned: Set<String> = []
    var togglePin: ((String) -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(FactStyle.label).foregroundStyle(.secondary).frame(width: FactStyle.labelWidth, alignment: .leading)
            FlowLayout(spacing: 4) {
                ForEach(items, id: \.self) { item in
                    if let open {
                        LinkPill(text: label(item), pinned: pinned.contains(item)) { open(item) }
                            .help("Every Game in the journal with \(title.lowercased()) \(item)")
                            .contextMenu {
                                if let togglePin {
                                    Button(pinned.contains(item) ? "Unpin from Sidebar" : "Pin to Sidebar") { togglePin(item) }
                                }
                            }
                    } else {
                        pill(label(item), systemImage: nil)
                    }
                }
                if let more {
                    Button {
                        more.show()
                    } label: {
                        pill("+\(more.count) more", systemImage: nil).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A pill that opens something: its arrow shows only on hover; a pinned one always shows its pin.
private struct LinkPill: View {
    let text: String
    let pinned: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            pill(text, systemImage: pinned ? "pin.fill" : hovering ? "arrow.forward" : nil)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private func pill(_ text: String, systemImage: String?) -> some View {
    HStack(spacing: 3) {
        Text(text)
        if let systemImage { Image(systemName: systemImage).imageScale(.small).foregroundStyle(.secondary) }
    }
    .font(FactStyle.value).padding(.horizontal, 10).padding(.vertical, 3).background(.quaternary, in: .capsule)
}

struct Screenshot: Identifiable {
    let id: String
}

/// An IGDB screenshot, downloaded on first view; a grey box until then.
struct ScreenshotImage: View {
    let igdb: IGDBClient
    let imageID: String
    let large: Bool
    @State private var image: NSImage?

    var body: some View {
        // The image is an overlay, so its pixel size never pushes the layout wider than offered.
        Rectangle().fill(.quaternary)
            .overlay {
                if let image { Image(nsImage: image).resizable().interpolation(.high).scaledToFill() }
            }
            .clipped()
            .task(id: imageID) {
                if let file = try? await igdb.screenshot(imageID: imageID, large: large) { image = NSImage(contentsOf: file) }
            }
    }
}

/// The Game's rarely-changed details: name override, Cover upload, IGDB link, and deleting it.
struct EditGameSheet: View {
    let services: Services
    let game: Game
    let canLink: Bool
    let link: () -> Void
    let delete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var nameOverride = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("Name override", text: $nameOverride, prompt: Text("Use IGDB's name"))
            }
            Section("Cover") {
                CoverEditor(services: services, game: game.id, name: game.name)
            }
            if canLink {
                Section {
                    if game.igdbGameId == nil {
                        Button("Link to IGDB…") { close(then: link) }
                    } else {
                        Button("Change IGDB link…") { close(then: link) }
                        Text("For a Game matched to the wrong IGDB game. Its name and Cover art follow the new link.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button("Delete Game…", role: .destructive) { close(then: delete) }
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Done", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear { nameOverride = (try? services.journal?.nameOverride(game.id)) ?? nil ?? "" }
    }

    private func close(then action: @escaping () -> Void) {
        dismiss()
        // After the sheet has gone, so the next sheet or alert can show.
        Task { @MainActor in action() }
    }

    private func save() {
        let name = nameOverride.trimmed
        do {
            if name != ((try services.journal?.nameOverride(game.id)) ?? nil ?? "") {
                try services.journal?.setNameOverride(game.id, name.isEmpty ? nil : name)
                services.changes.changed()
            }
            dismiss()
        } catch {
            self.error = journalErrorText(error)
        }
    }
}

/// Every Rating the Game has had, newest first, each deletable.
struct RatingHistorySheet: View {
    let history: [RatingEntry]
    let delete: (RatingEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Rating history").font(.headline).padding()
            List(history, id: \.id) { entry in
                HStack {
                    Text(entry.day).monospacedDigit()
                    Text(entry.rating.map(ratingText) ?? "Unrated")
                    if entry.imported { Text("imported").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Delete", systemImage: "trash") { delete(entry) }.labelStyle(.iconOnly).buttonStyle(.hover)
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 360, height: 360)
    }
}

/// The current Rating, big and coloured, edited in place: click it (or "Unrated"), type, Return.
/// An empty field clears it. The clock opens the Rating history.
struct RatingEditor: View {
    let rating: Rating?
    let imported: Bool
    let hasHistory: Bool
    let set: (Rating?) -> Void
    let showHistory: () -> Void
    @State private var editing = false
    @State private var text = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if editing {
                // Label hidden: inside a Form, a TextField otherwise shows its label beside the field.
                TextField("Rating", text: $text, prompt: Text("0.0–10.0"))
                    .labelsHidden()
                    .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    .multilineTextAlignment(.leading)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .frame(width: 96)
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
                    .onChange(of: focused) { _, now in if !now, editing { commit() } }
                if invalid { Text("0.0 to 10.0, in steps of 0.1").font(.caption).foregroundStyle(.red) }
            } else {
                Button(action: startEditing) {
                    RatingBadge(rating: rating, imported: imported)
                }
                .buttonStyle(.plain).help(rating == nil ? "Click to rate" : "Click to change the Rating")
            }
            if hasHistory {
                Button("Rating history", systemImage: "clock.arrow.circlepath", action: showHistory)
                    .labelStyle(.iconOnly).buttonStyle(.hover).help("Rating history")
            }
        }
    }

    private func startEditing() {
        text = rating.map(ratingText) ?? ""
        invalid = false
        editing = true
        focused = true
    }

    private func commit() {
        let trimmed = text.trimmed
        if trimmed.isEmpty {
            if rating != nil { set(nil) }
        } else if let new = parseRating(trimmed) {
            // Re-entering an imported value confirms it as mine.
            if new != rating || imported { set(new) }
        } else {
            invalid = true
            return
        }
        editing = false
    }
}

/// GoodTools region codes in a ROM's Version, spelled out: "U · !" → "USA · !".
func readableVersion(_ version: String?) -> String? {
    let codes = [
        "U": "USA", "E": "Europe", "J": "Japan", "UE": "USA, Europe", "JU": "Japan, USA", "JUE": "Japan, USA, Europe",
        "JE": "Japan, Europe", "W": "World", "B": "Brazil", "F": "France", "G": "Germany", "K": "Korea",
    ]
    return version.map { $0.components(separatedBy: " · ").map { codes[$0] ?? $0 }.joined(separator: " · ") }
}

/// IGDB's scores beside mine: players' and critics', each with how many it averages, so a score
/// from a handful of ratings reads as the guess it is.
struct CommunityScores: View {
    let players: CommunityScore?
    let critics: CommunityScore?

    var body: some View {
        if players != nil || critics != nil {
            HStack(spacing: 14) {
                if let players { score("Players", players, noun: "rating") }
                if let critics { score("Critics", critics, noun: "review") }
                Text("IGDB").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func score(_ title: String, _ s: CommunityScore, noun: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title).font(FactStyle.label).foregroundStyle(.secondary)
            Text(ratingText(s.rating)).font(FactStyle.value.bold()).monospacedDigit().foregroundStyle(ratingColor(s.rating))
            Text("(\(s.count) \(noun)\(s.count == 1 ? "" : "s"))").font(FactStyle.label).foregroundStyle(.secondary)
        }
        .help("IGDB \(title.lowercased()): \(String(format: "%.1f", s.score / 10)) from \(s.count) \(noun)\(s.count == 1 ? "" : "s")")
    }
}

/// Text sizes for the IGDB facts on Game detail (Genre, Theme, Companies, Links…): 1.5× the
/// caption labels and subheadline values they started as.
enum FactStyle {
    static let label = Font.system(size: 15)
    static let value = Font.system(size: 16.5)
    /// The label column's width, so the values line up.
    static let labelWidth: CGFloat = 100
}
