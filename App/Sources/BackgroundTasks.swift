import LudeumCore
import SwiftUI

/// Pinned to the foot of the sidebar: nothing when idle, one line while busy, and the full list
/// (with Cancel, and failures to dismiss) when opened. The cache refresh shows here too. A task working on a ROM
/// opens its Game when its title is clicked.
struct BackgroundTasksPanel: View {
    let tasks: BackgroundTasks
    let work: BackgroundWork
    let journal: LudeumStore?
    let open: (GameID) -> Void
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
            parts.append(!work.importing ? "Refreshing the cache" : "Cache refresh paused")
        }
        if waiting > 0 { parts.append("\(waiting) waiting") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: " · ")
    }

    private func row(_ item: BackgroundTasks.Item) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                title(item)
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

    /// The title, as a link to its Game when the task works on one of the Game's ROMs.
    @ViewBuilder private func title(_ item: BackgroundTasks.Item) -> some View {
        if case .rom(let rom) = item.subject, let game = try? journal?.game(ofROM: rom) {
            Button {
                open(game)
            } label: {
                Text(item.title).font(.caption).lineLimit(1).underline()
            }
            .buttonStyle(.plain)
            .help("Show its Game")
        } else {
            Text(item.title).font(.caption).lineLimit(1)
        }
    }

    private func refreshRow(_ progress: (done: Int, total: Int)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(!work.importing ? "Refreshing the cache \(progress.done)/\(progress.total)" : "Cache refresh paused")
                .font(.caption).monospacedDigit()
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))).controlSize(.small)
        }
        .help("Refreshing IGDB and Hasheous data older than 60 days. Pauses during an Import.")
    }
}

/// A queued or running task working on one thing, in place of the button that started it: its progress, or Queued.
/// Given `tasks`, a queued one can be taken off the queue there.
struct BackgroundTaskProgress: View {
    let task: BackgroundTasks.Item
    var tasks: BackgroundTasks? = nil

    var body: some View {
        if task.state == .running {
            HStack(spacing: 6) {
                ProgressView(value: task.progress ?? 0).controlSize(.small).frame(width: 80)
                Text(task.progress.map { "\(Int($0 * 100))%" } ?? "").font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .help(task.title)
        } else {
            HStack(spacing: 4) {
                Text("Queued").font(.caption).foregroundStyle(.secondary).help("Waiting in Background tasks")
                if let tasks {
                    Button("Cancel", systemImage: "xmark.circle") { tasks.cancel(task.id) }.labelStyle(.iconOnly).buttonStyle(.plain)
                        .help("Take it off the queue")
                }
            }
        }
    }
}
