import Foundation
import Testing

@testable import LudeumCore

@Suite struct CoverTests {
    @Test func downloadsACoverOnceAndServesItFromDiskAfterThat() async throws {
        let h = try Harness()
        let first = try await h.igdb.cover(imageID: "co1abc")
        try h.reopen()

        let second = try await h.igdb.cover(imageID: "co1abc")

        #expect(try Data(contentsOf: second) == FakeInternet.coverJPEG)
        #expect(first == second)
        #expect(h.internet.sent(to: FakeInternet.Hosts.igdbImages).count == 1)
    }
}
