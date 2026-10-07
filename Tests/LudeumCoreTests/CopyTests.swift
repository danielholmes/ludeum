import Foundation
import Testing

@testable import LudeumCore

/// Copies: the ones I record by hand, a ROM's Copy details, and what being Owned means.
@Suite struct CopyTests {
    let h: LudeumHarness
    let game: GameID

    init() throws {
        h = try LudeumHarness()
        game = try h.addGame("Chrono Trigger")
    }

    @Test func aCopyKeepsEverythingItWasGiven() throws {
        let draft = CopyDraft(
            kind: .physicalAndDigital,
            details: CopyDetails(
                regions: ["USA", "Japan"], acquiredOn: PartialDate("2019-03")!, acquiredFrom: "eBay",
                price: Price(amount: Decimal(string: "45.50")!, currency: "USD")),
            gone: Gone(on: PartialDate("2021")!, to: "A friend"))

        let id = try h.journal.addCopy(game, draft)

        #expect(try h.journal.copies(of: game) == [Copy(id: id, draft)])
    }

    @Test func aCopyCanBeEditedMadeGoneAndOwnedAgain() throws {
        let id = try h.journal.addCopy(game, CopyDraft(kind: .physical))

        try h.journal.updateCopy(id, CopyDraft(kind: .digital, gone: Gone()))
        #expect(try h.journal.copies(of: game).map(\.draft) == [CopyDraft(kind: .digital, gone: Gone())])

        try h.journal.updateCopy(id, CopyDraft(kind: .digital))
        #expect(try h.journal.copies(of: game).map(\.draft.gone) == [nil])
    }

    @Test func aCopyCantGoBeforeItWasAcquired() throws {
        let acquired = CopyDetails(acquiredOn: PartialDate("2020-05")!)

        #expect(throws: LudeumError.goneBeforeAcquired) {
            try h.journal.addCopy(game, CopyDraft(kind: .physical, details: acquired, gone: Gone(on: PartialDate("2019")!)))
        }
        // A less precise date that contains the other is fine.
        try h.journal.addCopy(game, CopyDraft(kind: .physical, details: acquired, gone: Gone(on: PartialDate("2020")!)))
        #expect(try h.journal.copies(of: game).count == 1)
    }

    @Test func copiesListOwnedBeforeGoneThenByWhenAcquired() throws {
        try h.journal.addCopy(game, CopyDraft(kind: .physical, gone: Gone()))
        try h.journal.addCopy(game, CopyDraft(kind: .digital))
        try h.journal.addCopy(game, CopyDraft(kind: .physical, details: CopyDetails(acquiredOn: PartialDate("2010")!)))

        #expect(try h.journal.copies(of: game).map(\.draft.kind) == [.physical, .digital, .physical])
        #expect(try h.journal.copies(of: game).map(\.draft.gone) == [nil, nil, Gone()])
    }

    @Test func deletingACopyIsForGood() throws {
        let id = try h.journal.addCopy(game, CopyDraft(kind: .physical))

        try h.journal.deleteCopy(id)

        #expect(try h.journal.copies(of: game).isEmpty)
    }

    @Test func aROMsRegionsComeFromItsNameAndItsDetailsCanBeEdited() throws {
        try h.journal.recordROM(game: game, fileName: "Chrono Trigger (USA, Europe).sfc", missing: false)
        let rom = try #require(try h.journal.roms(of: game).first)
        // Regions are kept in their shown order, not the name's.
        #expect(rom.details == CopyDetails(regions: ["Europe", "USA"]))

        let details = CopyDetails(regions: ["Japan"], acquiredOn: PartialDate("2024")!, acquiredFrom: "A friend", price: Price(amount: 0))
        try h.journal.setROMDetails(rom.id, details)

        #expect(try h.journal.roms(of: game).first?.details == details)
    }

    @Test func goodToolsRegionCodesAreSpelledOut() throws {
        try h.journal.recordROM(game: game, fileName: "Chrono Trigger (UE) [!].sfc", missing: false)
        try h.journal.recordROM(game: game, fileName: "Chrono Trigger.sfc", missing: true)

        #expect(try h.journal.roms(of: game).map(\.details.regions) == [["Europe", "USA"], []])
    }

    @Test func regionSuggestionsAreTheUsualOnesThenAnyOtherIveUsed() throws {
        try h.journal.addCopy(game, CopyDraft(kind: .physical, details: CopyDetails(regions: ["Korea", "USA"])))
        try h.journal.recordROM(game: game, fileName: "Chrono Trigger (Brazil).sfc", missing: false)

        #expect(try h.journal.regionSuggestions() == Regions.suggested + ["Brazil", "Korea"])
    }

    @Test func acquiredFromSuggestionsAreMostUsedFirst() throws {
        for from in ["eBay", "Cash Converters", "eBay"] {
            try h.journal.addCopy(game, CopyDraft(kind: .physical, details: CopyDetails(acquiredFrom: from)))
        }
        try h.journal.addCopy(game, CopyDraft(kind: .physical))

        #expect(try h.journal.acquiredFromSuggestions() == ["eBay", "Cash Converters"])
    }
}

/// Owned, Owned as a ROM, Owned only as a non-ROM Copy and Not owned, in the Library.
@Suite struct OwnedTests {
    let h: LudeumHarness
    let romOnly: GameID
    let both: GameID
    let copyOnly: GameID
    let goneOnly: GameID
    let nothing: GameID

    init() throws {
        h = try LudeumHarness()
        romOnly = try h.addGame("ROM only")
        both = try h.addGame("Both")
        copyOnly = try h.addGame("Copy only")
        goneOnly = try h.addGame("Gone only")
        nothing = try h.addGame("Nothing")
        // A missing ROM is still a Copy.
        try h.journal.recordROM(game: romOnly, fileName: "r.sfc", missing: true)
        try h.journal.recordROM(game: both, fileName: "b.sfc", missing: false)
        try h.journal.addCopy(both, CopyDraft(kind: .physical))
        try h.journal.addCopy(copyOnly, CopyDraft(kind: .digital))
        try h.journal.addCopy(goneOnly, CopyDraft(kind: .physical, gone: Gone()))
    }

    private func names(_ owned: OwnedFilter?) throws -> [String] {
        try h.journal.library(LibraryFilter(owned: owned), sort: .name, ascending: true).map(\.name)
    }

    @Test func theOwnedFilter() throws {
        #expect(try names(nil) == ["Both", "Copy only", "Gone only", "Nothing", "ROM only"])
        #expect(try names(.owned) == ["Both", "Copy only", "ROM only"])
        #expect(try names(.asROM) == ["Both", "ROM only"])
        #expect(try names(.onlyNonROM) == ["Copy only"])
        #expect(try names(.notOwned) == ["Gone only", "Nothing"])
    }

    @Test func eachRowSaysWhetherItsOwned() throws {
        let rows = try h.journal.library(LibraryFilter(), sort: .name, ascending: true)

        #expect(rows.map(\.owned) == [true, true, false, false, true])
        #expect(rows.map(\.roms) == [.playable, .noROMs, .noROMs, .noROMs, .missing])
    }
}
