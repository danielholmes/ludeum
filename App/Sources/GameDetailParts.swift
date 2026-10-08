import AppKit
import LudeumCore
import SwiftUI

/// A Rating's colour: red at 2 and under, through yellow at 6, to green at 10.
func ratingColor(_ rating: Rating) -> Color {
    let fraction = Double(max(rating.tenths, 20) - 20) / 80
    return Color(hue: fraction / 3, saturation: 0.85, brightness: 0.9)
}

/// The current Rating, big, or "Unrated".
struct RatingBadge: View {
    let rating: Rating?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let rating {
                Text(ratingText(rating)).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(ratingColor(rating))
                Text("/ 10").foregroundStyle(.secondary)
            } else {
                Text("Unrated").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
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
    .font(FactStyle.value).padding(.horizontal, 8).padding(.vertical, 2).background(.quaternary, in: .capsule)
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
                // A Game with no ROM finds its Box art by its name.
                services.changes.coverChanged()
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
                    RatingBadge(rating: rating)
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
            if new != rating { set(new) }
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
    /// Label above value, to sit beside my Rating on Game detail.
    var stacked = false

    var body: some View {
        if players != nil || critics != nil {
            HStack(alignment: .lastTextBaseline, spacing: stacked ? 24 : 14) {
                if let players { score("Players", players, noun: "rating") }
                if let critics { score("Critics", critics, noun: "review") }
                Text("IGDB").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func score(_ title: String, _ s: CommunityScore, noun: String) -> some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(title) · \(s.count)").font(FactStyle.label).foregroundStyle(.secondary)
                    Text(ratingText(s.rating)).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(ratingColor(s.rating))
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(title).font(FactStyle.label).foregroundStyle(.secondary)
                    Text(ratingText(s.rating)).font(FactStyle.value.bold()).monospacedDigit().foregroundStyle(ratingColor(s.rating))
                    Text("(\(s.count) \(noun)\(s.count == 1 ? "" : "s"))").font(FactStyle.label).foregroundStyle(.secondary)
                }
            }
        }
        .help("IGDB \(title.lowercased()): \(String(format: "%.1f", s.score / 10)) from \(s.count) \(noun)\(s.count == 1 ? "" : "s")")
    }
}

/// Text for the IGDB facts on Game detail (Genre, Theme, Companies, Links…): the panel's body size,
/// labels in grey, so they read like the rest of it.
enum FactStyle {
    static let label = Font.body
    static let value = Font.body
    /// The label column's width, so the values line up.
    static let labelWidth: CGFloat = 92
}

/// Opens `play`'s ROM in `emulator`, with every Emulator setting on the command line. A running Emulator gets the ROM
/// in its open window. `refused` gets why it couldn't, then or once the Emulator fails to open; `alert` gets a version
/// check's title and message.
@MainActor func startPlay(
    _ play: Play, in emulator: Emulator, services: Services, refused: @escaping @MainActor (String) -> Void,
    alert: (_ title: String, _ message: String) -> Void
) {
    let version: Play.VersionStatus =
        if let tooOld = services.versions.tooOldMessage(emulator) {
            .tooOld(tooOld)
        } else if let warning = services.versions.warningOnce(emulator) {
            .warn(warning)
        } else {
            .ok
        }
    let locator = ROMLocator(romFolders: services.settings.romFolders)
    switch play.prepare(locator: locator, version: version, app: NSWorkspace.shared.urlForApplication(withBundleIdentifier:)) {
    case .refused(.tooOld(let message)):
        alert("Can't Play in \(emulator.name)", message)
    case .refused(let refusal):
        refused(refusal.message)
    case .open(let app, let arguments, let warning):
        if let warning { alert("Check \(emulator.name)'s version", warning) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        // A second MesenCE hands its arguments to the running one and quits; DuckStation opens another window.
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
            if let error { Task { @MainActor in refused("Couldn't open \(emulator.name): \(error.localizedDescription)") } }
        }
    }
}

/// Plays a Library row's Game as Game detail's Play does, reading its ROMs and Emulator settings first: a double-click
/// on its Cover. `refused` and `alert` as `startPlay(_:in:services:refused:alert:)`.
@MainActor func startPlay(
    _ row: LibraryRow, services: Services, refused: @escaping @MainActor (String) -> Void,
    alert: (_ title: String, _ message: String) -> Void
) {
    guard let journal = services.journal, let emulator = Emulator.of(platformId: row.platformId) else { return }
    let roms: [LudeumROM]
    let settings: EmulatorSettings
    do {
        roms = try journal.roms(of: row.id)
        settings = try journal.emulatorSettings(row.id)
    } catch {
        refused("Couldn't read its ROMs and Emulator settings: \(error.localizedDescription)")
        return
    }
    let play = Play(
        platformId: row.platformId, platformName: row.platformName, roms: roms, settings: settings,
        busyROMs: Set(roms.map(\.id).filter { services.tasks.isActive(.rom($0)) }))
    startPlay(play, in: emulator, services: services, refused: refused, alert: alert)
}
