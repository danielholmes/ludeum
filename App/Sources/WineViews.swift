import AppKit
import LudeumCore
import SwiftUI

/// The Plays going on in Wine (ADR 0040), by ROM. A Play in Wine isn't over when its game opens, as the other Emulators'
/// are: Ludeum makes the ROM's prefix, clones its game, starts it, and keeps its Game save once it has ended, which can be
/// hours later. Play's button says how far each has got, and what went wrong with the last one stays until the next.
/// They aren't Background tasks, which run one at a time: a game being played would hold up every Archive behind it.
@Observable @MainActor final class WinePlays {
    private(set) var phases: [Int64: WinePlay.Phase] = [:]
    private(set) var failures: [Int64: String] = [:]

    /// How far the ROM's Play has got, while it has one.
    func phase(of rom: Int64?) -> WinePlay.Phase? { rom.flatMap { phases[$0] } }

    /// Why the ROM's last Play stopped, if it did.
    func failure(of rom: Int64?) -> String? { rom.flatMap { failures[$0] } }

    /// Starts the ROM's Play, unless it has one. `failed` gets why it stopped, should it, as soon as it does; `changes`
    /// is told once its Game save is kept, so Game detail shows it.
    func start(_ play: WinePlay, rom: Int64, changes: LudeumChanges, failed: @escaping @MainActor (String) -> Void) {
        guard phases[rom] == nil else { return }
        failures[rom] = nil
        phases[rom] = .gettingReady
        Task {
            do {
                try await play.run { phase in
                    Task { @MainActor in if self.phases[rom] != nil { self.phases[rom] = phase } }
                }
            } catch {
                failures[rom] = error.localizedDescription
                failed(error.localizedDescription)
            }
            phases[rom] = nil
            changes.savesChanged()
        }
    }
}

/// Play's place while a ROM's Play in Wine is going on: how far it has got.
struct WinePlayProgress: View {
    let phase: WinePlay.Phase

    var body: some View {
        HStack(spacing: 6) {
            if phase != .playing { ProgressView().controlSize(.small) }
            Text(phase.title).foregroundStyle(.secondary)
        }
        .help(help)
    }

    private var help: String {
        switch phase {
        case .keepingLastSave: "Its last Play ended without Ludeum, so what the game wrote then is kept before it starts again"
        case .makingPrefix: "Wine is building the Windows this ROM runs in, which takes about twenty seconds the first time"
        case .gettingReady: "Cloning the ROM's game and laying its Game save over the clone"
        case .playing: "Once the game ends, what it wrote is kept as its Game save, in the Data folder"
        case .keepingSave: "The game has ended: what it wrote is being kept as its Game save, in the Data folder"
        }
    }
}

/// Game detail's Game save for a Windows Game (ADR 0040): what the game wrote, for each of its ROMs, kept in the Data
/// folder once the game and Wine have ended. Read again when Game detail opens, when a Play in Wine ends, and whenever
/// Ludeum becomes active.
struct WineGameSaveSection: View {
    let services: Services
    /// The ROMs Play can open that aren't missing.
    let roms: [LudeumROM]

    @State private var saves: [Save] = []
    @State private var loaded = false

    private struct Save: Identifiable {
        let rom: String
        let folder: URL
        let files: [String]
        let hasRegistry: Bool
        let written: Date
        var id: String { rom }
    }

    var body: some View {
        Section(saves.count > 1 ? "Game saves" : "Game save") {
            if loaded, saves.isEmpty {
                Text("No Game save yet. Once the game has been Played, what it wrote is kept here, in the Data folder.")
                    .foregroundStyle(.secondary)
            }
            ForEach(saves) { save in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(roms.count > 1 ? "\(save.rom) · \(summary(save))" : summary(save))
                        Text("Written \(save.written.formatted(date: .abbreviated, time: .shortened))").font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .help(save.files.prefix(20).joined(separator: "\n") + (save.files.count > 20 ? "\n…" : ""))
                    Spacer()
                    Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([save.folder]) }
                        .labelStyle(.iconOnly).buttonStyle(.hover).help("Show the Game save in Finder")
                }
            }
        }
        .task(id: Key(roms: roms.map(\.folderName), revision: services.changes.savesRevision)) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await load() }
        }
    }

    private struct Key: Equatable {
        let roms: [String]
        let revision: Int
    }

    /// "3 files and its registry keys".
    private func summary(_ save: Save) -> String {
        let files = save.files.isEmpty ? nil : "\(save.files.count) file\(save.files.count == 1 ? "" : "s")"
        return [files, save.hasRegistry ? "its registry keys" : nil].compactMap { $0 }.joined(separator: " and ")
    }

    private func load() async {
        let ludeum = services.settings.folder
        let names = roms.map(\.folderName)
        saves = await Task.detached(priority: .utility) {
            names.compactMap { name in
                let save = ludeum.wineSave(ofROM: name)
                return save.contents().map {
                    Save(rom: name, folder: save.folder, files: $0.files, hasRegistry: $0.hasRegistry, written: $0.written)
                }
            }
        }.value
        loaded = true
    }
}
