import Foundation
import Testing
@testable import JournalCore

@Suite struct HasheousClientTests {
    @Test func aKnownChecksumGivesTheIGDBGameAndPlatform() async throws {
        let h = try Harness()
        h.internet.addHash(md5: "CDD3C8C37322978CA8669B34BC89C804", game: 1070, platform: 19)

        let result = try await h.hasheous.lookup(md5: "cdd3c8c37322978ca8669b34bc89c804")

        #expect(result.match?.igdbGameID == 1070)
        #expect(result.match?.igdbPlatformID == 19)
    }

    @Test func anUnknownChecksumIsCachedAsNoMatch() async throws {
        let h = try Harness()
        let first = try await h.hasheous.lookup(md5: "00000000000000000000000000000001")
        h.internet.resetSent()

        let second = try await h.hasheous.lookup(md5: "00000000000000000000000000000001")

        #expect(first == .noMatch)
        #expect(second == .noMatch)
        #expect(h.internet.sent.isEmpty)
    }

    @Test func sendsAtMostOneRequestASecond() async throws {
        let h = try Harness()

        for i in 1...3 { _ = try await h.hasheous.lookup(md5: String(format: "%032d", i)) }

        let times = h.internet.sent(to: FakeInternet.Hosts.hasheous).map(\.at)
        #expect(times.count == 3)
        #expect(zip(times, times.dropFirst()).allSatisfy { $1.timeIntervalSince($0) >= 1 })
    }
}
