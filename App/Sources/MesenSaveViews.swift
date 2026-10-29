import AppKit
import LudeumCore
import SwiftUI

/// Game detail's Save states and Game saves for a MesenCE Game (ADR 0027): each present ROM's, found in its Platform's
/// folders by the name MesenCE keeps them by (the ROM file's, or the one inside its `.7z`). Save states are Resume (the
/// automatic one) then by slot, each with its screenshot and when it was saved, to Play from or delete; Game saves are
/// the files the game wrote, with when MesenCE last wrote each. They're made in MesenCE; this is what's there, read
/// again when Game detail opens and whenever Ludeum becomes active, back from MesenCE.
struct MesenSavesSection: View {
    let services: Services
    let platformId: Int64
    /// The present ROMs Play opens.
    let roms: [LudeumROM]
    /// The one of them Play opens, the only one whose states it can start from.
    let plays: LudeumROM?
    /// Why Play can't open it, if it can't.
    let refusal: String?
    let play: (SaveState) -> Void

    /// Each ROM's name in MesenCE, its states and its Game saves.
    private struct ROMSaves: Identifiable {
        let rom: LudeumROM
        let name: String
        let states: [SaveState]
        let gameSaves: [GameSaveFile]
        var id: Int64 { rom.id }
    }

    @State private var saves: [ROMSaves] = []
    @State private var loaded = false
    @State private var screenshots: [String: NSImage] = [:]
    @State private var deleting: SaveState?
    @State private var error: String?

    var body: some View {
        Group {
            Section("Save states") {
                if loaded, saves.allSatisfy(\.states.isEmpty) {
                    Text("No save states. Save one in MesenCE and it shows here, kept in the Data folder.").foregroundStyle(.secondary)
                }
                ForEach(saves) { rom in
                    ForEach(rom.states) { row($0, of: rom) }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            Section(saves.flatMap(\.gameSaves).count == 1 ? "Game save" : "Game saves") {
                if loaded, saves.allSatisfy(\.gameSaves.isEmpty) {
                    Text("No Game saves yet. Once the game saves and stops, MesenCE's file shows here, kept in the Data folder.")
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

    private var folders: MesenSaveStates? { MesenSaveStates(ludeum: services.settings.folder, platformId: platformId) }

    private func row(_ state: SaveState, of rom: ROMSaves) -> some View {
        HStack(spacing: 12) {
            Group {
                if let image = screenshots[imageKey(state)] {
                    Image(nsImage: image).resizable().interpolation(.medium).aspectRatio(contentMode: .fit)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 96, height: 72).clipShape(.rect(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(saves.count > 1 ? "\(state.title) · \(rom.rom.name)" : state.title)
                Text(state.saved.formatted(date: .abbreviated, time: .shortened)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            let why = refusal ?? (rom.rom.id == plays?.id ? nil : "Play opens \(plays?.name ?? "another ROM"), not this one")
            Button("Play", systemImage: "play.fill") { play(state) }
                .labelStyle(.iconOnly).buttonStyle(.hover).disabled(why != nil)
                .help(why ?? "Play from this state in MesenCE")
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
        guard let folders else { return }
        let locator = ROMLocator(romFolders: services.settings.romFolders)
        let platformId = platformId
        let roms = roms
        saves = await Task.detached(priority: .utility) {
            var saves: [ROMSaves] = []
            for rom in roms where !rom.missing && !rom.archived {
                guard let file = (try? locator.file(of: rom, ready: true)) ?? nil,
                    let name = await MesenROMName.of(file, platformId: platformId)?.name
                else { continue }
                saves.append(ROMSaves(rom: rom, name: name, states: folders.states(of: name), gameSaves: folders.gameSaves(of: name)))
            }
            return saves
        }.value
        loaded = true
        for state in saves.flatMap(\.states) where screenshots[imageKey(state)] == nil {
            let file = state.file
            if let shot = await Task.detached(priority: .utility, operation: { MesenScreenshot.of(file) }).value {
                screenshots[imageKey(state)] = shot.image
            }
            if Task.isCancelled { return }
        }
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
