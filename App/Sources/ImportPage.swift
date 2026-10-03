import AppKit
import JournalCore
import SwiftUI

/// The first Import's state, shared by the Import page and the quit check.
@Observable @MainActor final class ImportModel {
    enum State: Equatable {
        case idle
        case running(ImportPhase, Double)
        case draft(ImportDraft)
        case committed
    }

    private(set) var state: State = .idle
    var error: String?
    private var task: Task<Void, Never>?
    private let services: Services

    /// True while the phases or the commit run: quitting asks first.
    static var isRunning = false

    init(services: Services) {
        self.services = services
        if (try? services.journal?.firstImportDone()) == true {
            state = .committed
        } else {
            do {
                if let draft = try firstImport?.loadDraft() { state = .draft(draft) }
            } catch {
                self.error = "The saved Import draft couldn't be read (\(error.localizedDescription)). Discard it and start again."
            }
        }
    }

    var firstImport: FirstImport? {
        guard let igdb = services.igdb, let hasheous = services.hasheous, let journal = services.journal else { return nil }
        return FirstImport(
            igdb: igdb, hasheous: hasheous, journal: journal, backups: services.settings.backups(),
            draftFolder: AppSettings.appFolder.appending(path: "Import draft", directoryHint: .isDirectory))
    }

    var draft: ImportDraft? { if case .draft(let d) = state { d } else { nil } }

    func start() { run { try await $0.start(library: self.services.settings.openEmuLibrary, progress: $1) } }

    func checkAgain() {
        guard let draft else { return }
        run { try await $0.checkAgain(draft, library: self.services.settings.openEmuLibrary, progress: $1) }
    }

    /// Runs a phase sequence off the main actor, with progress, until it gives a draft or is cancelled.
    private func run(
        _ work: @escaping @Sendable (FirstImport, @escaping @Sendable (ImportPhase, Double) -> Void) async throws -> ImportDraft
    ) {
        guard let firstImport else {
            error = "Set up IGDB in Settings first."
            return
        }
        let previous = state
        state = .running(.snapshot, 0)
        error = nil
        Self.isRunning = true
        task = Task {
            do {
                // FirstImport's work runs off the main actor, and cancelling this task cancels it.
                let draft = try await work(firstImport) { phase, fraction in
                    Task { @MainActor in self.advance(phase, fraction) }
                }
                state = .draft(draft)
            } catch is CancellationError {
                state = previous
            } catch {
                state = previous
                self.error = error.localizedDescription
            }
            Self.isRunning = false
        }
    }

    /// Progress only moves forward: updates can arrive out of order.
    private func advance(_ phase: ImportPhase, _ fraction: Double) {
        guard case .running(let current, let done) = state else { return }
        let order = ImportPhase.allCases
        if (order.firstIndex(of: phase)!, fraction) > (order.firstIndex(of: current)!, done) { state = .running(phase, fraction) }
    }

    /// Cancels the running phases. Lookups already made stay in the cache, so a rerun is quick.
    func cancel() { task?.cancel() }

    func answer(_ start: StartAnswer, for rom: Int64) {
        guard var draft, let firstImport else { return }
        do {
            try firstImport.answer(&draft, start: start, forROM: rom)
            state = .draft(draft)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func discard() {
        do {
            try firstImport?.discardDraft()
            state = .idle
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// True while the commit runs: the button is disabled and quitting asks first.
    private(set) var committing = false

    // MARK: Ongoing Imports

    /// The last ongoing Import's changes, shown until dismissed. Nil when it changed nothing.
    var summary: OngoingImportResult?
    /// When the last ongoing Import ran.
    private(set) var lastImported: Date?
    private(set) var importingNow = false

    /// An ongoing Import: at launch, when OpenEmu quits, and by hand. Only after the first Import,
    /// never while a draft exists, and one at a time.
    func importNow() {
        guard state == .committed, !importingNow, !Self.isRunning, let igdb = services.igdb, let hasheous = services.hasheous,
            let journal = services.journal
        else { return }
        importingNow = true
        Self.isRunning = true
        let run = OngoingImport(
            igdb: igdb, hasheous: hasheous, journal: journal, backups: services.settings.backups(),
            snapshotFile: AppSettings.appFolder.appending(path: "OpenEmu snapshot.sqlite"))
        let library = services.settings.openEmuLibrary
        Task {
            do {
                let result = try await run.run(library: library)
                if result.changedSomething { summary = result }
                lastImported = Date()
                error = nil
                services.changes.changed()
            } catch ImportError.libraryReplaced {
                error =
                    "OpenEmu's library was rebuilt or replaced (its store ID changed), so the Import stopped. Re-pointing the journal at a new library isn't supported yet."
            } catch {
                self.error = "Import failed: \(error.localizedDescription)"
            }
            importingNow = false
            Self.isRunning = false
        }
    }

    func commit() {
        guard let draft, let firstImport, !committing else { return }
        committing = true
        Self.isRunning = true
        Task {
            do {
                try await firstImport.commit(draft)
                state = .committed
                services.changes.coverChanged()
            } catch {
                self.error = error.localizedDescription
            }
            committing = false
            Self.isRunning = false
        }
    }
}

/// The Import page: the phase timeline on the left, then progress or the "Before you can commit"
/// checklist, "Not blocking", and the sticky Commit bar.
struct ImportPage: View {
    @Bindable var model: ImportModel
    @State private var confirmingDiscard = false

    var body: some View {
        HStack(spacing: 0) {
            timeline.frame(width: 200).padding().background(.background.secondary)
            Divider()
            VStack(spacing: 0) {
                ScrollView { main.padding() }
                if model.draft != nil {
                    Divider()
                    commitBar.padding()
                }
            }
        }
        .navigationTitle("Import")
        .confirmationDialog("Discard the Import draft?", isPresented: $confirmingDiscard) {
            Button("Discard draft", role: .destructive) { model.discard() }
        } message: {
            Text("Your start dates and other answers are thrown away. The next Import starts fresh.")
        }
    }

    // MARK: Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("First Import").font(.headline)
            ForEach(ImportPhase.allCases, id: \.self) { phase in
                Label(phaseTitle(phase), systemImage: phaseIcon(phase)).foregroundStyle(phaseColor(phase))
            }
            Spacer()
            if model.draft != nil {
                Button("Discard draft…", role: .destructive) { confirmingDiscard = true }
            }
        }
    }

    private func phaseTitle(_ phase: ImportPhase) -> String {
        switch phase {
        case .snapshot: "Snapshot"
        case .lookups: "Lookups"
        case .matching: "Matching"
        case .review: "Review"
        }
    }

    private enum PhaseStatus { case waiting, running, done, blocking }

    private func status(_ phase: ImportPhase) -> PhaseStatus {
        switch model.state {
        case .idle: .waiting
        case .committed: .done
        case .running(let current, _):
            phase == current
                ? .running : ImportPhase.allCases.firstIndex(of: phase)! < ImportPhase.allCases.firstIndex(of: current)! ? .done : .waiting
        case .draft(let draft): phase == .review && !draft.blockers.isEmpty ? .blocking : .done
        }
    }

    private func phaseIcon(_ phase: ImportPhase) -> String {
        switch status(phase) {
        case .waiting: "circle"
        case .running: "circle.dotted"
        case .done: "checkmark.circle.fill"
        case .blocking: "exclamationmark.circle.fill"
        }
    }

    private func phaseColor(_ phase: ImportPhase) -> Color {
        switch status(phase) {
        case .waiting: .secondary
        case .running: .accentColor
        case .done: .green
        case .blocking: .orange
        }
    }

    // MARK: Main area

    @ViewBuilder private var main: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = model.error { Text(error).foregroundStyle(.red) }
            switch model.state {
            case .idle:
                ContentUnavailableView {
                    Label("Import from OpenEmu", systemImage: "square.and.arrow.down")
                } description: {
                    Text(
                        "Reads a snapshot of OpenEmu's library and matches every ROM. Nothing becomes journal data until you commit, and OpenEmu is never changed."
                    )
                } actions: {
                    Button("Start Import") { model.start() }.buttonStyle(.borderedProminent)
                }
            case .running(let phase, let fraction):
                VStack(alignment: .leading, spacing: 8) {
                    Text(phaseTitle(phase)).font(.headline)
                    ProgressView(value: fraction)
                    Button("Cancel") { model.cancel() }
                }
                .frame(maxWidth: 480)
            case .draft(let draft):
                checklist(draft)
            case .committed:
                ContentUnavailableView {
                    Label("Up to date with OpenEmu", systemImage: "checkmark.circle")
                } description: {
                    Text(
                        "Imports run at launch and each time OpenEmu quits."
                            + (model.lastImported.map { " Last Import: \($0.formatted(date: .omitted, time: .shortened))." } ?? ""))
                } actions: {
                    Button(model.importingNow ? "Importing…" : "Import now") { model.importNow() }.disabled(model.importingNow)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func checklist(_ draft: ImportDraft) -> some View {
        let blockers = draft.blockers
        Text("Before you can commit").font(.title2)
        if blockers.isEmpty {
            Label("Nothing is blocking the commit.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
        let current = draft.library.roms.filter { $0.collections.contains("_Current") }
        if !current.isEmpty {
            GroupBox {
                DisclosureGroup("Start dates for _Current (\(blockers.missingStartDates.count) to answer)") {
                    ForEach(current, id: \.pk) { rom in
                        StartDateRow(rom: rom, answer: draft.startAnswers[rom.pk]) { model.answer($0, for: rom.pk) }
                        Divider()
                    }
                }
            }
        }
        if !blockers.duplicateVersions.isEmpty {
            GroupBox {
                DisclosureGroup("Duplicate Versions (\(blockers.duplicateVersions.count))") {
                    Text("Remove all but one Version of each Game in OpenEmu, then Check again. Real exceptions need a code change.")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(blockers.duplicateVersions) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.headline)
                            ForEach(item.roms, id: \.pk) { DuplicateROMRow(rom: $0) }
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                    Button("Check again") { model.checkAgain() }
                }
            }
        }
        Text("Not blocking").font(.title2).padding(.top)
        let s = draft.summary
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(s.automatic) ROMs matched automatically, into \(s.games) Games.")
                Text(
                    "Review queue: \(s.namesAgree) suggestions whose names agree, \(s.otherSuggestions) other suggestions, \(s.noSuggestion) with no suggestion. They carry over: answer them after committing."
                )
                Text("\(s.missing) ROMs whose files are gone are imported as missing.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        Button("Check again") { model.checkAgain() }
    }

    private var commitBar: some View {
        let blockers = model.draft?.blockers
        let waiting = [
            blockers.map(\.missingStartDates.count).flatMap { $0 > 0 ? "\($0) start date\($0 == 1 ? "" : "s")" : nil },
            blockers.map(\.duplicateVersions.count).flatMap { $0 > 0 ? "\($0) Duplicate Versions" : nil },
        ]
        .compactMap { $0 }
        return HStack {
            Text(
                waiting.isEmpty
                    ? "Committing can't be undone. A backup is taken first." : "Waiting on " + waiting.joined(separator: " and ")
            )
            .foregroundStyle(.secondary)
            Spacer()
            if model.committing { ProgressView().controlSize(.small) }
            Button("Commit Import") { model.commit() }.buttonStyle(.borderedProminent).disabled(!waiting.isEmpty || model.committing)
        }
    }
}

/// A `_Current` Game: "Started on…" with a Partial date, or "Not playing".
private struct StartDateRow: View {
    let rom: OpenEmuROMRecord
    let answer: StartAnswer?
    let set: (StartAnswer) -> Void
    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(rom.name)
                if let last = rom.lastPlayedAt {
                    Text("Last played \(last.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            TextField("Started on", text: $text, prompt: Text("YYYY-MM")).frame(width: 110).onSubmit(start)
                .foregroundStyle(invalid ? .red : .primary)
            Button("Set", action: start)
            Button("Not playing") { set(.notPlaying) }
            switch answer {
            case .started(let date): Text("Started \(date.text)").foregroundStyle(.green)
            case .notPlaying: Text("Not playing").foregroundStyle(.secondary)
            case nil: EmptyView()
            }
        }
        .onAppear { if case .started(let date) = answer { text = date.text } }
    }

    private func start() {
        guard let date = PartialDate(text.trimmingCharacters(in: .whitespaces)) else {
            invalid = true
            return
        }
        invalid = false
        set(.started(date))
    }
}

/// One present ROM of a Duplicate Versions item: what I'd lose by removing it.
private struct DuplicateROMRow: View {
    let rom: OpenEmuROMRecord

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ROMName(rom.name).version.isEmpty ? rom.name : ROMName(rom.name).version).bold()
                Text(rom.file?.lastPathComponent ?? rom.name).font(.caption)
                Text(details).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let file = rom.file {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }.controlSize(.small)
            }
        }
    }

    private var details: String {
        var parts: [String] = []
        if rom.stars > 0 { parts.append("\(rom.stars)★ in OpenEmu") }
        if !rom.collections.isEmpty { parts.append(rom.collections.joined(separator: ", ")) }
        if rom.playTimeSeconds > 0 { parts.append("played \(Int(rom.playTimeSeconds / 60)) min") }
        return parts.isEmpty ? "No OpenEmu data" : parts.joined(separator: " · ")
    }
}

/// Asks before quitting while the Import's phases are running.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard MainActor.assumeIsolated({ ImportModel.isRunning }) else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "An Import is running"
        alert.informativeText =
            "Quitting stops it. Nothing has been written to the journal, and lookups already made are kept for next time."
        alert.addButton(withTitle: "Keep importing")
        alert.addButton(withTitle: "Quit")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
