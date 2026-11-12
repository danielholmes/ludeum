import AppKit
import LudeumCore
import SwiftUI

/// Game detail's Game saves for a Java phone Game (ADR 0044): what each of its jars' MIDlets has saved, KEmulator's record
/// stores in the Data folder, named from the jar's manifest. Read again when Game detail opens and whenever Ludeum becomes
/// active, as a Play writes them with Ludeum in the background.
struct MobileGameSavesSection: View {
    let services: Services
    /// The ROMs Play can open that aren't missing.
    let roms: [LudeumROM]

    @State private var saves: [MobileGameSave] = []
    @State private var loaded = false
    @State private var deleting: MobileGameSave?
    @State private var error: String?

    var body: some View {
        Section("Game saves") {
            if loaded, saves.isEmpty {
                Text("Nothing saved yet. What the game saves is kept here, in the Data folder, by the name its jar gives it.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(saves, id: \.folder) { save in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(save.midlet) · \(ByteCountFormatter.string(fromByteCount: save.size, countStyle: .file))")
                        Text("Written \(save.written.formatted(date: .abbreviated, time: .shortened))")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([save.folder]) }
                        .labelStyle(.iconOnly).buttonStyle(.hover).help("Show the Game save in Finder")
                    Button("Delete…", systemImage: "trash") { deleting = save }
                        .labelStyle(.iconOnly).buttonStyle(.hover).help("Send the Game save to the Trash")
                }
            }
            if let error { ErrorText(error) }
        }
        .task(id: roms.map(\.folderName)) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await load() }
        }
        .confirmationDialog(
            "Delete this Game save?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let save = deleting { delete(save) }
            }
        } message: {
            Text("Everything the game has saved goes with it. The next Play starts afresh.")
        }
    }

    private func delete(_ save: MobileGameSave) {
        error = nil
        if Emulator.kemulator.isRunning {
            error = "Quit KEmulator first: it may be writing to this Game save."
            return
        }
        do {
            try Trash.move(save.folder)
            saves.removeAll { $0.folder == save.folder }
        } catch {
            self.error = "Couldn't send it to the Trash: \(error.localizedDescription)"
        }
    }

    private func load() async {
        let ludeum = services.settings.folder
        let locator = ROMLocator(romFolders: services.settings.romFolders)
        let roms = roms
        saves = await Task.detached(priority: .utility) {
            var found: [MobileGameSave] = []
            for jar in roms.flatMap({ MobileGameSave.jars(of: $0, locator: locator) }) {
                // Two builds of one game with the same vendor and name share theirs.
                if let save = MobileGameSave.of(jar: jar, ludeum: ludeum), !found.contains(where: { $0.folder == save.folder }) {
                    found.append(save)
                }
            }
            return found
        }.value
        loaded = true
    }
}
