import Foundation
import Testing
@testable import JournalCore

@Suite struct CoverTests {
    @Test func downloadsACoverOnceAndServesItFromDiskAfterThat() async throws {
        let h = try Harness()
        let first = try await h.igdb.cover(imageID: "co1abc")
        try h.reopen()

        let second = try await h.igdb.cover(imageID: "co1abc")

        #expect(try Data(contentsOf: second) == Data("jpeg:co1abc.jpg".utf8))
        #expect(first == second)
        #expect(h.internet.sent(to: FakeInternet.Hosts.igdbImages).count == 1)
    }
}
