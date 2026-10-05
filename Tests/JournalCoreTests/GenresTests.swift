import Foundation
import Testing

@testable import JournalCore

@Suite struct GenresTests {
    let h: Harness
    let j: JournalHarness

    init() throws {
        h = try Harness()
        j = try JournalHarness()
        try j.journal.addPlatform(id: 19, name: "SNES")
        h.internet.addGame(
            1103, "Super Metroid",
            fields: [
                "genres": [["id": 8, "name": "Platform"], ["id": 31, "name": "Adventure"]], "themes": [["name": "Science fiction"]],
            ])
        h.internet.addGame(1070, "Super Mario World", fields: ["genres": [["id": 8, "name": "Platform"]]])
        h.internet.addGame(5, "Chrono Trigger", fields: ["genres": [["id": 12, "name": "Role-playing (RPG)"]]])
        h.internet.addGame(6, "Nothing Listed")
    }

    @Test func genresComeFromTheCachedRecords() async throws {
        let facts = try await LibraryFacts(igdb: h.igdb).byGame([1103, 6])

        #expect(facts[1103]?.genres == ["Platform", "Adventure"])
        #expect(facts[6]?.genres == [])
    }

    @Test func theLibraryNarrowsToOneGenreOrThemeAndUnlinkedGamesNeverMatch() async throws {
        for (id, name) in [(1103, "Super Metroid"), (1070, "Super Mario World"), (5, "Chrono Trigger")] {
            try j.journal.addGame(platformId: 19, name: name, igdbGameId: Int64(id), igdbName: name)
        }
        try j.journal.addGameByHand(name: "Hermano", platformId: 19)
        let rows = try j.journal.library(LibraryFilter(), sort: .name, ascending: true)
        let facts = try await LibraryFacts(igdb: h.igdb).byGame(rows.compactMap(\.igdbGameId))

        #expect(rows.having(LibraryFilter(genre: "Platform"), in: facts).map(\.name) == ["Super Mario World", "Super Metroid"])
        #expect(rows.having(LibraryFilter(genre: "Platform", theme: "Science fiction"), in: facts).map(\.name) == ["Super Metroid"])
        #expect(rows.having(LibraryFilter(), in: facts).count == 4)
    }
}

@Suite struct GameFactsTests {
    @Test func genresThemesAndScreenshotsComeFromTheRecord() async throws {
        let h = try Harness()
        h.internet.addGame(
            1103, "Super Metroid",
            fields: [
                "genres": [["name": "Platform"]], "themes": [["name": "Science fiction"], ["name": "Action"]],
                "involved_companies": [
                    ["developer": true, "publisher": false, "porting": false, "supporting": false, "company": ["name": "Nintendo R&D1"]],
                    ["developer": false, "publisher": true, "porting": false, "supporting": false, "company": ["name": "Nintendo"]],
                    ["developer": true, "publisher": false, "porting": false, "supporting": false, "company": ["name": "Nintendo"]],
                ],
                "url": "https://www.igdb.com/games/super-metroid",
                "rating": 86.27, "rating_count": 8, "aggregated_rating": 92.0, "aggregated_rating_count": 0,
                "websites": [
                    ["type": 6, "url": "https://www.twitch.tv/directory/game/Super%20Metroid"],
                    ["type": 3, "url": "https://en.wikipedia.org/wiki/Super_Metroid"],
                ],
                "external_games": [["external_game_source": 3, "url": "https://www.giantbomb.com/games/3030-1/"]],
                "franchise": ["name": "Metroid"], "franchises": [["name": "Nintendo All-Stars"]], "collections": [["name": "Metroid"]],
                "first_release_date": 765_158_400,
            ])

        let facts = try await h.igdb.facts(igdbGameId: 1103)

        #expect(
            facts
                == GameFacts(
                    genres: ["Platform"], themes: ["Science fiction", "Action"], franchises: ["Metroid", "Nintendo All-Stars"],
                    series: ["Metroid"],
                    credits: [
                        CompanyCredit(name: "Nintendo R&D1", roles: [.developer]),
                        CompanyCredit(name: "Nintendo", roles: [.developer, .publisher]),
                    ], releaseYear: 1994,
                    links: [
                        GameLink(title: "Wikipedia", url: URL(string: "https://en.wikipedia.org/wiki/Super_Metroid")!),
                        GameLink(title: "IGDB", url: URL(string: "https://www.igdb.com/games/super-metroid")!),
                        GameLink(title: "Giant Bomb", url: URL(string: "https://www.giantbomb.com/games/3030-1/")!),
                    ],
                    // No critic score: a count of 0 is none.
                    playerScore: CommunityScore(score: 86.27, count: 8), screenshots: ["sc1103"]))
        let shot = try await h.igdb.screenshot(imageID: "sc1103")
        #expect(shot.path().contains("screenshot_med"))
    }
}

@Suite struct MoreFactsTests {
    @Test func summaryTimeToBeatKeywordsAndTheTrailer() async throws {
        let h = try Harness()
        h.internet.addGame(
            1103, "Super Metroid",
            fields: [
                "summary": "The Space Pirates have stolen the last Metroid.",
                "keywords": [["name": "metroidvania"], ["name": "female protagonist"]],
                "videos": [["name": "Game intro", "video_id": "intro1"], ["name": "Trailer", "video_id": "trail1"]],
            ])
        h.internet.state.withLock { $0.timeToBeat[1103] = 36_000 }

        let facts = try await h.igdb.facts(igdbGameId: 1103)

        #expect(facts.summary == "The Space Pirates have stolen the last Metroid.")
        #expect(facts.keywords == ["metroidvania", "female protagonist"])
        #expect(facts.timeToBeat == TimeToBeat(hastily: nil, normally: 36_000, completely: nil))
        #expect(facts.trailer == URL(string: "https://www.youtube.com/watch?v=trail1"))
    }

    @Test func noTrailerWithoutAVideoCalledOne() async throws {
        let h = try Harness()
        h.internet.addGame(1, "X", fields: ["videos": [["name": "Gameplay Video", "video_id": "g1"]]])

        #expect(try await h.igdb.facts(igdbGameId: 1).trailer == nil)
        #expect(try await h.igdb.facts(igdbGameId: 1).timeToBeat == nil)
    }
}

@Suite struct GameReleaseTests {
    @Test func releasesOnTheROMsPlatformsByRegionEarliestFirst() async throws {
        let h = try Harness()
        h.internet.addGame(
            1070, "Super Mario World",
            fields: [
                "release_dates": [
                    ["platform": 19, "release_region": 2, "y": 1991], ["platform": 19, "release_region": 5, "y": 1990],
                    ["platform": 5, "release_region": 3, "y": 2007], ["platform": 19, "release_region": 1, "y": 1992],
                    ["platform": 19, "release_region": 2, "y": 1995],
                ]
            ])
        let game = try #require(try await h.igdb.games(ids: [1070])[1070])

        #expect(
            game.releases(onSystem: "openemu.system.snes") == [
                GameRelease(region: "Japan", year: 1990), GameRelease(region: "North America", year: 1991),
                GameRelease(region: "Europe", year: 1992),
            ])
    }
}

@Suite struct SearchingFactsTests {
    @Test func searchAlsoFindsCompaniesFranchisesAndSeries() async throws {
        let h = try Harness()
        let j = try JournalHarness()
        try j.journal.addPlatform(id: 19, name: "SNES")
        h.internet.addGame(
            1, "Mega Man X",
            fields: ["involved_companies": [["developer": true, "company": ["name": "Capcom"]]], "collections": [["name": "Mega Man X"]]])
        h.internet.addGame(2, "Taz-Mania", fields: ["franchises": [["name": "Looney Tunes"]], "keywords": [["name": "metroidvania"]]])
        h.internet.addGame(3, "Capcom's Soccer Shootout")
        for (id, name) in [(1, "Mega Man X"), (2, "Taz-Mania"), (3, "Capcom's Soccer Shootout")] {
            try j.journal.addGame(platformId: 19, name: name, igdbGameId: Int64(id), igdbName: name)
        }
        let facts = try await LibraryFacts(igdb: h.igdb).byGame([1, 2, 3])

        func search(_ text: String) throws -> [String] {
            try j.journal.library(LibraryFilter(name: text), sort: .name, ascending: true, facts: facts).map(\.name)
        }

        #expect(try search("capcom") == ["Capcom's Soccer Shootout", "Mega Man X"])
        #expect(try search("looney") == ["Taz-Mania"])
        #expect(try search("man x") == ["Mega Man X"])
        #expect(try search("soccer") == ["Capcom's Soccer Shootout"])
        #expect(try search("metroidvania") == ["Taz-Mania"])
        #expect(try search("").count == 3)
    }

    @Test func yearSortUsesIGDBsReleaseYearNewestFirstUndatedLast() async throws {
        let h = try Harness()
        let j = try JournalHarness()
        try j.journal.addPlatform(id: 19, name: "SNES")
        h.internet.addGame(1, "Super Metroid", fields: ["first_release_date": 765_158_400])  // 1994
        h.internet.addGame(2, "Super Mario World", fields: ["first_release_date": 658_800_000])  // 1990
        h.internet.addGame(3, "Unreleased")
        h.internet.addGame(4, "Donkey Kong Country", fields: ["first_release_date": 785_000_000])  // 1994
        for (id, name) in [(1, "Super Metroid"), (2, "Super Mario World"), (3, "Unreleased"), (4, "Donkey Kong Country")] {
            try j.journal.addGame(platformId: 19, name: name, igdbGameId: Int64(id), igdbName: name)
        }
        try j.journal.addGameByHand(name: "Hand-made", platformId: 19)
        let facts = try await LibraryFacts(igdb: h.igdb).byGame([1, 2, 3, 4])

        func sorted(ascending: Bool) throws -> [String] {
            try j.journal.library(LibraryFilter(), sort: .year, ascending: ascending, facts: facts).map(\.name)
        }

        #expect(try sorted(ascending: false) == ["Donkey Kong Country", "Super Metroid", "Super Mario World", "Hand-made", "Unreleased"])
        #expect(try sorted(ascending: true) == ["Super Mario World", "Donkey Kong Country", "Super Metroid", "Hand-made", "Unreleased"])
        #expect(LibrarySort.year.defaultAscending)
        let rows = try j.journal.library(LibraryFilter(), sort: .name, ascending: true, facts: facts)
        #expect(rows.map(\.releaseYear) == [1994, nil, 1990, 1994, nil])  // every sort carries the year
        let plain = try j.journal.library(LibraryFilter(), sort: .name, ascending: true)
        #expect(plain.withReleaseYears(facts) == rows)
    }
}
