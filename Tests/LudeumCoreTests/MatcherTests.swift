import Foundation
import Testing

@testable import LudeumCore

@Suite struct MatcherTests {
    /// On the SNES unless said otherwise.
    func rom(_ name: String, md5: String? = nil, platforms: [Int] = [19]) -> ROMToMatch {
        ROMToMatch(id: 1, name: name, md5: md5, platforms: platforms)
    }

    func match(_ h: Harness, _ r: ROMToMatch) async throws -> MatchResult {
        try await Matcher(igdb: h.igdb, hasheous: h.hasheous).match([r])[r.id]!
    }

    @Test func aChecksumWhoseNamesAgreeIsAutomatic() async throws {
        let h = try Harness()
        h.internet.addHash(md5: "aa", game: 1070, platform: 19)
        h.internet.addGame(1070, "Super Mario World")

        #expect(try await match(h, rom("Super Mario World (USA)", md5: "aa")) == .automatic(gameID: 1070))
    }

    @Test func aChecksumWhoseNamesDisagreeIsOnlyASuggestion() async throws {
        let h = try Harness()
        h.internet.addHash(md5: "aa", game: 1, platform: 19)
        h.internet.addGame(1, "Super Star Wars")

        #expect(
            try await match(h, rom("Super Star Wars - Return of the Jedi (USA)", md5: "aa"))
                == .suggestion(Suggestion(gameID: 1, source: .checksum, namesAgree: false)))
    }

    @Test func aRelatedRecordWhoseNameAgreesIsSuggestedInstead() async throws {
        let h = try Harness()
        h.internet.addHash(md5: "aa", game: 1, platform: 7)
        h.internet.addGame(1, "Resident Evil 2", fields: ["expanded_games": [["id": 2]]])
        h.internet.addGame(2, "Resident Evil 2: Dual Shock Ver.")

        #expect(
            try await match(h, rom("Resident Evil 2 - Dual Shock Ver. (USA) (Disc 1) (Leon)", md5: "aa", platforms: [7]))
                == .suggestion(Suggestion(gameID: 2, source: .relatedRecord, namesAgree: true, checksumGameID: 1)))
    }

    @Test func withNoChecksumGameTheFirstAgreeingSearchCandidateIsSuggested() async throws {
        let h = try Harness()
        h.internet.addGame(5, "Kirby Super Star Ultra")
        h.internet.addGame(6, "Kirby Super Star")
        h.internet.addSearch("Kirby Super Star", platform: 19, results: [5, 6])

        #expect(
            try await match(h, rom("Kirby Super Star (USA)"))
                == .suggestion(Suggestion(gameID: 6, source: .nameSearch, namesAgree: true)))
    }

    @Test func otherwiseTheFirstSearchCandidateThatCanBeAGame() async throws {
        let h = try Harness()
        h.internet.addGame(5, "Kirby Mod", fields: ["game_type": 5])
        h.internet.addGame(6, "Kirby's Fun Pak", fields: ["game_type": 0])
        h.internet.addSearch("Kirby Super Star", platform: 19, results: [5, 6])

        #expect(
            try await match(h, rom("Kirby Super Star (USA)"))
                == .suggestion(Suggestion(gameID: 6, source: .nameSearch, namesAgree: false)))
    }

    @Test func searchTriesEachOfItsPlatforms() async throws {
        let h = try Harness()
        h.internet.addGame(8, "Pocket Monsters Gold")
        h.internet.addSearch("Pocket Monsters Gold", platform: 22, results: [8])

        #expect(
            try await match(h, rom("Pocket Monsters Gold (J)", platforms: [33, 22]))
                == .suggestion(Suggestion(gameID: 8, source: .nameSearch, namesAgree: true)))
    }

    @Test func aChecksumGameIGDBDoesntKnowIsStillTheSuggestion() async throws {
        let h = try Harness()
        h.internet.addHash(md5: "aa", game: 404, platform: 19)

        #expect(
            try await match(h, rom("Lost Game (USA)", md5: "aa"))
                == .suggestion(Suggestion(gameID: 404, source: .checksum, namesAgree: false)))
    }

    @Test func nothingFoundIsNoSuggestion() async throws {
        let h = try Harness()
        #expect(try await match(h, rom("Unknown Homebrew")) == .noSuggestion)
    }
}
