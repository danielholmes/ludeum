import LudeumCore
import SwiftUI

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
            parts.append(!work.importing ? "Refreshing the cache" : "Cache refresh paused")
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
            Text(!work.importing ? "Refreshing the cache \(progress.done)/\(progress.total)" : "Cache refresh paused")
                .font(.caption).monospacedDigit()
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))).controlSize(.small)
        }
        .help("Refreshing IGDB and Hasheous data older than 60 days. Pauses during an Import.")
    }
}
