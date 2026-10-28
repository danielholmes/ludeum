import Foundation
import Observation

/// What a Background task works on, so the things that would change it can wait while it's queued or running.
public enum TaskSubject: Hashable, Sendable {
    case rom(Int64)
    /// An Emulator being installed.
    case emulator(Emulator)
}

/// Background tasks: long work that runs while I carry on, one at a time in the order asked for,
/// and keeps running when I move to another screen. A failure stays listed until dismissed.
@Observable @MainActor public final class BackgroundTasks {
    public struct Item: Identifiable {
        public enum State: Equatable, Sendable {
            case queued, running
            case failed(String)

            /// Queued or running, rather than failed.
            public var isActive: Bool { self == .queued || self == .running }
        }

        public let id = UUID()
        public let title: String
        public let subject: TaskSubject?
        public internal(set) var state = State.queued
        /// 0–1 while running, when the work reports it.
        public internal(set) var progress: Double?
        fileprivate let work: @Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void
        fileprivate let ended: @MainActor () -> Void
    }

    public private(set) var items: [Item] = []
    /// Where each queued or running task is in `items`, by what it works on: a list of ROMs asks about every row.
    private var activeItems: [TaskSubject: Int] = [:]
    private var running: Task<Void, Never>?
    /// The tasks that have run, however they ended, since nothing was last queued or running.
    private var finished = 0

    /// Whether anything is queued or running, for the quit check.
    public static var isBusy = false

    public init() {}

    public var isBusy: Bool { items.contains { $0.state.isActive } }

    /// How many tasks are waiting their turn.
    public var queuedCount: Int { items.filter { $0.state == .queued }.count }

    /// How many tasks are queued or running.
    public var activeCount: Int { items.filter { $0.state.isActive }.count }

    /// 0–1 across every task since nothing was last queued or running, each an equal share: those that have run count
    /// in full, the running one as far as it has got and the queued ones not at all. Nil when nothing is queued or running.
    public var overallProgress: Double? {
        let active = items.filter { $0.state.isActive }
        guard !active.isEmpty else { return nil }
        let running = active.first { $0.state == .running }?.progress ?? 0
        return (Double(finished) + running) / Double(finished + active.count)
    }

    /// The queued or running task working on `subject`, if any.
    public func active(_ subject: TaskSubject) -> Item? { activeItems[subject].map { items[$0] } }

    /// Whether a task working on `subject` is queued or running. Unlike `active`, a view asking this isn't redrawn as
    /// the task's progress moves.
    public func isActive(_ subject: TaskSubject) -> Bool { activeItems[subject] != nil }

    /// Adds work to the queue. `ended` runs on the main actor once the work has run, whether it succeeded, failed or was
    /// cancelled: work that didn't finish can still have changed things.
    public func enqueue(
        _ title: String, subject: TaskSubject? = nil,
        work: @escaping @Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void,
        ended: @escaping @MainActor () -> Void = {}
    ) {
        items.append(Item(title: title, subject: subject, work: work, ended: ended))
        startNext()
    }

    /// Stops it if it's running, or takes it off the queue.
    public func cancel(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if items[i].state == .running { running?.cancel() } else { items.remove(at: i) }
        update()
    }

    public func dismiss(_ id: UUID) {
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
                items.removeAll { $0.id == id }
            } catch is CancellationError {
                // Cancelled, not failed.
                items.removeAll { $0.id == id }
            } catch {
                if let i = items.firstIndex(where: { $0.id == id }) { items[i].state = .failed(error.localizedDescription) }
            }
            finished += 1
            update()
            item.ended()
            running = nil
            startNext()
        }
    }

    /// To the nearest whole percent, so the screens showing it aren't redrawn for every chunk the work gets through.
    private func setProgress(_ id: UUID, _ fraction: Double) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].state == .running else { return }
        let percent = (fraction * 100).rounded() / 100
        if items[i].progress != percent { items[i].progress = percent }
    }

    /// After every change to which tasks there are or what state they're in.
    private func update() {
        Self.isBusy = isBusy
        if !isBusy, finished != 0 { finished = 0 }
        var active: [TaskSubject: Int] = [:]
        for (i, item) in items.enumerated() where item.state.isActive {
            if let subject = item.subject, active[subject] == nil { active[subject] = i }
        }
        if activeItems != active { activeItems = active }
    }
}
