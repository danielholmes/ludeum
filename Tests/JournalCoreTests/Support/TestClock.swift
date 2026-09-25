import Foundation
import Synchronization
@testable import JournalCore

/// A clock the test controls. Sleeping advances time instantly.
final class TestClock: TimeSource, Sendable {
    private let current: Mutex<Date>

    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        current = Mutex(start)
    }

    func now() -> Date { current.withLock { $0 } }

    func sleep(seconds: Double) async throws {
        advance(seconds: seconds)
    }

    func advance(seconds: Double) {
        current.withLock { $0 = $0.addingTimeInterval(seconds) }
    }

    func advance(days: Double) { advance(seconds: days * 86_400) }
}
