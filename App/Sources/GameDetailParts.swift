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

    /// Between the label and the pills, and between the pills.
    private static let labelGap: CGFloat = 6
    private static let spacing: CGFloat = 4

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.labelGap) {
            Text(title).font(FactStyle.label).foregroundStyle(.secondary).frame(width: FactStyle.labelWidth, alignment: .leading)
            FlowLayout(spacing: Self.spacing) {
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

extension PillRow {
    /// How many of `items`' plain pills fit on one line of a row `rowWidth` wide, leaving room for "+N more" after them
    /// when not all do.
    static func fittingOneLine(_ items: [String], rowWidth: CGFloat) -> Int {
        let width = rowWidth - FactStyle.labelWidth - labelGap
        let widths = items.map(pillWidth)
        if widths.reduce(0, +) + spacing * CGFloat(widths.count - 1) <= width { return items.count }
        var x: CGFloat = 0
        var count = 0
        for w in widths {
            let more = pillWidth("+\(items.count - count - 1) more")
            guard x + w + spacing + more <= width else { break }
            x += w + spacing
            count += 1
        }
        return count
    }
}

private let pillPadding: CGFloat = 8

private func pill(_ text: String, systemImage: String?) -> some View {
    HStack(spacing: 3) {
        Text(text)
        if let systemImage { Image(systemName: systemImage).imageScale(.small).foregroundStyle(.secondary) }
    }
    .font(FactStyle.value).padding(.horizontal, pillPadding).padding(.vertical, 2).background(.quaternary, in: .capsule)
}

/// A plain pill's width: its text in FactStyle.value (the body font, 13 points) and its padding.
private func pillWidth(_ text: String) -> CGFloat {
    let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    return (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up) + 2 * pillPadding
}

/// A Screenshot from either source: IGDB's by its image id, LaunchBox's by its file name there.
enum ShownScreenshot: Hashable {
    case igdb(imageID: String)
    case launchBox(file: String)
}

struct Screenshot: Identifiable {
    let id: ShownScreenshot
}

/// Downloads Screenshots from wherever they're from: IGDB's through `igdb`, LaunchBox's through `covers`.
struct ScreenshotLoader {
    var igdb: IGDBClient?
    var covers: Covers?

    /// The file for a tile, or with `original`, the whole image: IGDB has both; LaunchBox has one, used for both. Nil
    /// when it can't be downloaded.
    func file(_ screenshot: ShownScreenshot, original: Bool) async -> URL? {
        switch screenshot {
        case .igdb(let imageID): try? await igdb?.screenshot(imageID: imageID, original: original)
        case .launchBox(let file): (try? await covers?.launchBoxScreenshot(file)) ?? nil
        }
    }
}

/// LaunchBox's Screenshots for the Game (`Covers.launchBoxScreenshots(for:)`), title screens first, below IGDB's and
/// shown as they are: nothing while they're looked for, or when LaunchBox has none.
struct LaunchBoxScreenshotsSection: View {
    let services: Services
    let game: GameID
    @State private var screenshots: [String] = []
    @State private var failed = false

    var body: some View {
        Group {
            let title = "LaunchBox Screenshots"
            if !screenshots.isEmpty {
                ScreenshotsSection(
                    loader: ScreenshotLoader(covers: services.covers), screenshots: screenshots.map { .launchBox(file: $0) }, title: title)
            } else if failed {
                Section(title) { Text("Couldn't load").foregroundStyle(.red) }
            }
        }
        // Again when the Game's Covers change: its names or IGDB link, which the Screenshots are found by.
        .task(id: "\(game) \(services.changes.coverRevision)") {
            failed = false
            do {
                screenshots = try await services.covers?.launchBoxScreenshots(for: game) ?? []
            } catch {
                screenshots = []
                failed = true
            }
        }
    }
}

/// A screenshot filling its frame, cropped to it, downloaded on first view; a grey box until then.
struct ScreenshotImage: View {
    let loader: ScreenshotLoader
    let screenshot: ShownScreenshot
    @State private var image: NSImage?

    var body: some View {
        // The image is an overlay, so its pixel size never pushes the layout wider than offered.
        Rectangle().fill(.quaternary)
            .overlay {
                if let image { Image(nsImage: image).resizable().interpolation(.high).scaledToFill() }
            }
            .clipped()
            .task(id: screenshot) {
                if let file = await loader.file(screenshot, original: false) { image = NSImage(contentsOf: file) }
            }
    }
}

/// A screenshot's original, whole: as large as its frame allows without going over its own size in pixels, and never
/// cropped. One under 200 pixels either way has its own size scaled up by a whole amount (`screenshotScale`). A
/// spinner until it's downloaded.
struct WholeScreenshot: View {
    let loader: ScreenshotLoader
    let screenshot: ShownScreenshot
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                let pixels = Self.pixelSize(of: image)
                let scale = CGFloat(screenshotScale(pixelWidth: Int(pixels.width), pixelHeight: Int(pixels.height)))
                Image(nsImage: image).resizable()
                    // Scaled up, each pixel stays a sharp square of them; shrunk to fit, it's smoothed.
                    .interpolation(scale > 1 ? .none : .high)
                    .scaledToFit()
                    .frame(maxWidth: pixels.width * scale, maxHeight: pixels.height * scale)
            } else if failed {
                Text("Couldn't download it.").foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: screenshot) {
            if let file = await loader.file(screenshot, original: true), let image = NSImage(contentsOf: file) {
                self.image = image
            } else {
                failed = true
            }
        }
    }

    /// Its size in pixels, whatever resolution the file claims (which `NSImage.size` goes by).
    private static func pixelSize(of image: NSImage) -> CGSize {
        guard let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return image.size }
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
}

/// A Game's Highlight note: yellow, under its name, so it's the first thing I read.
struct HighlightNote: View {
    let text: String

    var body: some View {
        Label {
            Text(text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "highlighter").foregroundStyle(.yellow)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.yellow.opacity(0.15), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.yellow.opacity(0.5)))
    }
}

/// The Game's rarely-changed details: name override, Highlight note, Cover upload, IGDB link, and deleting it.
struct EditGameSheet: View {
    let services: Services
    let game: Game
    let canLink: Bool
    let link: () -> Void
    let delete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var nameOverride = ""
    @State private var highlightNote = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("Name override", text: $nameOverride, prompt: Text("Use IGDB's name"))
                TextField("Highlight note", text: $highlightNote, prompt: Text("Shown at the top of its page"), axis: .vertical)
                    .lineLimit(3...8)
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
        .onAppear {
            nameOverride = (try? services.journal?.nameOverride(game.id)) ?? nil ?? ""
            highlightNote = game.highlightNote ?? ""
        }
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
                // Its Box art is found by its name.
                services.changes.coverChanged()
            }
            if highlightNote.trimmed != (game.highlightNote ?? "") {
                try services.journal?.setHighlightNote(game.id, highlightNote)
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
/// check's title and message. `saveState` starts DuckStation from that state.
@MainActor func startPlay(
    _ play: Play, in emulator: Emulator, services: Services, saveState: URL? = nil, refused: @escaping @MainActor (String) -> Void,
    alert: (_ title: String, _ message: String) -> Void
) {
    let version: Play.VersionStatus =
        if let tooOld = services.versions.refusalMessage(emulator) {
            .tooOld(tooOld)
        } else if let warning = services.versions.warningOnce(emulator) {
            .warn(warning)
        } else {
            .ok
        }
    let locator = ROMLocator(romFolders: services.settings.romFolders)
    if services.versions.isInstalling(emulator, tasks: services.tasks) {
        refused(Play.Refusal.installing(emulator).message)
        return
    }
    switch play.prepare(
        locator: locator, version: version, app: NSWorkspace.shared.urlForApplication(withBundleIdentifier:), saveState: saveState,
        duckStation: DuckStationSettings(ludeum: services.settings.folder), running: \.isRunning)
    {
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
        roms = try journal.romsToPlay(of: row.id)
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

/// Under an Expansion's name: "Expansion of" its Base game, a link when it's my Game on the same Platform,
/// or just "Expansion" when IGDB doesn't say what it expands.
struct ExpansionOfLine: View {
    let line: BaseGameLine
    let open: (GameID) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(line.name == nil ? "Expansion" : "Expansion of").foregroundStyle(.secondary)
            if let name = line.name {
                if let game = line.game {
                    Button(name) { open(game) }.buttonStyle(.link).help("Open the Base game")
                } else {
                    Text(name).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Under a Base game's name: its Expansions on the same Platform in the journal, each a link.
struct ExpansionsLine: View {
    let games: [Game]
    let open: (GameID) -> Void

    var body: some View {
        FlowLayout(spacing: 4) {
            Text("Expansions:").foregroundStyle(.secondary)
            ForEach(games, id: \.id) { game in
                Button(game.name) { open(game.id) }.buttonStyle(.link).help("Open this Expansion")
            }
        }
    }
}
