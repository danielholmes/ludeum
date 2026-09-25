import Foundation
import Testing

@testable import JournalCore

@Suite struct TwitchTokenTests {
    @Test func reusesOneTokenAcrossRequests() async throws {
        let h = try Harness()
        for id in 1...3 { h.internet.addGame(id, "Game \(id)") }

        for id in 1...3 { _ = try await h.igdb.games(ids: [id]) }

        #expect(h.internet.tokensIssued == 1)
    }

    @Test func reusesTheTokenAfterAnAppRestart() async throws {
        let h = try Harness()
        for id in 1...2 { h.internet.addGame(id, "Game \(id)") }
        _ = try await h.igdb.games(ids: [1])
        try h.reopen()

        _ = try await h.igdb.games(ids: [2])

        #expect(h.internet.tokensIssued == 1)
    }

    @Test func replacesATokenThatIGDBRejectsBeforeItsExpiry() async throws {
        let h = try Harness()
        for id in 1...2 { h.internet.addGame(id, "Game \(id)") }
        _ = try await h.igdb.games(ids: [1])
        h.internet.revokeAllTokens()

        let games = try await h.igdb.games(ids: [2])

        #expect(games[2]?.name == "Game 2")
        #expect(h.internet.tokensIssued == 2)
    }

    @Test func givesUpIfIGDBRejectsAFreshToken() async throws {
        let h = try Harness()
        h.internet.addGame(1, "Game 1")
        h.internet.state.withLock { $0.firstValidToken = .max }  // IGDB rejects every token

        await #expect(throws: HTTPStatusError.self) { try await h.igdb.games(ids: [1]) }
        #expect(h.internet.tokensIssued == 2)
    }

    @Test func getsANewTokenShortlyBeforeTheOldOneExpires() async throws {
        let h = try Harness()
        for id in 1...2 { h.internet.addGame(id, "Game \(id)") }
        h.internet.setTokenLifetime(seconds: 5_000_000)
        _ = try await h.igdb.games(ids: [1])
        h.clock.advance(seconds: 5_000_000 - 1_800)

        _ = try await h.igdb.games(ids: [2])

        #expect(h.internet.tokensIssued == 2)
    }
}
