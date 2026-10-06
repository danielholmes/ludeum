import Foundation
import Synchronization

/// Lets one Import run at a time, and holds the background refresh while it runs,
/// since they share the rate limiters.
public final class WorkGate: Sendable {
    private struct State {
        var importing = false
        var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    }

    private let state = Mutex(State())

    public init() {}

    /// An Import is running.
    public var isImporting: Bool { state.withLock { $0.importing } }

    /// Starts an Import, or returns false if one is already running.
    public func beginImport() -> Bool {
        state.withLock {
            guard !$0.importing else { return false }
            $0.importing = true
            return true
        }
    }

    /// Ends the Import and releases anything waiting. Ending when none is running does nothing.
    public func endImport() {
        let waiters = state.withLock { s -> [CheckedContinuation<Void, Never>] in
            guard s.importing else { return [] }
            s.importing = false
            defer { s.waiters = [:] }
            return Array(s.waiters.values)
        }
        for waiter in waiters { waiter.resume() }
    }

    /// Returns once no Import is running, or when the waiting task is cancelled.
    public func waitUntilClear() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let resumeNow = state.withLock { s in
                    if !s.importing || Task.isCancelled { return true }
                    s.waiters[id] = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            state.withLock { $0.waiters.removeValue(forKey: id) }?.resume()
        }
    }
}
