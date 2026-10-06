import Foundation
import Testing

@testable import LudeumCore

/// Work a test lets finish when it chooses.
private actor Gate {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var open = false

    func wait() async {
        if open { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        open = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }
}

@MainActor func untilIdle(_ tasks: BackgroundTasks) async {
    while tasks.items.contains(where: { $0.state == .queued || $0.state == .running }) { await Task.yield() }
}

@MainActor @Suite struct BackgroundTasksTests {
    @Test func tasksRunOneAtATimeInTheOrderAskedFor() async {
        let tasks = BackgroundTasks()
        let gate = Gate()
        var finished: [String] = []
        tasks.enqueue("Archiving Okami", subject: .rom(1), work: { _ in await gate.wait() }, finished: { finished.append("Okami") })
        tasks.enqueue("Archiving ICO", subject: .rom(2), work: { _ in }, finished: { finished.append("ICO") })

        #expect(tasks.active(.rom(1))?.state == .running)
        #expect(tasks.active(.rom(2))?.state == .queued)

        await gate.release()
        await untilIdle(tasks)

        #expect(finished == ["Okami", "ICO"])
        #expect(tasks.items.isEmpty)
    }

    @Test func aFailureStaysListedSayingWhyAndIsntFinished() async {
        let tasks = BackgroundTasks()
        var finished = false
        tasks.enqueue("Archiving Okami", subject: .rom(1), work: { _ in throw ArchiveError.noSevenZip }, finished: { finished = true })

        await untilIdle(tasks)

        #expect(tasks.items.map(\.state) == [.failed("7-Zip isn't installed. Run `brew install sevenzip`, then try again.")])
        #expect(tasks.active(.rom(1)) == nil)
        #expect(!finished)
    }

    @Test func cancellingWhileRunningLeavesNoFailure() async {
        let tasks = BackgroundTasks()
        var finished = false
        tasks.enqueue(
            "Archiving Okami", subject: .rom(1),
            work: { _ in
                while true { try await Task.sleep(for: .milliseconds(1)) }
            }, finished: { finished = true })

        tasks.cancel(tasks.items[0].id)
        await untilIdle(tasks)

        #expect(tasks.items.isEmpty)
        #expect(!finished)
    }

    @Test func cancellingAQueuedTaskTakesItOffTheQueue() async {
        let tasks = BackgroundTasks()
        let gate = Gate()
        tasks.enqueue("Archiving Okami", subject: .rom(1), work: { _ in await gate.wait() })
        tasks.enqueue("Archiving ICO", subject: .rom(2), work: { _ in })

        tasks.cancel(tasks.items[1].id)

        #expect(tasks.active(.rom(2)) == nil)
        await gate.release()
        await untilIdle(tasks)
    }
}
