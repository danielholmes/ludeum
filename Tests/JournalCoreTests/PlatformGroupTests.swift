import Testing

@testable import JournalCore

@Suite struct PlatformGroupTests {
    let j: JournalHarness

    init() throws {
        j = try JournalHarness()
        try j.journal.addPlatform(id: 6, name: "PC (Microsoft Windows)")
        try j.journal.addPlatform(id: 13, name: "DOS")
        try j.journal.addPlatform(id: 19, name: "SNES")
        try j.journal.addGameByHand(name: "Half-Life", platformId: 6)
        try j.journal.addGameByHand(name: "Doom", platformId: 13)
        try j.journal.addGameByHand(name: "Super Metroid", platformId: 19)
    }

    @Test func dosAndWindowsShowAsOnePCPlatform() throws {
        #expect(
            try j.journal.platformCounts() == [
                PlatformCount(id: 6, name: "PC", games: 2), PlatformCount(id: 19, name: "Super Nintendo Entertainment System", games: 1),
            ])
        #expect(try j.journal.shownPlatforms().map(\.name) == ["PC", "Super Nintendo Entertainment System"])
    }

    @Test func superFamicomShowsAsSNES() throws {
        try j.journal.addPlatform(id: 58, name: "Super Famicom")
        try j.journal.addGameByHand(name: "Bahamut Lagoon", platformId: 58)

        #expect(try j.journal.platformCounts().first { $0.id == 19 }?.games == 2)
        #expect(
            try j.journal.library(LibraryFilter(platformId: 19), sort: .name, ascending: true).map(\.name) == [
                "Bahamut Lagoon", "Super Metroid",
            ])
    }

    @Test func filteringOnPCFindsBothAndRowsSayPC() throws {
        let rows = try j.journal.library(LibraryFilter(platformId: 6), sort: .name, ascending: true)

        #expect(rows.map(\.name) == ["Doom", "Half-Life"])
        #expect(Set(rows.map(\.platformName)) == ["PC"])
        #expect(rows.map(\.platformId) == [13, 6])  // each keeps its own IGDB platform
    }
}
