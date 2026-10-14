import AppKit
import LudeumCore
import SwiftUI
import UniformTypeIdentifiers

/// Game detail's Attachments: every file I keep about the Game, Manuals first, each opened in the app the system uses for
/// it. Files are added from a picker or dropped on the section.
struct AttachmentsSection: View {
    let services: Services
    let game: GameID

    @State private var attachments: [Attachment] = []
    @State private var adding: PendingAttachments?
    @State private var renaming: Attachment?
    @State private var newName = ""
    @State private var deleting: Attachment?
    @State private var locating: LocatedFile?
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Section("Attachments") {
            ForEach(attachments) { row($0) }
            HStack {
                Button("Add Manual…", systemImage: "book") { pick(manual: true) }
                    .buttonStyle(.hover).help("A manual, opened from Open Manual at the top")
                Button("Add Attachment…", systemImage: "paperclip") { pick(manual: false) }
                    .buttonStyle(.hover).help("Any file about this Game, such as a map or a guide. Or drop files here.")
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .disabled(working)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            adding = PendingAttachments(files: files, manual: false)
            return true
        }
        .task(id: TaskKey(game: game, revision: services.changes.revision)) { await load() }
        .sheet(item: $adding) { pending in
            AddAttachmentsSheet(pending: pending) { manual, moving in
                adding = nil
                run { try $0.add(pending.files, to: game, manual: manual, moving: moving) }
            }
        }
        .alert(
            "Rename Attachment", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
            presenting: renaming
        ) { attachment in
            TextField("Name", text: $newName)
            Button("Rename") { run { [newName] in try $0.rename(attachment.id, to: newName) } }
            Button("Cancel", role: .cancel) {}
        } message: { attachment in
            let ext = (attachment.fileName as NSString).pathExtension
            Text(ext.isEmpty ? "Its file is renamed too." : "Its file is renamed too, keeping .\(ext).")
        }
        .confirmationDialog(
            deleting.map { $0.missing ? "Delete \($0.fileName)?" : "Send \($0.fileName) to the Trash?" } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting
        ) { attachment in
            Button("Delete Attachment", role: .destructive) { run { try $0.delete(attachment.id) } }
        } message: { attachment in
            Text(attachment.missing ? "Its file is gone already; it leaves the journal." : "Its file goes to the Trash.")
        }
        .locateAttachment($locating) { located, moving in
            run { try $0.locate(located.attachment, file: located.file, moving: moving) }
        }
    }

    private func row(_ attachment: Attachment) -> some View {
        HStack {
            Image(systemName: attachment.isManual ? "book.closed" : "doc").foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Button(attachment.fileName) { NSWorkspace.shared.open(attachment.url) }
                    .buttonStyle(.link).disabled(attachment.missing).strikethrough(attachment.missing)
                    .help(attachment.missing ? "Its file isn't in its folder" : "Open it")
                let notes = [attachment.isManual ? "Manual" : nil, attachment.missing ? "missing" : nil].compactMap { $0 }
                if !notes.isEmpty { Text(notes.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary) }
            }
            Spacer()
            if attachment.missing {
                Button("Locate…") { locating = pickLocated(for: attachment) }
                    .help("Choose its file, wherever it is now, to put back")
            } else {
                Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([attachment.url]) }
                    .labelStyle(.iconOnly).buttonStyle(.hover).help("Show in Finder")
            }
            Menu {
                Button(attachment.isManual ? "Not a Manual" : "Mark as Manual") {
                    run { try $0.setManual(attachment.id, !attachment.isManual) }
                }
                Button("Rename…") {
                    newName = attachment.name
                    renaming = attachment
                }
                Divider()
                Button(attachment.missing ? "Delete…" : "Move to Trash…", role: .destructive) { deleting = attachment }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More")
        }
    }

    /// Moves its folder after the Game's name or Platform changed, looks for its files, then reads it all.
    private func load() async {
        guard let store = services.attachments else { return }
        do {
            let changed = try await offMain { [game] in
                let moved = try store.follow(game)
                let checked = try store.checkFiles(game)
                return moved || checked
            }
            attachments = try store.attachments(of: game)
            // The Review queue's badge counts missing ones.
            if changed { services.changes.changed() }
        } catch {
            self.error = "Couldn't read its Attachments: \(error.localizedDescription)"
        }
    }

    private func pick(manual: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose"
        panel.message = manual ? "Choose its manual: a PDF, or any other file." : "Choose the files to attach."
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        adding = PendingAttachments(files: panel.urls, manual: manual)
    }

    /// Off the main thread, as files are copied; then every screen reloads.
    private func run(_ change: @escaping @Sendable (Attachments) throws -> Void) {
        guard let store = services.attachments, !working else { return }
        working = true
        Task {
            defer { working = false }
            do {
                try await offMain { try change(store) }
                error = nil
            } catch {
                self.error = attachmentErrorText(error)
            }
            services.changes.changed()
        }
    }

    private struct TaskKey: Equatable {
        let game: GameID
        let revision: Int
    }
}

/// Open Manual, at the top of Game detail: the Game's one Manual, or a menu of them when it has several. Nothing when
/// it has none.
struct OpenManualButton: View {
    let services: Services
    let game: GameID
    @State private var manuals: [Attachment] = []

    var body: some View {
        Group {
            if manuals.count == 1, let manual = manuals.first {
                Button("Open Manual", systemImage: "book") { NSWorkspace.shared.open(manual.url) }
                    .disabled(manual.missing).help(manual.missing ? "Its file is missing" : manual.fileName)
            } else if manuals.count > 1 {
                Menu("Open Manual", systemImage: "book") {
                    ForEach(manuals) { manual in
                        Button(manual.fileName) { NSWorkspace.shared.open(manual.url) }.disabled(manual.missing)
                    }
                }
                .fixedSize()
            }
        }
        .task(id: [Int(game), services.changes.revision]) {
            manuals = (try? services.attachments?.manuals(of: game)) ?? []
        }
    }
}

/// Files picked or dropped, waiting to be added.
struct PendingAttachments: Identifiable {
    let id = UUID()
    let files: [URL]
    /// Whether they're Manuals: true from Add Manual.
    let manual: Bool
}

/// Confirms adding the files: as Manuals or not, and copied or moved.
struct AddAttachmentsSheet: View {
    let pending: PendingAttachments
    let add: (_ manual: Bool, _ moving: Bool) -> Void
    @State private var manual: Bool
    @State private var keepingOriginals = true
    @Environment(\.dismiss) private var dismiss

    init(pending: PendingAttachments, add: @escaping (_ manual: Bool, _ moving: Bool) -> Void) {
        self.pending = pending
        self.add = add
        _manual = State(initialValue: pending.manual)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pending.files.count == 1 ? "Add \(pending.files[0].lastPathComponent)" : "Add \(pending.files.count) files")
                .font(.headline)
            if pending.files.count > 1 {
                List(pending.files, id: \.self) { Text($0.lastPathComponent) }
                    .listStyle(.bordered(alternatesRowBackgrounds: true)).frame(height: 120)
            }
            Toggle(pending.files.count == 1 ? "It's a Manual" : "They're Manuals", isOn: $manual)
            Picker("Picked files", selection: $keepingOriginals) {
                Text("Copy them").tag(true)
                Text("Move them").tag(false)
            }
            .pickerStyle(.radioGroup)
            Text(keepingOriginals ? "They stay where they are." : "They go to the Trash once they're in.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") { add(manual, !keepingOriginals) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// A file picked to put back a missing Attachment's.
struct LocatedFile: Identifiable {
    let attachment: Int64
    let file: URL
    var id: URL { file }
}

/// Asks for a missing Attachment's file, wherever it is now. Nil when cancelled.
@MainActor func pickLocated(for attachment: Int64, named fileName: String) -> LocatedFile? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    panel.message = "Choose the file for \(fileName). It goes back under that name."
    guard panel.runModal() == .OK, let file = panel.url else { return nil }
    return LocatedFile(attachment: attachment, file: file)
}

@MainActor func pickLocated(for attachment: Attachment) -> LocatedFile? {
    pickLocated(for: attachment.id, named: attachment.fileName)
}

extension View {
    /// Asks whether a located file is copied or moved back, then `put`s it.
    func locateAttachment(_ located: Binding<LocatedFile?>, put: @escaping (LocatedFile, _ moving: Bool) -> Void) -> some View {
        confirmationDialog(
            "Put \(located.wrappedValue?.file.lastPathComponent ?? "it") back?",
            isPresented: Binding(get: { located.wrappedValue != nil }, set: { if !$0 { located.wrappedValue = nil } }),
            presenting: located.wrappedValue
        ) { file in
            Button("Copy It In") { put(file, false) }
            Button("Move It In") { put(file, true) }
        } message: { _ in
            Text("Moving sends the original to the Trash once it's in.")
        }
    }
}

func attachmentErrorText(_ error: Error) -> String {
    switch error {
    case AttachmentError.notAFile(let name): "\(name) is a folder. Only single files can be attached: zip it, or make it a PDF, first."
    case AttachmentError.alreadyInAttachments(let name): "\(name) is already in the Attachments folder."
    case AttachmentError.nameTaken: "Another Attachment, or another file in its folder, already has that name."
    case AttachmentError.nameRequired: "A name is required."
    case AttachmentError.notFound: "That Attachment is gone."
    default: journalErrorText(error)
    }
}
