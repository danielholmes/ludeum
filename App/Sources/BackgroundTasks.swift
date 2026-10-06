import LudeumCore
import SwiftUI

/// Background tasks: long work that runs while I carry on, one at a time in the order asked for,
/// and keeps running when I move to another screen. A failure stays listed until dismissed.
@Observable @MainActor final class BackgroundTasks {
    struct Item: Identifiable {
        enum State: Equatable {
            case queued, running
            case failed(String)
        }

        let id = UUID()
        let title: String
        /// What it works on (e.g. a ROM), so its buttons can wait while it's queued or running.
        let subject: String?
        var state = State.queued
        /// 0–1 while running, when the work reports it.
        var progress: Double?
        fileprivate let work: @Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void
        fileprivate let finished: @MainActor () -> Void
    }

    private(set) var items: [Item] = []
    private var running: Task<Void, Never>?

    /// Whether anything is queued or running, for the quit check.
    static var isBusy = false

    var isBusy: Bool { items.contains { $0.state == .queued || $0.state == .running } }

    func isQueuedOrRunning(_ subject: String) -> Bool {
        items.contains { $0.subject == subject && ($0.state == .queued || $0.state == .running) }
    }

    /// Adds work to the queue. `finished` runs on the main actor after it succeeds.
    func enqueue(
        _ title: String, subject: String? = nil,
        work: @escaping @Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void,
        finished: @escaping @MainActor () -> Void = {}
    ) {
        items.append(Item(title: title, subject: subject, work: work, finished: finished))
        startNext()
    }

    /// Stops it if it's running, or takes it off the queue.
    func cancel(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if items[i].state == .running { running?.cancel() } else { items.remove(at: i) }
        update()
    }

    func dismiss(_ id: UUID) {
        items.removeAll { $0.id == id }
        update()
    }

    private func startNext() {
        update()
        guard running == nil, let i = items.firstIndex(where: { $0.state == .queued }) else { return }
        items[i].state = .running
        let item = items[i]
        running = Task {
            let id = item.id
            do {
                // Nonisolated, so it runs off the main actor; cancelling this task cancels it.
                try await item.work { fraction in Task { @MainActor in self.setProgress(id, fraction) } }
                // A cancel that came in during the work leaves it cancelled, not failed.
                try Task.checkCancellation()
                items.removeAll { $0.id == id }
                item.finished()
            } catch is CancellationError {
                items.removeAll { $0.id == id }
            } catch {
                if let i = items.firstIndex(where: { $0.id == id }) { items[i].state = .failed(Self.describe(error)) }
            }
            running = nil
            startNext()
        }
    }

    private func setProgress(_ id: UUID, _ fraction: Double) {
        if let i = items.firstIndex(where: { $0.id == id }), items[i].state == .running { items[i].progress = fraction }
    }

    private func update() { Self.isBusy = isBusy }

    static func describe(_ error: Error) -> String {
        switch error as? ArchiveError {
        case .noSevenZip: "7-Zip isn't installed. Run `brew install sevenzip`, then try again."
        case .ambiguous(let images): "Several images and no cue sheet: \(images.joined(separator: ", "))."
        case .noImage: "Nothing in the archive is a game image."
        case .notEnoughSpace(let needed):
            "Needs \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)) free."
        case .nothingToDo: "There's no file to work on. Check again, then try again."
        case .alreadyThere(let name): "\(name) is already in the ROM folder."
        case .checkFailed(let name): "\(name) didn't check out, so the original is kept."
        case .sevenZipFailed(let message): "7-Zip failed: \(message)"
        case nil: error.localizedDescription
        }
    }
}

/// Pinned to the foot of the sidebar: nothing when idle, one line while busy, and the full list
/// (with Cancel, and failures to dismiss) when opened. The cache refresh shows here too.
struct BackgroundTasksPanel: View {
    let tasks: BackgroundTasks
    let work: BackgroundWork
    @State private var expanded = false

    var body: some View {
        if !tasks.items.isEmpty || work.refreshing != nil {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption2)
                        Text(summary).font(.caption).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? "Hide Background tasks" : "Show Background tasks")
                if expanded {
                    ForEach(tasks.items) { row($0) }
                    if let refreshing = work.refreshing { refreshRow(refreshing) }
                }
            }
            .padding(10)
            .background(.bar)
        }
    }

    private var summary: String {
        let failed = tasks.items.filter { if case .failed = $0.state { true } else { false } }.count
        let waiting = tasks.items.filter { $0.state == .queued }.count
        var parts: [String] = []
        if let running = tasks.items.first(where: { $0.state == .running }) {
            parts.append(running.title + (running.progress.map { " · \(Int($0 * 100))%" } ?? ""))
        } else if work.refreshing != nil {
            parts.append(work.exclusive == nil ? "Refreshing the cache" : "Cache refresh paused")
        }
        if waiting > 0 { parts.append("\(waiting) waiting") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: " · ")
    }

    private func row(_ item: BackgroundTasks.Item) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(item.title).font(.caption).lineLimit(1)
                Spacer(minLength: 4)
                if case .failed = item.state {
                    Button("Dismiss", systemImage: "xmark") { tasks.dismiss(item.id) }.labelStyle(.iconOnly).buttonStyle(.plain)
                        .help("Dismiss")
                } else {
                    Button("Cancel", systemImage: "xmark.circle") { tasks.cancel(item.id) }.labelStyle(.iconOnly).buttonStyle(.plain)
                        .help(item.state == .running ? "Stop it" : "Take it off the queue")
                }
            }
            switch item.state {
            case .queued: Text("Waiting").font(.caption2).foregroundStyle(.secondary)
            case .running: ProgressView(value: item.progress ?? 0).controlSize(.small)
            case .failed(let message): Text(message).font(.caption2).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func refreshRow(_ progress: (done: Int, total: Int)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(work.exclusive == nil ? "Refreshing the cache \(progress.done)/\(progress.total)" : "Cache refresh paused")
                .font(.caption).monospacedDigit()
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))).controlSize(.small)
        }
        .help("Refreshing IGDB and Hasheous data older than 60 days. Pauses during an Import or Sync.")
    }
}
