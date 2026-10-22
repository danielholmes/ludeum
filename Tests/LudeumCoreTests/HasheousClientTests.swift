import Foundation
import Testing

@testable import LudeumCore

@Suite struct HasheousClientTests {
    @Test func aKnownChecksumGivesTheIGDBGameAndPlatform() async throws {
        let h = try Harness()
        h.internet.addHash(md5: "CDD3C8C37322978CA8669B34BC89C804", game: 1070, platform: 19)

        let result = try await h.hasheous.lookup(md5: "cdd3c8c37322978ca8669b34bc89c804")

        #expect(result.match?.igdbGameID == 1070)
        #expect(result.match?.igdbPlatformID == 19)
    }

    @Test func aDATEntrysRegionsAreItsNamesRegionTagsElseItsCountries() async throws {
        let h = try Harness()
        h.internet.addHash(
            md5: "a1", game: 1, platform: 24, romName: "Medal of Honor - Infiltrator (USA, Europe) (En,Fr,De).gba",
            country: ["US": "United States"])
        h.internet.addHash(
            md5: "a2", game: 1, platform: 29, romName: "Urban Strike (1994-08-30)(Electronic Arts)(EU-US).bin",
            country: ["EU": "Europe", "US": "United States"])
        h.internet.addHash(md5: "a3", game: 1, platform: 33, romName: "Feed IT Souls.gbc", country: ["World": "Worldwide"])
        h.internet.addHash(md5: "a4", game: 1, platform: 24, romName: "Splinter Cell.gba", country: ["GB": "United Kingdom"])
        h.internet.addHash(md5: "a5", game: 1, platform: 7, romName: "Crash Bandicoot.cue")
        h.internet.addHash(md5: "a6", game: 1, platform: 7)
        h.internet.addHash(md5: "a7", game: 1, platform: 18, romName: "Duck Hunt (Unknown).nes", country: ["US": "United States"])

        func regions(_ md5: String) async throws -> [String]? { try await h.hasheous.lookup(md5: md5).match?.regions }

        #expect(try await regions("a1") == ["Europe", "USA"])
        #expect(try await regions("a2") == ["Europe", "USA"])
        #expect(try await regions("a3") == ["World"])
        #expect(try await regions("a4") == ["UK"])
        #expect(try await regions("a5") == [])
        #expect(try await regions("a6") == [])
        #expect(try await regions("a7") == ["USA"])
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
