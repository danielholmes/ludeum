import LudeumCore
import SwiftUI
import os

/// Work that isn't a screen's own: the launch refresh of the cache, Import and Sync exclusivity,
/// and whether the journal can be edited right now.
@Observable @MainActor final class BackgroundWork {
    /// Shared with `CacheRefresh`, which waits while an Import or Sync holds it.
    let gate = WorkGate()
    /// The refresh's (done, total) while it runs; nil otherwise.
    private(set) var refreshing: (done: Int, total: Int)?
    /// True during the Import's write step: no journal edits until it's done.
    private(set) var journalLocked = false
    /// Mirrors `gate.current`, for views.
    private(set) var exclusive: ExclusiveWork?

    private static let log = Logger(subsystem: "org.danielholmes.Ludeum", category: "refresh")

    /// Starts Import or Sync, or returns false while the other (or another of the same) runs.
    func begin(_ work: ExclusiveWork) -> Bool {
        guard gate.begin(work) else { return false }
        exclusive = work
        return true
    }

    func end(_ work: ExclusiveWork) {
        guard gate.current == work else { return }
        gate.end(work)
        exclusive = nil
        journalLocked = false
    }

    /// Wraps the Import's write step.
    func lockJournal(_ locked: Bool) { journalLocked = locked }

    /// Progress only moves forward: updates can arrive out of order.
    private func advance(_ done: Int, _ total: Int) {
        guard done >= (refreshing?.done ?? 0), !finished else { return }
        refreshing = done == total ? nil : (done, total)
    }

    private var finished = false

    /// The low-priority refresh of expired cache entries, once per launch. Errors are logged.
    func refreshCache(services: Services) async {
        guard let cache = services.cache, let hasheous = services.hasheous else { return }
        let refresh = CacheRefresh(cache: cache, igdb: services.igdb, hasheous: hasheous, gate: gate)
        let result = await Task.detached(priority: .background) {
            await refresh.run { done, total in
                Task { @MainActor in self.advance(done, total) }
            }
        }.value
        finished = true
        refreshing = nil
        for error in result.errors { Self.log.error("Cache refresh: \(error, privacy: .public)") }
        if result.refreshed > 0 {
            Self.log.info("Cache refresh: \(result.refreshed) entries refreshed")
            services.changes.coverChanged()
        }
    }
}

/// The refresh's small status indicator: nothing unless it's running.
struct RefreshStatus: View {
    let work: BackgroundWork

    var body: some View {
        if let progress = work.refreshing {
            HStack(spacing: 6) {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .progressViewStyle(.circular).controlSize(.small)
                Text(work.exclusive == nil ? "Refreshing \(progress.done)/\(progress.total)" : "Refresh paused")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .help("Refreshing IGDB and Hasheous data older than 60 days. Pauses during an Import or Sync.")
        }
    }
}

/// Starts the cache refresh once per launch, not for every new main window.
struct CacheRefreshOnLaunch: ViewModifier {
    let services: Services
    @MainActor private static var started = false

    func body(content: Content) -> some View {
        content.task {
            guard !Self.started else { return }
            Self.started = true
            // Not tied to the window: closing it mustn't stop the refresh.
            Task { await services.work.refreshCache(services: services) }
        }
    }
}
