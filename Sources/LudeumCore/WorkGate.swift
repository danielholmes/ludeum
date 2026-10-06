import Foundation
import Synchronization

/// Work that runs alone: while it runs, no other can start.
public enum ExclusiveWork: Sendable, Equatable {
    case importing
}

/// Lets one Import run at a time, and holds the background refresh while it runs,
/// since they share the rate limiters.
public final class WorkGate: Sendable {
    private struct State {
        var current: ExclusiveWork?
        var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    }

    private let state = Mutex(State())

    public init() {}

    public var current: ExclusiveWork? { state.withLock { $0.current } }

    /// Starts `work`, or returns false if an Import is already running.
    public func begin(_ work: ExclusiveWork) -> Bool {
        state.withLock {
            guard $0.current == nil else { return false }
            $0.current = work
            return true
        }
    }

    /// Ends `work` and releases anything waiting. Ending work that isn't running does nothing.
    public func end(_ work: ExclusiveWork) {
        let waiters = state.withLock { s -> [CheckedContinuation<Void, Never>] in
            guard s.current == work else { return [] }
            s.current = nil
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
                    if s.current == nil || Task.isCancelled { return true }
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
