import Foundation
import Testing

@testable import LudeumCore

@Suite struct LaunchBoxGamesDBTests {
    let h = try! Harness()
    var launchBox: LaunchBoxGamesDB { h.launchBox }

    static let redAlert2 = LaunchBoxGame(
        id: 1, name: "Command & Conquer: Red Alert 2", platform: "Windows", released: "2000-10-23",
        boxes: [(nil, "ra2.jpg"), ("Germany", "ra2-de.jpg")],
        otherImages: [("Screenshot - Gameplay", "ra2-shot.jpg"), ("Box - Back", "ra2-back.jpg")])

    func boxart(_ platform: Int64, _ titles: [String], regions: Set<NameRegion> = [], year: Int? = nil) throws -> String? {
        try launchBox.boxart(platform: platform, titles: titles, regions: regions, year: year)
    }

    @Test func aGameFindsItsBoxFrontByTitleOnItsPlatform() async throws {
        h.internet.setLaunchBox([Self.redAlert2])

        try await launchBox.refresh()

        #expect(try boxart(6, ["Command & Conquer: Red Alert 2"]) == "ra2.jpg")
        #expect(try boxart(7, ["Command & Conquer: Red Alert 2"]) == nil)
    }

    @Test func onlyBoxFrontsAreKept() async throws {
        h.internet.setLaunchBox([
            LaunchBoxGame(
                id: 1, name: "Half-Life", platform: "Windows",
                otherImages: [("Box - Back", "hl-back.jpg"), ("Screenshot - Gameplay", "hl-shot.jpg")]),
            Self.redAlert2,
        ])

        try await launchBox.refresh()

        #expect(try boxart(6, ["Half-Life"]) == nil)
    }

    @Test func aGameIsFoundByItsAlternateName() async throws {
        h.internet.setLaunchBox([
            LaunchBoxGame(
                id: 1, name: "Resident Evil", platform: "Sony Playstation", alternateNames: ["Biohazard"], boxes: [(nil, "re.jpg")])
        ])

        try await launchBox.refresh()

        #expect(try boxart(7, ["Biohazard"]) == "re.jpg")
    }

    @Test func titlesMatchAsLibretrosDoAndPlatformsIGDBSplitsShareLaunchBoxs() async throws {
        h.internet.setLaunchBox([
            LaunchBoxGame(
                id: 1, name: "The Legend of Zelda: A Link to the Past", platform: "Super Nintendo Entertainment System",
                boxes: [(nil, "zelda.jpg")])
        ])

        try await launchBox.refresh()

        #expect(try boxart(19, ["Legend of Zelda, The - A Link to the Past"]) == "zelda.jpg")
        #expect(try boxart(58, ["The Legend of Zelda: A Link to the Past"]) == "zelda.jpg")
    }

    @Test func theBoxIsForItsOwnRegionsElseNorthAmericaWorldNoRegionEuropeJapan() async throws {
        h.internet.setLaunchBox([
            LaunchBoxGame(
                id: 1, name: "Every Region", platform: "Windows",
                boxes: [("Japan", "j.jpg"), ("Europe", "e.jpg"), (nil, "n.jpg"), ("World", "w.jpg"), ("North America", "na.jpg")]),
            LaunchBoxGame(id: 2, name: "No North America", platform: "Windows", boxes: [("Japan", "j2.jpg"), (nil, "n2.jpg")]),
            LaunchBoxGame(id: 3, name: "Germany", platform: "Windows", boxes: [("Japan", "j3.jpg"), ("Germany", "de3.jpg")]),
        ])

        try await launchBox.refresh()

        #expect(try boxart(6, ["Every Region"]) == "na.jpg")
        #expect(try boxart(6, ["Every Region"], regions: [.japan]) == "j.jpg")
        #expect(try boxart(6, ["Every Region"], regions: [.europe]) == "e.jpg")
        #expect(try boxart(6, ["No North America"]) == "n2.jpg")
        #expect(try boxart(6, ["Germany"]) == "de3.jpg")
    }

    @Test func aGamesScreenshotsAreFoundTitleScreensFirst() async throws {
        h.internet.setLaunchBox([
            LaunchBoxGame(
                id: 9, name: "Half-Life", platform: "Windows",
                otherImages: [
                    ("Screenshot - Gameplay", "hl1.jpg"), ("Screenshot - Game Title", "hlt.jpg"), ("Screenshot - Gameplay", "hl2.jpg"),
                    ("Box - Back", "back.jpg"),
                ]),
            Self.redAlert2,
        ])

        try await launchBox.refresh()

        #expect(try launchBox.screenshots(platform: 6, titles: ["Half-Life"], year: nil) == ["hlt.jpg", "hl1.jpg", "hl2.jpg"])
        #expect(try launchBox.screenshots(platform: 6, titles: ["Command & Conquer: Red Alert 2"], year: nil) == ["ra2-shot.jpg"])
        #expect(try boxart(6, ["Half-Life"]) == nil)
    }

    @Test func theScreenshotsAreAllOneGamesTheYearPicking() async throws {
        h.internet.setLaunchBox([
            LaunchBoxGame(
                id: 1, name: "Doom", platform: "Windows", released: "1993-12-10", otherImages: [("Screenshot - Gameplay", "d93.jpg")]),
            LaunchBoxGame(
                id: 2, name: "Doom", platform: "Windows", released: "2016-05-13", otherImages: [("Screenshot - Gameplay", "d16.jpg")]),
        ])

        try await launchBox.refresh()

        #expect(try launchBox.screenshots(platform: 6, titles: ["Doom"], year: 2016) == ["d16.jpg"])
        #expect(try launchBox.screenshots(platform: 6, titles: ["Doom"], year: nil) == ["d93.jpg"])
    }

    @Test func aDumpReadBeforeScreenshotsWereKeptIsReadAgain() throws {
        try h.cache.store(["launchbox:metadata": Data()])

        #expect(try launchBox.isStale())
    }

    @Test func aGamesOwnNameBeatsAnothersAlternateName() async throws {
        h.internet.setLaunchBox([
            LaunchBoxGame(id: 2, name: "Descent 3", platform: "Windows", alternateNames: ["Descent"], boxes: [(nil, "d3.jpg")]),
            LaunchBoxGame(id: 1, name: "Descent", platform: "Windows", boxes: [(nil, "d1.jpg")]),
        ])

        try await launchBox.refresh()

        #expect(try boxart(6, ["Descent"]) == "d1.jpg")
    }

    @Test func theYearPicksBetweenGamesOfTheSameName() async throws {
        h.internet.setLaunchBox([
            LaunchBoxGame(id: 1, name: "Doom", platform: "Windows", released: "1993-12-10", boxes: [(nil, "doom93.jpg")]),
            LaunchBoxGame(id: 2, name: "Doom", platform: "Windows", released: "2016-05-13", boxes: [(nil, "doom16.jpg")]),
        ])

        try await launchBox.refresh()

        #expect(try boxart(6, ["Doom"], year: 2016) == "doom16.jpg")
        #expect(try boxart(6, ["Doom"], year: 1993) == "doom93.jpg")
        #expect(try boxart(6, ["Doom"]) == "doom93.jpg")
    }

    @Test func aDumpIsStaleOnceItsOlderThan30DaysAndANewOneReplacesIt() async throws {
        h.internet.setLaunchBox([Self.redAlert2])
        #expect(try launchBox.isStale())
        try await launchBox.refresh()

        h.clock.advance(days: 29)
        #expect(try launchBox.isStale() == false)

        h.clock.advance(days: 2)
        #expect(try launchBox.isStale())
        h.internet.setLaunchBox([LaunchBoxGame(id: 9, name: "Half-Life", platform: "Windows", boxes: [(nil, "hl.jpg")])])
        try await launchBox.refresh()
        #expect(try boxart(6, ["Half-Life"]) == "hl.jpg")
        #expect(try boxart(6, ["Command & Conquer: Red Alert 2"]) == nil)
        #expect(try launchBox.isStale() == false)
    }

    @Test func aDumpThatCantBeFetchedOrReadKeepsTheOldOne() async throws {
        h.internet.setLaunchBox([Self.redAlert2])
        try await launchBox.refresh()

        h.internet.setDown(FakeInternet.Hosts.launchBox, true)
        await #expect(throws: (any Error).self) { try await launchBox.refresh() }
        h.internet.setDown(FakeInternet.Hosts.launchBox, false)
        h.internet.state.withLock { $0.launchBoxDump = Data("not a zip".utf8) }
        await #expect(throws: (any Error).self) { try await launchBox.refresh() }
        h.internet.setLaunchBox([LaunchBoxGame(id: 1, name: "Half-Life", platform: "Windows")])
        await #expect(throws: (any Error).self) { try await launchBox.refresh() }

        #expect(try boxart(6, ["Command & Conquer: Red Alert 2"]) == "ra2.jpg")
    }

    @Test func aDumpThatCantBeFetchedIsTriedAgainADayLaterNotAtEveryLaunch() async throws {
        h.internet.setLaunchBox([Self.redAlert2])
        try await launchBox.refresh()
        h.clock.advance(days: 31)
        h.internet.setDown(FakeInternet.Hosts.launchBox, true)

        await #expect(throws: (any Error).self) { try await launchBox.refresh() }

        #expect(try launchBox.isStale() == false)
        h.clock.advance(days: 1)
        #expect(try launchBox.isStale())
    }

    @Test func beforeAnyDumpNothingIsFoundAndNothingIsSent() throws {
        #expect(try boxart(6, ["Command & Conquer: Red Alert 2"]) == nil)
        #expect(h.internet.sent.isEmpty)
    }

    @Test func anImageIsDownloadedTheFirstTimeAndKept() async throws {
        let first = try await launchBox.image("ra2.jpg")
        let second = try await launchBox.image("ra2.jpg")

        #expect(first == second)
        #expect(try Data(contentsOf: first) == FakeInternet.boxartPNG)
        #expect(h.internet.sent(to: FakeInternet.Hosts.launchBoxImages).map { $0.request.url?.path() } == ["/ra2.jpg"])
    }
}
