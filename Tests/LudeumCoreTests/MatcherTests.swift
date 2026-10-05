import CryptoKit
import Foundation
import Testing

@testable import LudeumCore

@Suite struct MatcherTests {
    let snes = "openemu.system.snes"

    func rom(
        _ name: String, md5: String = "00000000000000000000000000000000", system: String = "openemu.system.snes",
        title: String? = nil, file: URL? = nil
    ) -> OpenEmuROM {
        OpenEmuROM(id: 1, name: name, openVGDBTitle: title, system: system, md5: md5, file: file)
    }

    func match(_ h: Harness, _ r: OpenEmuROM) async throws -> MatchResult {
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
            try await match(h, rom("Resident Evil 2 - Dual Shock Ver. (USA) (Disc 1) (Leon)", md5: "aa", system: "openemu.system.psx"))
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

    @Test func searchTriesTheOpenVGDBTitleAndTheSystemsOtherPlatforms() async throws {
        let h = try Harness()
        h.internet.addGame(8, "Pocket Monsters Gold")
        h.internet.addSearch("Pocket Monsters Gold", platform: 22, results: [8])

        #expect(
            try await match(h, rom("PMG (J)", system: "openemu.system.gb", title: "Pocket Monsters Gold"))
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

    @Test func aHeaderedNESDumpOnDiskIsRetriedWithoutItsHeader() async throws {
        let h = try Harness()
        let body = Data(repeating: 0x42, count: 64)
        let file = h.directory.appending(path: "Holy Diver (Japan).nes")
        try (Data([0x4E, 0x45, 0x53, 0x1A]) + Data(repeating: 0, count: 12) + body).write(to: file)
        let headerless = Insecure.MD5.hash(data: body).map { String(format: "%02x", $0) }.joined()
        h.internet.addHash(md5: headerless, game: 9, platform: 18)
        h.internet.addGame(9, "Holy Diver")

        #expect(try await match(h, rom("Holy Diver (Japan)", md5: "bb", system: "openemu.system.nes", file: file)) == .automatic(gameID: 9))
    }

    @Test func aMissingFileIsNotRetried() async throws {
        let h = try Harness()
        let file = h.directory.appending(path: "gone.nes")

        #expect(try await match(h, rom("Gone (USA)", md5: "bb", system: "openemu.system.nes", file: file)) == .noSuggestion)
    }
}
