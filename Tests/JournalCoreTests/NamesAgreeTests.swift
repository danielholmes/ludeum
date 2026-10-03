import Testing

@testable import JournalCore

@Suite struct NamesAgreeTests {
    func game(_ name: String, alt: [(String, String)] = [], localizations: [(String, Int)] = []) -> IGDBGame {
        IGDBGame(
            id: 1,
            record: .object([
                "name": .string(name),
                "alternative_names": .array(alt.map { .object(["name": .string($0.0), "comment": .string($0.1)]) }),
                "game_localizations": .array(localizations.map { .object(["name": .string($0.0), "region": .number(Double($0.1))]) }),
            ]))
    }

    func agree(_ rom: String, _ g: IGDBGame, title: String? = nil) -> Bool {
        namesAgree(romName: rom, openVGDBTitle: title, game: g)
    }

    @Test func equalNamesAfterNormalisingAgree() {
        #expect(agree("Lost Vikings, The (U) [!]", game("The Lost Vikings")))
        #expect(agree("Asterix and the Power of the Gods (Europe) (En,Fr,De,Es)", game("Astérix and the Power of the Gods")))
        #expect(agree("Baseball Stars II (USA)", game("Baseball Stars 2")))
        #expect(agree("Choplifter II - Rescue & Survive (E) [!]", game("Choplifter II: Rescue Survive")))
        #expect(agree("King of Dragons (USA)", game("The King of Dragons")))
        #expect(agree("Toy Story (Europe)", game("Disney's Toy Story")))
        #expect(agree("007 - The World Is Not Enough (USA)", game("James Bond 007: The World Is Not Enough")))
    }

    @Test func aPrefixNeverAgrees() {
        #expect(!agree("Super Star Wars - Return of the Jedi (USA)", game("Super Star Wars")))
        #expect(!agree("Battletoads-Double Dragon (USA)", game("Battletoads")))
    }

    @Test func iVAndXStayWords() {
        #expect(!agree("Final Fantasy V (Japan)", game("Final Fantasy 5")))
    }

    @Test func titleAndSubtitleMaySwap() {
        #expect(agree("Super Mario Advance 2 - Super Mario World (U) [!]", game("Super Mario World: Super Mario Advance 2")))
    }

    @Test func aTildeSeparatesAlternativeTitles() {
        #expect(
            agree(
                "QuackShot Starring Donald Duck ~ QuackShot - I Love Donald Duck - Guruzia Ou no Hihou (World) (v1.1)",
                game("QuackShot Starring Donald Duck")))
    }

    @Test func fileArtefactsAreIgnored() {
        #expect(agree("Feed_IT_Souls_v1.4", game("Feed It Souls")))
        #expect(agree("grimacebday v.1.7", game("Grimacebday")))
        #expect(agree("Colin McRae Rally 2 # GBA", game("Colin McRae Rally 2")))
        #expect(agree("0173 - Harry Potter (Europe)", game("Harry Potter")))
        #expect(agree("Metroid Prime (USA).nkit", game("Metroid Prime")))
        #expect(agree("Earthbound (USA) - bofner patch", game("EarthBound")))
    }

    @Test func openVGDBsTitleCountsToo() {
        #expect(agree("RSHAKE", game("Resident Evil"), title: "Resident Evil"))
    }

    @Test func alternativeNamesAndLocalizationsAgree() {
        #expect(agree("Sonic Chaos (E) [!]", game("Sonic the Hedgehog Chaos", alt: [("Sonic Chaos", "Other")])))
        #expect(agree("Pocket Monsters (Japan)", game("Pokémon Red", localizations: [("Pocket Monsters", 3)])))
    }

    @Test func aRegionalNameOnlyAgreesForThatRegionsROMs() {
        let lilo2 = game("Disney's Lilo & Stitch 2: Hämsterviel Havoc", alt: [("Lilo & Stitch", "Japanese title - translated")])
        #expect(!agree("Lilo & Stitch (USA)", lilo2))
        #expect(agree("Lilo & Stitch (Japan)", lilo2))
        #expect(agree("Lilo & Stitch", lilo2))
        let football = game("Football International", localizations: [("Soccer", 4)])
        #expect(agree("Soccer (Europe)", football))
        #expect(!agree("Soccer (Japan)", football))
    }
}
