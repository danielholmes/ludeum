import AppKit
import LudeumCore
import SwiftUI

/// Game detail's Save states and Game saves for a Saturn Game (ADR 0036), by its ROMs' Serials. Save states are Ymir's slots,
/// each with when it was saved and the keys that load it in Ymir, as nothing can start Ymir from one; they can be deleted
/// here. Game saves are what's in the Game's backup RAM. They're made in Ymir, which keeps them in the Data folder; this is
/// what's there, read again when Game detail opens and whenever Ludeum becomes active, back from Ymir.
struct YmirSavesSection: View {
    let services: Services
    /// The Serials of the ROMs Play opens, in Disc order.
    let serials: [String]

    @State private var states: [SaveState] = []
    @State private var images: [SaturnBackupImage] = []
    @State private var loaded = false
    @State private var deleting: SaveState?
    @State private var error: String?

    private var saves: YmirSaves { YmirSaves(ludeum: services.settings.folder) }

    var body: some View {
        Group {
            Section("Save states") {
                if loaded, states.isEmpty {
                    Text("No save states. Save one in Ymir and it shows here, kept in the Data folder.").foregroundStyle(.secondary)
                }
                ForEach(states) { row($0) }
                if let error { ErrorText(error) }
            }
            Section(images.flatMap { $0.saves ?? [] }.count == 1 ? "Game save" : "Game saves") {
                if loaded, images.isEmpty {
                    Text("No Game saves yet. Once the game saves, its backup RAM shows here, kept in the Data folder.")
                        .foregroundStyle(.secondary)
                }
                ForEach(images) { image in
                    ForEach(image.saves ?? []) { save in
                        row(
                            save.comment.isEmpty ? save.name : "\(save.comment) · \(save.name)",
                            "Written \(save.written.formatted(date: .abbreviated, time: .shortened)) · "
                                + save.size.formatted(.byteCount(style: .file)),
                            image)
                    }
                    if image.saves == nil {
                        row(
                            image.fileName, "Couldn't read it. Written \(image.saved.formatted(date: .abbreviated, time: .shortened))",
                            image)
                    } else if image.saves?.isEmpty == true {
                        row("Nothing saved yet", "Its backup RAM is empty", image)
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
            Text("It goes to the Trash, with the state it replaced.")
        }
    }

    private func row(_ state: SaveState) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(serials.count > 1 ? "\(state.title) · Disc \((serials.firstIndex(of: state.serial) ?? 0) + 1)" : state.title)
                Text(state.saved.formatted(date: .abbreviated, time: .shortened)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if case .numbered(let slot) = state.slot {
                Text(YmirSaves.loadKey(slot: slot)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    .help("Press \(YmirSaves.loadKey(slot: slot)) in Ymir, during a Play of this Game, to load it")
            }
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

    private func row(_ title: String, _ detail: String, _ image: SaturnBackupImage) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([image.file]) }
                .labelStyle(.iconOnly).buttonStyle(.hover).help("Show the Game's backup RAM in Finder")
        }
    }

    private func load() async {
        let saves = saves
        let serials = serials
        let found = await Task.detached(priority: .utility) { (saves.states(of: serials), saves.backupImages(of: serials)) }.value
        states = found.0
        images = found.1
        loaded = true
    }

    private func delete(_ state: SaveState) {
        do {
            try saves.delete(state)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        Task { await load() }
    }
}
