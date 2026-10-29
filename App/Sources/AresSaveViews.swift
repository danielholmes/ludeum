import AppKit
import LudeumCore
import SwiftUI

/// Game detail's Save states and Game saves for an ares Game (ADR 0028): each present ROM's, found in its system's
/// folder by the name ares keeps them by (the ROM file's). Save states are its slots, each with when it was saved, to
/// Play from or delete; ares keeps no screenshot in one. Game saves are the files the game wrote, with when ares last
/// wrote each, which it does every 30 seconds of play. They're made in ares; this is what's there, read again when Game
/// detail opens and whenever Ludeum becomes active, back from ares.
struct AresSavesSection: View {
    let services: Services
    let platformId: Int64
    /// The present ROMs Play opens.
    let roms: [LudeumROM]
    /// The one of them Play opens, the only one whose states it can start from.
    let plays: LudeumROM?
    /// Why Play can't open it, if it can't.
    let refusal: String?
    let play: (SaveState) -> Void

    /// Each ROM, its states and its Game saves.
    private struct ROMSaves: Identifiable {
        let rom: LudeumROM
        let states: [SaveState]
        let gameSaves: [GameSaveFile]
        var id: Int64 { rom.id }
    }

    @State private var saves: [ROMSaves] = []
    @State private var loaded = false
    @State private var deleting: SaveState?
    @State private var error: String?

    var body: some View {
        Group {
            Section("Save states") {
                if loaded, saves.allSatisfy(\.states.isEmpty) {
                    Text("No save states. Save one in ares and it shows here, kept in the Data folder.").foregroundStyle(.secondary)
                }
                ForEach(saves) { rom in
                    ForEach(rom.states) { row($0, of: rom) }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            Section(saves.flatMap(\.gameSaves).count == 1 ? "Game save" : "Game saves") {
                if loaded, saves.allSatisfy(\.gameSaves.isEmpty) {
                    Text("No Game saves yet. Once the game saves, ares's file shows here, kept in the Data folder.")
                        .foregroundStyle(.secondary)
                }
                ForEach(saves) { rom in
                    ForEach(rom.gameSaves) { gameSave in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(gameSave.fileName)
                                Text("Written \(gameSave.saved.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Show in Finder", systemImage: "folder") {
                                NSWorkspace.shared.activateFileViewerSelecting([gameSave.file])
                            }
                            .labelStyle(.iconOnly).buttonStyle(.hover).help("Show the Game save in Finder")
                        }
                    }
                }
            }
        }
        .task(id: roms.map(\.id)) { await load() }
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

    private var folders: AresSaves? { AresSaves(ludeum: services.settings.folder, platformId: platformId) }

    private func row(_ state: SaveState, of rom: ROMSaves) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(saves.count > 1 ? "\(state.title) · \(rom.rom.name)" : state.title)
                Text(state.saved.formatted(date: .abbreviated, time: .shortened)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            let why = refusal ?? (rom.rom.id == plays?.id ? nil : "Play opens \(plays?.name ?? "another ROM"), not this one")
            Button("Play", systemImage: "play.fill") { play(state) }
                .labelStyle(.iconOnly).buttonStyle(.hover).disabled(why != nil)
                .help(why ?? "Play from this state in ares")
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

    private func load() async {
        guard let folders else { return }
        let locator = ROMLocator(romFolders: services.settings.romFolders)
        let roms = roms
        saves = await Task.detached(priority: .utility) {
            roms.filter { !$0.missing && !$0.archived }.compactMap { rom in
                guard let file = (try? locator.file(of: rom, ready: true)) ?? nil else { return nil }
                let name = file.deletingPathExtension().lastPathComponent
                return ROMSaves(rom: rom, states: folders.states(of: name), gameSaves: folders.gameSaves(of: name))
            }
        }.value
        loaded = true
    }

    private func delete(_ state: SaveState) {
        do {
            try folders?.delete(state)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        Task { await load() }
    }
}
