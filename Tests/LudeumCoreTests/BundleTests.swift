import Foundation
import Testing

@testable import LudeumCore

/// Adding a Bundle from IGDB, with the contents IGDB lists for it.
@Suite struct AddingBundlesTests {
    let h: Harness
    let j: LudeumHarness
    let snes = IGDBPlatform(id: 19, name: "SNES")

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        let platforms: [[String: Any]] = [["id": 19, "name": "SNES"]]
        h.internet.addGame(5199, "Super Mario All-Stars", fields: ["game_type": 3, "platforms": platforms])
        h.internet.addGame(222095, "Super Mario Bros.", fields: ["game_type": 9, "bundles": [5199]])
        h.internet.addGame(222099, "Super Mario Bros. 3", fields: ["game_type": 9, "bundles": [5199]])
    }

    var search: GameSearch { GameSearch(igdb: h.igdb, journal: j.journal) }

    @Test func aBundlesContentsSayWhichAreAlreadyGames() async throws {
        try j.journal.addPlatform(id: 19, name: "SNES")
        let smb3 = try j.journal.addGame(platformId: 19, name: "Super Mario Bros. 3", igdbGameId: 222099, igdbName: "Super Mario Bros. 3")
        let result = try #require(try await search.result(igdbGameId: 5199))
        #expect(result.isBundle)

        let contents = try await search.bundleContents(of: result, on: snes)

        #expect(contents.map(\.name) == ["Super Mario Bros.", "Super Mario Bros. 3"])
        #expect(contents.map(\.game) == [nil, smb3])
    }

    @Test func addingABundleAddsTheContentsChosenAndLinksTheGamesThereAlready() async throws {
        try j.journal.addPlatform(id: 19, name: "SNES")
        let smb3 = try j.journal.addGame(platformId: 19, name: "Super Mario Bros. 3", igdbGameId: 222099, igdbName: "Super Mario Bros. 3")
        let result = try #require(try await search.result(igdbGameId: 5199))
        let contents = try await search.bundleContents(of: result, on: snes)

        let bundle = try search.addBundle(result, on: snes, contents: contents)

        #expect(try j.journal.game(bundle).isBundle)
        #expect(try j.journal.game(bundle).igdbGameId == 5199)
        let games = try j.journal.bundleGames(bundle)
        #expect(games.map(\.name) == ["Super Mario Bros.", "Super Mario Bros. 3"])
        #expect(games.map(\.igdbGameId) == [222095, 222099])
        #expect(games.map(\.platformId) == [19, 19])
        #expect(games[1].id == smb3)
    }
}

/// Bundles (ADR 0016): one release of several games, whose Copies are Copies of every Game it contains.
@Suite struct BundleTests {
    let h: LudeumHarness
    let allStars: GameID
    let smb: GameID
    let smb3: GameID

    init() throws {
        h = try LudeumHarness()
        _ = try h.addGame("Super Metroid")
        allStars = try h.journal.addBundle(platformId: 19, name: "Super Mario All-Stars")
        smb = try h.addGame("Super Mario Bros.")
        smb3 = try h.addGame("Super Mario Bros. 3")
        try h.journal.addToBundle(allStars, smb)
        try h.journal.addToBundle(allStars, smb3)
    }

    private func library(_ filter: LibraryFilter = LibraryFilter()) throws -> [String] {
        try h.journal.library(filter, sort: .name, ascending: true).map(\.name)
    }

    @Test func theLibraryListsTheGamesNotTheBundle() throws {
        #expect(try library() == ["Super Mario Bros.", "Super Mario Bros. 3", "Super Metroid"])
        #expect(try h.journal.platformCounts().map(\.games) == [3])
        #expect(try h.journal.game(allStars).isBundle)
        #expect(try !h.journal.game(smb).isBundle)
    }

    @Test func aBundleListsItsGamesAndAGameItsBundles() throws {
        let deluxe = try h.journal.addBundle(platformId: 19, name: "Mario Deluxe Pack")
        try h.journal.addToBundle(deluxe, smb3)

        #expect(try h.journal.bundleGames(allStars).map(\.name) == ["Super Mario Bros.", "Super Mario Bros. 3"])
        #expect(try h.journal.bundles(containing: smb3).map(\.name) == ["Super Mario All-Stars", "Mario Deluxe Pack"])
        #expect(try h.journal.bundles(containing: smb).map(\.id) == [allStars])
    }

    @Test func playOpensAGamesOwnROMBeforeItsBundles() throws {
        try h.journal.recordROM(game: allStars, fileName: "Super Mario All-Stars (USA).sfc", missing: false)
        #expect(try h.journal.romsToPlay(of: smb).map(\.fileName) == ["Super Mario All-Stars (USA).sfc"])

        try h.journal.recordROM(game: smb, fileName: "Super Mario Bros. (World).nes", missing: false)
        #expect(
            try h.journal.romsToPlay(of: smb).map(\.fileName) == [
                "Super Mario Bros. (World).nes", "Super Mario All-Stars (USA).sfc",
            ])
    }

    @Test func aPlaythroughCanBePlayedOnABundlesCopy() throws {
        let copy = try h.journal.addCopy(allStars, CopyDraft(kind: .physical))

        try h.journal.addPlaythrough(smb, PlaythroughDraft(start: PartialDate("2024")!, copy: .copy(copy)))

        #expect(try h.journal.playthroughs(smb).map(\.draft.copy) == [.copy(copy)])
        #expect(throws: LudeumError.copyNotOfGame) {
            try h.journal.addPlaythrough(
                try h.addGame("Super Metroid II"), PlaythroughDraft(start: PartialDate("2024")!, copy: .copy(copy)))
        }
    }

    @Test func aGameCantBeDeletedWhileABundleContainsIt() throws {
        #expect(try !h.journal.deletionSummary(smb).canDelete)
        #expect(throws: LudeumError.gameInBundle) { try h.journal.deleteGame(smb) }

        try h.journal.removeFromBundle(allStars, smb)

        #expect(try h.journal.deletionSummary(smb).canDelete)
        try h.journal.deleteGame(smb)
        #expect(try h.journal.bundleGames(allStars).map(\.name) == ["Super Mario Bros. 3"])
    }

    @Test func aGameCantLeaveABundleWhileAPlaythroughOfItWasPlayedOnTheBundlesCopy() throws {
        try h.journal.recordROM(game: allStars, fileName: "Super Mario All-Stars (USA).sfc", missing: false)
        let rom = try #require(try h.journal.roms(of: allStars).first)
        try h.journal.addPlaythrough(smb, PlaythroughDraft(start: PartialDate("2024")!, copy: .rom(rom.id)))

        #expect(throws: LudeumError.copyPlayedOn) { try h.journal.removeFromBundle(allStars, smb) }
        // Another Game of the Bundle can still leave.
        try h.journal.removeFromBundle(allStars, smb3)
        #expect(try h.journal.bundleGames(allStars).map(\.name) == ["Super Mario Bros."])
    }

    @Test func deletingABundleLeavesItsGames() throws {
        try h.journal.deleteGame(allStars)

        #expect(try h.journal.bundles(containing: smb).isEmpty)
        #expect(try library() == ["Super Mario Bros.", "Super Mario Bros. 3", "Super Metroid"])
    }

    @Test func searchingABundlesNameFindsItsGames() throws {
        #expect(try library(LibraryFilter(name: "all-stars")) == ["Super Mario Bros.", "Super Mario Bros. 3"])
        #expect(try library(LibraryFilter(name: "all-stars 3")) == ["Super Mario Bros. 3"])
    }

    @Test func aBundlesCopyMakesItsGamesOwned() throws {
        try h.journal.addCopy(allStars, CopyDraft(kind: .physical))

        #expect(try library(LibraryFilter(copies: .onlyNonROM)) == ["Super Mario Bros.", "Super Mario Bros. 3"])
        #expect(try library(LibraryFilter(copies: .notOwned)) == ["Super Metroid"])
    }

    @Test func aBundlesROMMakesItsGamesOwnedAsAROMAndPlayable() throws {
        try h.journal.recordROM(game: allStars, fileName: "Super Mario All-Stars (USA).sfc", missing: false)

        let rows = try h.journal.library(LibraryFilter(copies: .hasROM), sort: .name, ascending: true)
        #expect(rows.map(\.name) == ["Super Mario Bros.", "Super Mario Bros. 3"])
        #expect(rows.map(\.roms) == [.playable, .playable])
        #expect(try library(LibraryFilter(roms: .playable)) == ["Super Mario Bros.", "Super Mario Bros. 3"])
    }

    @Test func aGoneBundleCopyLeavesItsGamesNotOwned() throws {
        try h.journal.addCopy(allStars, CopyDraft(kind: .physical, gone: Gone()))

        #expect(try library(LibraryFilter(copies: .notOwned)) == ["Super Mario Bros.", "Super Mario Bros. 3", "Super Metroid"])
        #expect(try library(LibraryFilter(copies: .noCopies)) == ["Super Metroid"])
    }
}
