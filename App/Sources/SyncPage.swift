import AppKit
import JournalCore
import SwiftUI

/// The Sync's state: the preview, my Delete ticks, and the result.
@Observable @MainActor final class SyncModel {
    private(set) var preview: SyncPreview?
    private(set) var result: SyncResult?
    private(set) var syncing = false
    private(set) var loading = false
    var deleting: Set<Int64> = []
    var error: String?
    private let services: Services
    private let importModel: ImportModel

    init(services: Services, importModel: ImportModel) {
        self.services = services
        self.importModel = importModel
    }

    /// Sync isn't available while an Import draft exists or an Import is running.
    var blockedByImport: String? {
        switch importModel.state {
        case .idle, .draft: "Commit the first Import before syncing."
        case .running: "The first Import is running. Sync once it's committed."
        case .committed: ImportModel.isRunning ? "An Import is running. Sync once it's done." : nil
        }
    }

    private var sync: OpenEmuSync? {
        guard let journal = services.journal else { return nil }
        // OpenEmu's backup goes where the journal's backups currently go.
        let backups = services.settings.backups()
        return OpenEmuSync(
            journal: journal, covers: services.covers, backupFolder: backups.isUsingFallback ? backups.fallback : backups.folder,
            isOpenEmuRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: "org.openemu.OpenEmu").isEmpty })
    }

    func refresh() {
        guard blockedByImport == nil, let sync else { return }
        loading = true
        let library = services.settings.openEmuLibrary
        Task {
            do {
                preview = try await sync.preview(library: library)
                deleting.formIntersection(Set(preview?.otherCollections.map(\.pk) ?? []))
                error = nil
            } catch {
                self.error = "Couldn't read OpenEmu's library: \(error.localizedDescription)"
            }
            loading = false
        }
    }

    func run() {
        guard blockedByImport == nil, !syncing, let sync else { return }
        syncing = true
        result = nil
        ImportModel.isRunning = true  // Import and Sync are exclusive
        let library = services.settings.openEmuLibrary
        let deleting = deleting
        Task {
            do {
                result = try await sync.sync(library: library, deleting: deleting)
                self.deleting = []
                error = nil
            } catch SyncError.guardsFailed(let failed) {
                error = "Sync didn't run: \(failed.map(guardTitle).joined(separator: ", "))."
            } catch SyncError.integrityFailedAfterWrite(let backup) {
                error =
                    "OpenEmu's library failed its integrity check after the Sync. Restore its backup, \(backup), before opening OpenEmu."
            } catch {
                self.error = "Sync failed: \(error.localizedDescription). Nothing was written if the error came before the write."
            }
            syncing = false
            ImportModel.isRunning = false
            refresh()
        }
    }
}

func guardTitle(_ g: SyncGuard) -> String {
    switch g {
    case .openEmuRunning: "OpenEmu is open"
    case .conflictedCopy: "a conflicted copy is next to the library"
    case .differentLibrary: "it's not the library the journal imported"
    case .integrityFailed: "the library failed its integrity check"
    }
}

/// The Sync page: guards on the left, then banners, the preview, the other collections with a
/// Delete tick each, and the Sync button.
struct SyncPage: View {
    @Bindable var model: SyncModel

    var body: some View {
        HStack(spacing: 0) {
            guards.frame(width: 220).padding().background(.background.secondary)
            Divider()
            ScrollView { main.padding().frame(maxWidth: .infinity, alignment: .leading) }
        }
        .navigationTitle("Sync")
        .task { model.refresh() }
    }

    private var guards: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Before syncing").font(.headline)
            ForEach(SyncGuard.allCases, id: \.self) { g in
                let failed = model.preview?.failedGuards.contains(g) ?? false
                Label(passTitle(g), systemImage: failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(model.preview == nil ? .secondary : failed ? Color.red : .green)
            }
            Spacer()
            Button("Check again") { model.refresh() }.disabled(model.loading)
        }
    }

    private func passTitle(_ g: SyncGuard) -> String {
        switch g {
        case .openEmuRunning: "OpenEmu closed"
        case .conflictedCopy: "No conflicted copy"
        case .differentLibrary: "Same library"
        case .integrityFailed: "Integrity check"
        }
    }

    @ViewBuilder private var main: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let blocked = model.blockedByImport {
                banner(blocked)
            }
            if let error = model.error { banner(error) }
            if let result = model.result {
                Label("Synced. OpenEmu's database was backed up first as \(result.backupName).", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if let preview = model.preview {
                ForEach(preview.failedGuards, id: \.self) { banner(failedText($0)) }
                previewSections(preview)
                otherCollections(preview)
                syncButton(preview)
            } else if model.loading {
                ProgressView("Reading OpenEmu's library…")
            }
        }
    }

    private func failedText(_ g: SyncGuard) -> String {
        switch g {
        case .openEmuRunning: "OpenEmu is open. Quit it, then Check again: Sync only writes while OpenEmu is closed."
        case .conflictedCopy: "Dropbox left a conflicted copy next to OpenEmu's library. Sort it out in Finder, then Check again."
        case .differentLibrary:
            "This isn't the OpenEmu library the journal imported (its store ID changed). Syncing into another library isn't supported."
        case .integrityFailed: "OpenEmu's library failed its integrity check. Open OpenEmu to let it repair, or restore a backup."
        }
    }

    private func banner(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.octagon.fill")
            .foregroundStyle(.white).padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(.red, in: .rect(cornerRadius: 8))
    }

    @ViewBuilder private func previewSections(_ p: SyncPreview) -> some View {
        GroupBox("Stars") {
            list(
                p.starChanges.map {
                    "\($0.gameName): \($0.stars)★ (was \(Set($0.current).sorted().map { "\($0)★" }.joined(separator: ", ")))"
                })
        }
        GroupBox("Collections") {
            list(
                p.collectionChanges.map { c in
                    "\(c.isNew ? "New: " : "")\(c.name)\(c.renamedFrom.map { " (was \($0))" } ?? "") +\(c.added) −\(c.removed)"
                } + p.deletedListCollections.map { "Deleted List: \($0) (collection removed)" })
        }
        GroupBox("Covers") {
            list(
                p.coversAdded.map { "Add: \($0.gameName)" } + p.coversReplaced.map { "Replace: \($0.gameName)" }
                    + p.coversSkipped.map { "Skipped: \($0.gameName) (\(skipReason($0.reason)))" })
        }
        if !p.notSynced.isEmpty {
            GroupBox("Not synced") {
                list(p.notSynced.map { "\($0.name): Duplicate Versions, resolve them in the Review queue" })
            }
        }
    }

    private func skipReason(_ r: SyncPreview.SkippedCover.Reason) -> String {
        switch r {
        case .hasBoxArt: "OpenEmu has box art"
        case .awaitingOpenVGDB: "waiting for OpenEmu's game lookup"
        case .downloadFailed: "IGDB's cover couldn't be downloaded"
        case .unreadable: "the Cover isn't a readable image"
        }
    }

    private func list(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if lines.isEmpty { Text("No changes").foregroundStyle(.secondary) }
            ForEach(Array(lines.prefix(200).enumerated()), id: \.offset) { Text($0.element).font(.callout) }
            if lines.count > 200 { Text("…and \(lines.count - 200) more").foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func otherCollections(_ p: SyncPreview) -> some View {
        if !p.otherCollections.isEmpty {
            GroupBox("Collections the journal doesn't own") {
                VStack(alignment: .leading) {
                    Text("Tick a collection to delete it in OpenEmu. Unticked ones are left alone and asked about at the next Sync.")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(p.otherCollections) { c in
                        Toggle(
                            "\(c.name) (\(c.gameCount) game\(c.gameCount == 1 ? "" : "s"))",
                            isOn: Binding(
                                get: { model.deleting.contains(c.pk) },
                                set: { on in if on { model.deleting.insert(c.pk) } else { model.deleting.remove(c.pk) } }))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func syncButton(_ p: SyncPreview) -> some View {
        let count = model.deleting.count
        return HStack {
            Spacer()
            if model.syncing { ProgressView().controlSize(.small) }
            Button(
                count == 0 ? "Sync" : "Sync and delete \(count) collection\(count == 1 ? "" : "s")", role: count == 0 ? nil : .destructive
            ) {
                model.run()
            }
            .buttonStyle(.borderedProminent)
            .tint(count == 0 ? nil : .red)
            .disabled(!p.failedGuards.isEmpty || model.blockedByImport != nil || model.syncing || model.loading)
        }
    }
}
