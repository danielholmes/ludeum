import Testing

@testable import LudeumCore

@Suite struct LibretroLookupTests {
    func find(_ fileName: String, titles: [String] = [], in names: Set<String>) -> String? {
        LibretroLookup.find(fileName: fileName, titles: titles, in: names)
    }

    @Test func theFileNameMinusItsExtensionMatchesExactly() {
        #expect(
            find("Super Metroid (Japan, USA) (En).sfc", in: ["Super Metroid (Japan, USA) (En)", "Super Metroid (Europe)"])
                == "Super Metroid (Japan, USA) (En)")
        #expect(find("Metroid Prime (USA).nkit.iso", in: ["Metroid Prime (USA)"]) == "Metroid Prime (USA)")
    }

    @Test func libretrosSubstitutionsApply() {
        #expect(
            find("Ren & Stimpy Show, The - Buckeroo$! (USA).sfc", in: ["Ren _ Stimpy Show, The - Buckeroo$! (USA)"])
                == "Ren _ Stimpy Show, The - Buckeroo$! (USA)")
    }

    @Test func goodToolsTagsAreRewritten() {
        #expect(
            find("Super Mario Kart (U) [!].smc", in: ["Super Mario Kart (USA)", "Super Mario Kart (Europe)"]) == "Super Mario Kart (USA)")
        #expect(find("Zelda (UE) (V1.1) [C][!].gb", in: ["Zelda (USA, Europe) (Rev 1)"]) == "Zelda (USA, Europe) (Rev 1)")
    }

    @Test func aMultiDiscROMUsesItsDisclessName() {
        let names: Set = ["Parasite Eve II (USA)", "Parasite Eve II (USA) (Disc 2)"]
        #expect(find("Parasite Eve II (USA) (Disc 2).cue", in: names) == "Parasite Eve II (USA)")
    }

    @Test func aFloppySetsDiskUsesItsDisklessName() {
        let names: Set = ["Snatcher (Japan)", "Snatcher (Japan) (Disk 2)"]
        #expect(find("Snatcher (Japan) (Disk 2).dsk", in: names) == "Snatcher (Japan)")
    }

    @Test func aFuzzyTitleMatchPrefersTheROMsOwnRegion() {
        let names: Set = ["Rayman DS (USA)", "Rayman DS (Europe) (En,Fr,De)", "Rayman DS (Japan)"]
        #expect(find("Rayman DS (E).nds", in: names) == "Rayman DS (Europe) (En,Fr,De)")
    }

    @Test func withNoRegionOfItsOwnUSAThenEuropeThenJapanWin() {
        #expect(
            find("Vagrant Story.cue", in: ["Vagrant Story (Japan)", "Vagrant Story (Europe)", "Vagrant Story (USA)"])
                == "Vagrant Story (USA)")
        #expect(find("Vagrant Story.cue", in: ["Vagrant Story (Japan)", "Vagrant Story (Europe)"]) == "Vagrant Story (Europe)")
    }

    @Test func prereleasesAreNeverFuzzyMatches() {
        #expect(find("Star Fox 2.sfc", in: ["Star Fox 2 (Japan) (Proto)"]) == nil)
    }

    @Test func articlesAndAmpersandsDontStopAFuzzyMatch() {
        #expect(find("The Legend of Zelda.nes", in: ["Legend of Zelda, The (USA)"]) == "Legend of Zelda, The (USA)")
        #expect(find("Banjo and Kazooie.z64", in: ["Banjo _ Kazooie (USA)"]) == "Banjo _ Kazooie (USA)")
    }

    @Test func otherTitlesAreTriedLast() {
        let names: Set = ["Final Fantasy III (USA)", "Final Fantasy VI (Japan)"]
        #expect(find("ff3us.smc", titles: ["Final Fantasy III"], in: names) == "Final Fantasy III (USA)")
        #expect(find("ff3us.smc", titles: ["Nope", "Final Fantasy III"], in: names) == "Final Fantasy III (USA)")
    }

    @Test func aTitleWithUmlautsOrMacronsMatchesTheirSpelledOutForm() {
        #expect(
            find("Einhander.7z", titles: ["Einhander", "Einhänder"], in: ["Einhaender (USA)", "Einhaender (Japan)"])
                == "Einhaender (USA)")
        #expect(find("Okami (USA).7z", titles: ["Okami", "Ōkami"], in: ["Ookami (USA)"]) == "Ookami (USA)")
        #expect(find("Munchen.7z", titles: ["München"], in: ["Muenchen (Germany)"]) == "Muenchen (Germany)")
    }

    @Test func aTitlesAccentsDroppedStillWinsOverTheirSpelledOutForm() {
        #expect(find("x.7z", titles: ["Ōkami"], in: ["Okami HD (USA)", "Okami (USA)", "Ookami (Japan)"]) == "Okami (USA)")
    }

    @Test func everyTitleIsTriedWithItsAccentsDroppedBeforeAnyIsSpelledOut() {
        #expect(find("Ökö.7z", titles: ["Eco"], in: ["Oekoe (Germany)", "Eco (USA)"]) == "Eco (USA)")
    }

    @Test func homebrewFindsNothing() {
        #expect(find("Hermano_1.1_jam.gb", titles: ["Hermano"], in: ["Hermie Hopperhead (Japan)"]) == nil)
    }
}

/// A Game with no ROM: titles alone, with its Copies' Regions for the region.
@Suite struct LibretroTitleLookupTests {
    let names: Set = ["Gran Turismo (USA)", "Gran Turismo (Europe) (En,Fr,De,Es,It)", "Gran Turismo (Japan) (Demo 1)"]

    func find(_ titles: [String], regions: Set<NameRegion> = [], in names: Set<String>) -> String? {
        LibretroLookup.fuzzy(titles: titles, regions: regions, in: LibretroLookup.titleIndex(names))
    }

    @Test func withNoRegionsUSAWins() {
        #expect(find(["Gran Turismo"], in: names) == "Gran Turismo (USA)")
    }

    @Test func itsRegionsWin() {
        #expect(find(["Gran Turismo"], regions: [.europe], in: names) == "Gran Turismo (Europe) (En,Fr,De,Es,It)")
    }

    @Test func eachTitleIsTriedInTurn() {
        #expect(find(["GT", "Gran Turismo"], in: names) == "Gran Turismo (USA)")
        #expect(find(["Gran Turismo 2"], in: names) == nil)
    }

    @Test func umlautsMatchTheirSpelledOutForm() {
        #expect(find(["Einhänder"], regions: [.japan], in: ["Einhaender (USA)", "Einhaender (Japan)"]) == "Einhaender (Japan)")
    }

    @Test func copyRegionsReadAsROMRegionsDo() {
        #expect(ROMName.regions(named: ["Australia"]) == [.europe])
        #expect(ROMName.regions(named: ["USA", "Japan"]) == [.usa, .japan])
        #expect(ROMName.regions(named: ["Asia"]) == nil)
    }
}
