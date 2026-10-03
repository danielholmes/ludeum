import AppKit
import JournalCore
import SwiftUI

/// Settings' backup controls: where backups go (with a warning when it's the local fallback),
/// "Back up now" and "Restore from backup…".
struct BackupsSection: View {
    let journal: JournalStore?
    let backups: Backups
    let chooseFolder: () -> Void

    @State private var message: String?
    @State private var restoring = false

    var body: some View {
        Section {
            LabeledContent("Folder") {
                HStack {
                    Text(backups.folder.path(percentEncoded: false)).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Button("Choose…", action: chooseFolder)
                }
            }
            if backups.isUsingFallback {
                Label(
                    "That folder isn't there, so backups go to \(backups.fallback.path(percentEncoded: false)), which isn't synced anywhere.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }
            HStack {
                Button("Back up now", action: backUpNow)
                Button("Restore from backup…") { restoring = true }
                if let message { Text(message).foregroundStyle(.secondary) }
            }
            .disabled(journal == nil)
        } header: {
            Text("Backups")
        } footer: {
            Text(
                "Taken before every Import, Sync and deletion, and daily. Kept: all from the last 7 days, then one a day for 30 days, then one a month."
            )
            .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $restoring) {
            if let journal { RestoreSheet(journal: journal, backups: backups) }
        }
    }

    private func backUpNow() {
        guard let journal else { return }
        do {
            let backup = try backups.backUp(journal, operation: .manual)
            message = "Saved \(backup.url.lastPathComponent)"
        } catch {
            message = "Backup failed: \(error)"
        }
    }
}

/// Lists the backups. Restoring one backs up the current journal first, replaces it, and relaunches.
struct RestoreSheet: View {
    let journal: JournalStore
    let backups: Backups
    @Environment(\.dismiss) private var dismiss
    @State private var list: [Backup] = []
    @State private var selection: URL?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restore from backup").font(.headline)
            Text("The journal is backed up first, then replaced, and Games Journal relaunches. Nothing is written to OpenEmu.")
                .font(.callout).foregroundStyle(.secondary)
            List(list, id: \.url, selection: $selection) { backup in
                HStack {
                    Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                    Spacer()
                    Text(backup.operation.rawValue).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 240)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Restore", action: restore).keyboardShortcut(.defaultAction).disabled(selection == nil)
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear { list = (try? backups.all()) ?? [] }
    }

    private func restore() {
        guard let backup = list.first(where: { $0.url == selection }) else { return }
        do {
            try backups.restore(backup, into: journal)
            relaunch()
        } catch {
            self.error = "Restore failed: \(error)"
        }
    }

    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    self.error = "Restored, but couldn't relaunch (\(error.localizedDescription)). Quit and reopen Games Journal."
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
