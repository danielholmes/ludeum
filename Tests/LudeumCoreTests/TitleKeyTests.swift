import Testing

@testable import LudeumCore

/// The title keys a Game's names find its LaunchBox game by: two names match when a key of each is the same.
@Suite struct TitleKeyTests {
    func sameTitle(_ a: String, _ b: String) -> Bool { TitleKey.title.of(a) == TitleKey.title.of(b) }
    func sameLooseTitle(_ a: String, _ b: String) -> Bool { TitleKey.loose.of(a) == TitleKey.loose.of(b) }

    @Test func tagsArentPartOfTheTitle() {
        #expect(sameTitle("Super Metroid (Japan, USA) (En) [!]", "Super Metroid"))
        #expect(!sameTitle("Final Fantasy III (USA)", "Final Fantasy VI"))
    }

    @Test func articlesAndAmpersandsDontStopAMatch() {
        #expect(sameTitle("The Legend of Zelda", "Legend of Zelda, The (USA)"))
        #expect(sameTitle("Banjo and Kazooie", "Banjo _ Kazooie (USA)"))
        #expect(sameTitle("Banjo & Kazooie", "Banjo and Kazooie"))
    }

    @Test func anArticleBeforeTheSubtitleDoesntStopAMatch() {
        let noIntro = "Legend of Zelda, The - Phantom Hourglass (USA) (En,Fr,Es)"
        #expect(sameTitle("Legend of Zelda - Phantom Hourglass, The (U)", noIntro))
        #expect(sameTitle("The Legend of Zelda: Phantom Hourglass", noIntro))
        #expect(sameTitle("Lord of the Rings, The - Two Towers, The (U)", "Lord of the Rings, The - The Two Towers (USA)"))
    }

    @Test func smallWordsAnotherNameLeavesOutOnlyMatchLoosely() {
        let noIntro = "Spider-Man - X-Men - Arcade's Revenge (USA, Europe)"
        #expect(!sameTitle("Spider-Man and the X-Men in Arcade's Revenge", noIntro))
        #expect(sameLooseTitle("Spider-Man and the X-Men in Arcade's Revenge", noIntro))
        #expect(
            sameLooseTitle(
                "Simpsons, The - Itchy & Scratchy in Miniature Golf Madness (USA)",
                "Simpsons, The - Itchy _ Scratchy - Miniature Golf Madness (USA, Europe)"))
    }

    @Test func accentsAreDroppedAndUmlautsAndMacronsCanBeSpelledOut() {
        #expect(sameTitle("Ōkami", "Okami (USA)"))
        #expect(sameTitle(TitleKey.spelledOut("Ōkami"), "Ookami (USA)"))
        #expect(sameTitle(TitleKey.spelledOut("Einhänder"), "Einhaender (USA)"))
        #expect(sameTitle(TitleKey.spelledOut("München"), "Muenchen (Germany)"))
    }

    @Test func copyRegionsReadAsROMRegionsDo() {
        #expect(ROMName.regions(named: ["Australia"]) == [.europe])
        #expect(ROMName.regions(named: ["USA", "Japan"]) == [.usa, .japan])
        #expect(ROMName.regions(named: ["Asia"]) == nil)
    }
}
