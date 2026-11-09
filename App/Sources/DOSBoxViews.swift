import AppKit
import LudeumCore
import SwiftUI

extension DOSBoxesOpen {
    /// The DOSBox Stagings open now, Ludeum's or another's, and the ROMs they're playing. DOS Games Play side by side, one
    /// copy to a ROM (ADR 0042).
    @MainActor static func now(ludeum: LudeumFolder) -> DOSBoxesOpen {
        // One that has just quit can be listed still, and has no command line left to read.
        let open = NSRunningApplication.runningApplications(withBundleIdentifier: Emulator.dosBoxStaging.bundleIdentifier)
            .filter { !$0.isTerminated }
        return DOSBoxesOpen(commandLines: open.map { ProcessArguments.of($0.processIdentifier) }, ludeum: ludeum)
    }
}

/// Next to Play for a DOS Game (ADR 0042): "DOSBox Staging · KEEN1.EXE", or "DOS prompt", opening the program it starts with
/// and its ROM's own DOSBox Staging settings.
struct DOSBoxSettingsButton: View {
    let services: Services
    /// The ROM Play opens, whose drive C the programs are on and whose settings file is edited.
    let rom: LudeumROM?
    let settings: EmulatorSettings
    let save: (EmulatorSettings) -> Void
    @State private var showing = false
    @State private var programs: [String] = []
    @State private var error: String?

    private var program: String? { settings.dosProgram }

    var body: some View {
        Button {
            showing = true
        } label: {
            Label(
                "\(Emulator.dosBoxStaging.name) · \(program.map { ($0 as NSString).lastPathComponent } ?? "DOS prompt")",
                systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.hover)
        .help("This Game's \(Emulator.dosBoxStaging.name) settings")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Emulator.dosBoxStaging.name) settings").font(.headline)
                    Text("For this Game, applied every time you Play it.").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Starts with", selection: Binding(get: { program }, set: { choose($0) })) {
                        Text("A DOS prompt").tag(String?.none)
                        // One chosen before and gone since stays, so the choice still says what Play does.
                        ForEach(programs + (program.map { programs.contains($0) ? [] : [$0] } ?? []), id: \.self) { path in
                            Text("C:\\\(path)").tag(String?.some(path))
                        }
                    }
                    Text(
                        "The program Play starts on drive C, quitting DOSBox Staging when it ends. Play's menu still offers a DOS "
                            + "prompt. A CD game's install shows here once it's installed. Programs in folders with long names aren't "
                            + "offered, as DOS knows them by other names."
                    )
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Button("Edit DOSBox Settings…") { editSettings() }.disabled(rom == nil)
                    Text(
                        "Opens this ROM's own settings file, laid over Ludeum's at every Play. Put in only what this game needs "
                            + "differently, such as its CPU cycles or sound card. It's kept in the Data folder."
                    )
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let error { ErrorText(error, font: .caption) }
            }
            .padding()
            .frame(width: 360)
            .task { await loadPrograms() }
        }
    }

    private func choose(_ program: String?) {
        var changed = settings
        changed.dosProgram = program
        save(changed)
    }

    /// The ROM's subfolder, where its drives are.
    private var subfolder: URL? {
        guard let rom, let folder = ROMLocator(romFolders: services.settings.romFolders).folder(of: rom) else { return nil }
        return folder.url.appending(path: rom.folderName, directoryHint: .isDirectory)
    }

    /// Off the main thread: a game is hundreds of files.
    private func loadPrograms() async {
        guard let rom, let subfolder else { return }
        let dosBox = DOSBoxStagingSettings(ludeum: services.settings.folder)
        let name = rom.folderName
        programs = await Task.detached(priority: .userInitiated) { dosBox.programs(ofROMIn: subfolder, romName: name) }.value
    }

    /// Opens the ROM's settings file in TextEdit, making it first, with a note of what goes in it, when there's none.
    private func editSettings() {
        error = nil
        guard let rom else { return }
        do {
            let file = try DOSBoxStagingSettings(ludeum: services.settings.folder).gameSettings(ofROM: rom.folderName)
            if let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
                NSWorkspace.shared.open([file], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(file)
            }
        } catch {
            self.error = "Couldn't make its settings file: \(error.localizedDescription)"
        }
    }
}

/// Game detail's Game save for a DOS Game (ADR 0042): for each of its ROMs, what its game has written over its drive C, a
/// CD game's install included. Read again when Game detail opens and whenever Ludeum becomes active, as a Play writes to it
/// with Ludeum in the background.
struct DOSGameSaveSection: View {
    let services: Services
    /// The ROMs Play can open that aren't missing.
    let roms: [LudeumROM]

    @State private var saves: [Saved] = []
    @State private var loaded = false
    @State private var deleting: Saved?
    @State private var error: String?

    private struct Saved: Identifiable {
        let rom: String
        let save: DOSGameSave
        var id: String { rom }
    }

    var body: some View {
        Section("Game save") {
            if loaded, saves.isEmpty {
                Text(
                    "Nothing saved yet. What the game writes, saves and settings, and a CD game's install, are kept here, in the "
                        + "Data folder, and its ROM is never written to."
                )
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(saves) { saved in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        let size = ByteCountFormatter.string(fromByteCount: saved.save.size, countStyle: .file)
                        Text(roms.count > 1 ? "\(saved.rom) · \(size)" : size)
                        Text("Written \(saved.save.written.formatted(date: .abbreviated, time: .shortened)) · What the game has written")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([saved.save.folder]) }
                        .labelStyle(.iconOnly).buttonStyle(.hover).help("Show the Game save in Finder")
                    Button("Delete…", systemImage: "trash") { deleting = saved }
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
                if let saved = deleting { delete(saved) }
            }
        } message: {
            Text(
                "Everything the game has written goes with it: its saves, its settings, and a CD game's install. The next Play starts afresh."
            )
        }
    }

    private func delete(_ saved: Saved) {
        error = nil
        if DOSBoxesOpen.now(ludeum: services.settings.folder).isPlaying(saved.rom) {
            error = "Quit the DOSBox Staging playing it first: it's writing to this Game save."
            return
        }
        do {
            try Trash.move(saved.save.folder)
            saves.removeAll { $0.id == saved.id }
        } catch {
            self.error = "Couldn't send it to the Trash: \(error.localizedDescription)"
        }
    }

    private func load() async {
        let ludeum = services.settings.folder
        let names = roms.map(\.folderName)
        saves = await Task.detached(priority: .utility) {
            names.compactMap { name in DOSGameSave.of(romName: name, ludeum: ludeum).map { Saved(rom: name, save: $0) } }
        }.value
        loaded = true
    }
}
