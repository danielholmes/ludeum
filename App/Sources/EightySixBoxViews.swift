import AppKit
import LudeumCore
import SwiftUI
import UniformTypeIdentifiers

/// Asks for a prepared Windows base's archive. Nil when cancelled.
@MainActor private func pickWindowsBase() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [UTType(filenameExtension: "7z") ?? .data]
    panel.prompt = "Choose"
    panel.message = "Choose a prepared Windows base's .7z. Ludeum keeps its own read-only copy in the Data folder."
    return panel.runModal() == .OK ? panel.url : nil
}

/// The Windows base under 86Box's row in the Emulators sheet (ADR 0041): whether there is one, where it is, and choosing one.
/// It can't be changed under a game disk standing on it.
struct WindowsBaseRow: View {
    let services: Services
    /// Why a choice was refused before it started.
    @Binding var error: String?

    /// Only looks: `choose()` makes the one that reads an archive.
    private var base: WindowsBase { WindowsBase(ludeum: services.settings.folder, sevenZip: nil) }
    private var choosing: BackgroundTasks.Item? { services.tasks.active(.windowsBase) }

    var body: some View {
        let hasGameDisks = !base.gameDisks.isEmpty
        HStack(spacing: 8) {
            if let choosing {
                Label(
                    choosing.progress.map { "Bringing in the Windows base \(Int($0 * 100))%" } ?? "Bringing in the Windows base…",
                    systemImage: "arrow.down.circle"
                )
                .foregroundStyle(.secondary)
            } else if base.isChosen {
                Label("Windows base: \(base.file.lastPathComponent)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([base.file]) }
                    .labelStyle(.iconOnly).buttonStyle(.hover).help("Show the Windows base in Finder")
            } else {
                Label("No Windows base: Windows Games can't Play yet", systemImage: "minus.circle").foregroundStyle(.secondary)
            }
            Spacer()
            Button(base.isChosen ? "Choose Another Base…" : "Choose Base…") { choose() }
                .disabled(choosing != nil || hasGameDisks)
                .help(
                    hasGameDisks
                        ? "Game disks stand on this base, and would no longer read true over another"
                        : "Choose a prepared Windows base's .7z")
        }
        .font(.callout)
    }

    private func choose() {
        error = nil
        if Emulator.eightySixBox.isRunning {
            error = "Quit 86Box first: a machine may be using the Windows base."
            return
        }
        guard let archive = pickWindowsBase() else { return }
        let folder = services.settings.folder
        services.tasks.enqueue("Bringing in the Windows base", subject: .windowsBase) { progress in
            // It may have opened while this waited its turn.
            if await Emulator.eightySixBox.isRunning { throw EmulatorRunning(emulator: .eightySixBox) }
            try await WindowsBase(ludeum: folder).choose(archive, progress: progress)
        } ended: {
        }
    }
}

/// Game detail's game disk for a Windows Game (ADR 0041): for each of its ROMs, the installed game and everything it has
/// written, which is its Game save. Read again when Game detail opens and whenever Ludeum becomes active, as a Play writes
/// to it with Ludeum in the background.
struct GameDiskSection: View {
    let services: Services
    /// The ROMs Play can open that aren't missing.
    let roms: [LudeumROM]

    @State private var disks: [Disk] = []
    @State private var loaded = false
    @State private var deleting: Disk?
    @State private var error: String?

    private struct Disk: Identifiable {
        let rom: String
        let file: URL
        let size: Int64
        let written: Date
        var id: String { rom }
    }

    var body: some View {
        Section(disks.count > 1 ? "Game disks" : "Game disk") {
            if loaded, disks.isEmpty {
                Text(
                    "No game disk yet. The first Play makes it and boots Windows with the disc in the drive: install the game there, "
                        + "and it and its Game saves are kept here, in the Data folder."
                )
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(disks) { disk in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        let size = ByteCountFormatter.string(fromByteCount: disk.size, countStyle: .file)
                        Text(roms.count > 1 ? "\(disk.rom) · \(size)" : size)
                        Text(
                            "Written \(disk.written.formatted(date: .abbreviated, time: .shortened)) · The installed game and its Game saves"
                        )
                        .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([disk.file]) }
                        .labelStyle(.iconOnly).buttonStyle(.hover).help("Show the game disk in Finder")
                    Button("Delete…", systemImage: "trash") { deleting = disk }
                        .labelStyle(.iconOnly).buttonStyle(.hover).help("Send the game disk to the Trash")
                }
            }
            if let error { ErrorText(error) }
        }
        .task(id: roms.map(\.folderName)) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await load() }
        }
        .confirmationDialog(
            "Delete this game disk?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let disk = deleting { delete(disk) }
            }
        } message: {
            Text("It holds the installed game and all its Game saves, and both go with it. The next Play starts again with a new install.")
        }
    }

    private func delete(_ disk: Disk) {
        error = nil
        if Emulator.eightySixBox.isRunning {
            error = "Quit 86Box first: it may be using this game disk."
            return
        }
        do {
            try Trash.move(disk.file)
            disks.removeAll { $0.id == disk.id }
        } catch {
            self.error = "Couldn't send it to the Trash: \(error.localizedDescription)"
        }
    }

    private func load() async {
        let ludeum = services.settings.folder
        let names = roms.map(\.folderName)
        disks = await Task.detached(priority: .utility) {
            names.compactMap { name in
                let file = ludeum.gameDisk(ofROM: name)
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                guard let values, let written = values.contentModificationDate else { return nil }
                return Disk(rom: name, file: file, size: Int64(values.fileSize ?? 0), written: written)
            }
        }.value
        loaded = true
    }
}
