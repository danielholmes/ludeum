import AppKit
import LudeumCore
import SwiftUI

/// Game detail's Save states and Game saves for a PlayStation 2 Game (ADR 0032): PCSX2's states for the ROMs' Serials,
/// by Disc, then Resume, then slot, each with its screenshot and when it was saved, to Play from or delete; and its Card
/// saves on PCSX2's folder memory cards, the subfolders whose names carry one of its Serials (or one PCSX2's game
/// database says shares its saves), each with its title and when it was last written. They're made in PCSX2, which
/// keeps them in the Data folder; this is what's there, read again when Game detail opens and whenever Ludeum becomes
/// active, back from PCSX2.
struct PCSX2SavesSection: View {
    let services: Services
    /// The Serials of the ROMs Play opens, in Disc order.
    let serials: [String]
    /// Why Play can't open it, if it can't.
    let refusal: String?
    let play: (SaveState) -> Void

    @State private var states: [SaveState] = []
    @State private var cardSaves: [PS2CardSave] = []
    @State private var screenshots: [String: NSImage] = [:]
    @State private var loaded = false
    @State private var deleting: SaveState?
    @State private var error: String?

    var body: some View {
        Group {
            Section("Save states") {
                if loaded, states.isEmpty {
                    Text("No save states. Save one in PCSX2 and it shows here, kept in the Data folder.").foregroundStyle(.secondary)
                }
                ForEach(states) { row($0) }
                if let error { ErrorText(error) }
            }
            Section(cardSaves.count == 1 ? "Game save" : "Game saves") {
                if loaded, cardSaves.isEmpty {
                    Text("No Game saves yet. Once the game saves to a memory card, its save shows here, kept in the Data folder.")
                        .foregroundStyle(.secondary)
                }
                ForEach(cardSaves) { save in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(save.title ?? save.name)
                            Text(
                                "\(save.title == nil ? "" : "\(save.name) · ")\(save.card) · Written "
                                    + save.saved.formatted(date: .abbreviated, time: .shortened)
                            )
                            .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([save.folder]) }
                            .labelStyle(.iconOnly).buttonStyle(.hover).help("Show the save's folder in Finder")
                    }
                }
            }
        }
        .task(id: serials) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await load() }
        }
        .confirmationDialog(
            deleting.map { "Delete \($0.title)?" } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { state in
            Button("Delete Save State", role: .destructive) { delete(state) }
        } message: { _ in
            Text("It goes to the Trash.")
        }
    }

    private var saveStates: PCSX2SaveStates { PCSX2SaveStates(ludeum: services.settings.folder) }

    private func row(_ state: SaveState) -> some View {
        HStack(spacing: 12) {
            // PCSX2 keeps the frame scaled to fit 640 × 480; a PlayStation 2 picture is 4:3 on screen.
            Group {
                if let image = screenshots[imageKey(state)] {
                    Image(nsImage: image).resizable().interpolation(.medium)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 96, height: 72).clipShape(.rect(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(serials.count > 1 ? "\(state.title) · Disc \((serials.firstIndex(of: state.serial) ?? 0) + 1)" : state.title)
                Text(state.saved.formatted(date: .abbreviated, time: .shortened)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Play", systemImage: "play.fill") { play(state) }
                .labelStyle(.iconOnly).buttonStyle(.hover).disabled(refusal != nil)
                .help(refusal ?? "Play from this state in PCSX2")
            Menu {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([state.file]) }
                Divider()
                Button("Delete…", role: .destructive) { deleting = state }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More")
        }
    }

    /// A screenshot is read again when its state's saved again.
    private func imageKey(_ state: SaveState) -> String { "\(state.file.path(percentEncoded: false))@\(state.saved.timeIntervalSince1970)" }

    private func load() async {
        let saveStates = saveStates
        let cards = PCSX2MemoryCards(ludeum: services.settings.folder)
        let serials = serials
        let found = await Task.detached(priority: .utility) { (saveStates.states(of: serials), cards.saves(of: serials)) }.value
        states = found.0
        cardSaves = found.1
        loaded = true
        for state in states where screenshots[imageKey(state)] == nil {
            let file = state.file
            if let png = await Task.detached(priority: .utility, operation: { PCSX2SaveStates.screenshotPNG(of: file) }).value,
                let image = NSImage(data: png)
            {
                screenshots[imageKey(state)] = image
            }
            if Task.isCancelled { return }
        }
    }

    private func delete(_ state: SaveState) {
        do {
            try saveStates.delete(state)
            error = nil
            // Play's Resume follows a deleted Resume state (ADR 0034).
            services.changes.savesChanged()
        } catch {
            self.error = error.localizedDescription
        }
        Task { await load() }
    }
}
