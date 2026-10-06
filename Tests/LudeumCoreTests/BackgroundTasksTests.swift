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
        var ended: [String] = []
        tasks.enqueue("Archiving Okami", subject: .rom(1), work: { _ in await gate.wait() }, ended: { ended.append("Okami") })
        tasks.enqueue("Archiving ICO", subject: .rom(2), work: { _ in }, ended: { ended.append("ICO") })

        #expect(tasks.active(.rom(1))?.state == .running)
        #expect(tasks.active(.rom(2))?.state == .queued)

        await gate.release()
        await untilIdle(tasks)

        #expect(ended == ["Okami", "ICO"])
        #expect(tasks.items.isEmpty)
    }

    @Test func aFailureStaysListedSayingWhy() async {
        let tasks = BackgroundTasks()
        tasks.enqueue("Archiving Okami", subject: .rom(1), work: { _ in throw ArchiveError.noSevenZip })

        await untilIdle(tasks)

        #expect(tasks.items.map(\.state) == [.failed("7-Zip isn't installed. Run `brew install sevenzip`, then try again.")])
        #expect(tasks.active(.rom(1)) == nil)
    }

    @Test func cancellingWhileRunningLeavesNoFailure() async {
        let tasks = BackgroundTasks()
        tasks.enqueue(
            "Archiving Okami", subject: .rom(1),
            work: { _ in
                while true { try await Task.sleep(for: .milliseconds(1)) }
            })

        tasks.cancel(tasks.items[0].id)
        await untilIdle(tasks)

        #expect(tasks.items.isEmpty)
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

/// A task ends however its work went, so what it may have left half-changed is looked at again.
@MainActor @Suite struct BackgroundTaskEndingTests {
    @Test func aTaskThatFailsHasStillEnded() async {
        let tasks = BackgroundTasks()
        var ended = false
        tasks.enqueue("Archiving Okami", subject: .rom(1), work: { _ in throw ArchiveError.noSevenZip }, ended: { ended = true })

        await untilIdle(tasks)

        #expect(ended)
    }

    @Test func aTaskCancelledWhileRunningHasStillEnded() async {
        let tasks = BackgroundTasks()
        var ended = false
        tasks.enqueue(
            "Archiving Okami", subject: .rom(1),
            work: { _ in
                while true { try await Task.sleep(for: .milliseconds(1)) }
            }, ended: { ended = true })

        tasks.cancel(tasks.items[0].id)
        await untilIdle(tasks)

        #expect(ended)
    }

    @Test func aTaskTakenOffTheQueueNeverStartedSoNeverEnds() async {
        let tasks = BackgroundTasks()
        var ended = false
        tasks.enqueue("Archiving Okami", subject: .rom(1), work: { _ in try await Task.sleep(for: .milliseconds(20)) })
        tasks.enqueue("Archiving ICO", subject: .rom(2), work: { _ in }, ended: { ended = true })

        tasks.cancel(tasks.items[1].id)
        await untilIdle(tasks)

        #expect(!ended)
    }
}
