import Foundation
import Testing
@testable import JournalCore

@Suite struct ThrottlingTests {
    @Test func sendsAtMostThreeRequestsASecondToIGDB() async throws {
        let h = try Harness()
        for id in 1...6 { h.internet.addGame(id, "Game \(id)") }

        for id in 1...6 { _ = try await h.igdb.games(ids: [id]) }

        let times = h.internet.sent(to: FakeInternet.Hosts.igdb).map(\.at)
        #expect(times.count == 6)
        #expect(zip(times, times.dropFirst()).allSatisfy { $1.timeIntervalSince($0) >= 1.0 / 3 })
    }

    @Test func waitsOutATooManyRequestsReplyFromIGDBThenRetries() async throws {
        let h = try Harness()
        h.internet.addGame(1070, "Super Mario World")
        h.internet.rateLimitOnce(FakeInternet.Hosts.igdb, retryAfter: 5)

        let games = try await h.igdb.games(ids: [1070])

        let times = h.internet.sent(to: FakeInternet.Hosts.igdb).map(\.at)
        #expect(games[1070]?.name == "Super Mario World")
        #expect(times.count == 2)
        #expect(times[1].timeIntervalSince(times[0]) >= 5)
    }
}
