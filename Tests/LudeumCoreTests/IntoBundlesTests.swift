import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// `into-bundles`: the one-off move of the Games that were really Bundles into Bundles, and of the Copies recorded once
/// per Game of a box into a Bundle made by hand.
@Suite struct IntoBundlesTests {
    let h: Harness
    let j: LudeumHarness
    let backups: Backups
    let allStars: GameID
    let redAlert: GameID
    let aftermath: GameID

    static let pc = 6

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        backups = Backups(folder: j.directory.appending(path: "Backups"), clock: j.clock)
        h.internet.addGame(5199, "Super Mario All-Stars", fields: ["game_type": 3])
        h.internet.addGame(222095, "Super Mario Bros.", fields: ["bundles": [5199]])
        h.internet.addGame(222099, "Super Mario Bros. 3", fields: ["bundles": [5199]])
        try j.journal.addPlatform(id: 19, name: "SNES")
        try j.journal.addPlatform(id: Int64(Self.pc), name: "PC")
        allStars = try j.journal.addGame(platformId: 19, name: "Super Mario All-Stars", igdbGameId: 5199, igdbName: "Super Mario All-Stars")
        redAlert = try j.journal.addGame(platformId: Int64(Self.pc), name: "Red Alert", igdbGameId: 295, igdbName: "Red Alert")
        aftermath = try j.journal.addGame(platformId: Int64(Self.pc), name: "The Aftermath", igdbGameId: 652, igdbName: "The Aftermath")
    }

    static let spec = IntoBundles.Spec(
        fromGames: [5199],
        byHand: [
            .init(
                name: "Red Alert compilation", games: [295, 652],
                copy: CopyDraft(kind: .physical, details: CopyDetails(acquiredFrom: "Game Wizards"), gone: Gone()),
                replacing: "Game Wizards, compilation")
        ])

    var intoBundles: IntoBundles { IntoBundles(journal: j.journal, igdb: h.igdb, backups: backups, spec: Self.spec) }

    @Test func aGameBecomesABundleOfItsIGDBContentsKeepingItsCopies() async throws {
        try j.journal.recordROM(game: allStars, fileName: "Super Mario All-Stars (USA).sfc", missing: false)
        try j.journal.addCopy(allStars, CopyDraft(kind: .physical))

        try await intoBundles.run(try await intoBundles.plan())

        #expect(try j.journal.game(allStars).isBundle)
        #expect(try j.journal.bundleGames(allStars).map(\.name) == ["Super Mario Bros.", "Super Mario Bros. 3"])
        #expect(try j.journal.bundleGames(allStars).map(\.platformId) == [19, 19])
        #expect(try j.journal.roms(of: allStars).count == 1)
        #expect(try j.journal.copies(of: allStars).count == 1)
        let smb = try #require(try j.journal.bundleGames(allStars).first)
        #expect(try j.journal.romsToPlay(of: smb.id).count == 1)
        #expect(try backups.all().map(\.operation) == [.beforeIntoBundles])
    }

    @Test func aRatingIsDroppedAndSaidSo() async throws {
        try j.journal.setRating(allStars, Rating(tenths: 90))

        let plan = try await intoBundles.plan()
        #expect(plan.bundles.first { $0.name == "Super Mario All-Stars" }?.droppedRating == Rating(tenths: 90))
        try await intoBundles.run(plan)

        #expect(try j.journal.ratingHistory(allStars).isEmpty)
    }

    @Test func aGameWithPlaythroughsOrIntentIsAProblemAndNothingChanges() async throws {
        try j.journal.addPlaythrough(allStars, PlaythroughDraft(start: PartialDate("2024")!))
        try j.journal.setChildhood(allStars, true)

        let plan = try await intoBundles.plan()

        #expect(plan.problems == ["Super Mario All-Stars has Playthroughs", "Super Mario All-Stars has Childhood"])
        #expect(!plan.isRunnable)
        await #expect(throws: IntoBundles.NotRunnable.self) { try await intoBundles.run(plan) }
        #expect(try !j.journal.game(allStars).isBundle)
    }

    @Test func aBoxRecordedOncePerGameBecomesABundleMadeByHandWithOneCopy() async throws {
        try j.journal.addCopy(redAlert, CopyDraft(kind: .physical, details: CopyDetails(acquiredFrom: "Electronics Boutique")))
        try j.journal.addCopy(
            redAlert, CopyDraft(kind: .physical, details: CopyDetails(acquiredFrom: "Game Wizards, compilation (RA)"), gone: Gone()))
        try j.journal.addCopy(
            aftermath, CopyDraft(kind: .physical, details: CopyDetails(acquiredFrom: "Game Wizards, compilation (RA)"), gone: Gone()))

        try await intoBundles.run(try await intoBundles.plan())

        let bundle = try #require(try j.journal.bundles(containing: redAlert).first)
        #expect(bundle.name == "Red Alert compilation")
        #expect(bundle.igdbGameId == nil)
        #expect(bundle.platformId == Int64(Self.pc))
        #expect(try j.journal.bundleGames(bundle.id).map(\.id) == [redAlert, aftermath])
        #expect(
            try j.journal.copies(of: bundle.id).map(\.draft)
                == [CopyDraft(kind: .physical, details: CopyDetails(acquiredFrom: "Game Wizards"), gone: Gone())])
        #expect(try j.journal.copies(of: redAlert).map(\.draft.details.acquiredFrom) == ["Electronics Boutique"])
        #expect(try j.journal.copies(of: aftermath).isEmpty)
    }

    @Test func aGameInTwoBundlesIsAddedOnce() async throws {
        h.internet.addGame(5200, "Mario Pack", fields: ["game_type": 3])
        h.internet.addGame(222095, "Super Mario Bros.", fields: ["bundles": [5199, 5200]])
        let pack = try j.journal.addGame(platformId: 19, name: "Mario Pack", igdbGameId: 5200, igdbName: "Mario Pack")
        let spec = IntoBundles.Spec(fromGames: [5199, 5200])
        let intoBundles = IntoBundles(journal: j.journal, igdb: h.igdb, backups: backups, spec: spec)

        try await intoBundles.run(try await intoBundles.plan())

        let smb = try #require(try j.journal.bundleGames(pack).first)
        #expect(try j.journal.bundles(containing: smb.id).map(\.id) == [allStars, pack])
        #expect(try j.journal.games(igdbGameId: 222095).count == 1)
    }

    @Test func runningAgainChangesNothing() async throws {
        try await intoBundles.run(try await intoBundles.plan())

        let again = try await intoBundles.plan()

        #expect(again.bundles.isEmpty)
        #expect(again.done == ["Super Mario All-Stars", "Red Alert compilation"])
    }
}
