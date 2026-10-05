import Testing

@testable import LudeumCore

@Suite struct ROMNameTests {
    @Test func theVersionIsTheTagsAsWrittenWithoutDumpFlags() {
        #expect(ROMName("Super Metroid (Japan, USA) (En,Ja)").version == "Japan, USA · En,Ja")
        #expect(ROMName("Zelda (U) (V1.1) [!]").version == "U · V1.1")
        #expect(ROMName("Tetris (World) (Rev A) (Beta)").version == "World · Rev A · Beta")
        #expect(ROMName("Kirby's Dream Land").version == "")
    }

    @Test func aTranslationSuffixIsPartOfTheVersion() {
        #expect(ROMName("Sweet Home (Japan) - English patch").version == "Japan · English patch")
        #expect(ROMName("Sweet Home (Japan) [T+Eng1.0]").version == "Japan · T+Eng1.0")
    }

    @Test func fileArtefactsAreNotPartOfTheVersion() {
        #expect(ROMName("Metroid II (USA) 2").version == "USA")
        #expect(ROMName("Spider-Man and the X-Men in Arcade's Revenge (U) 2").version == "U")
    }

    @Test func theDiscAndItsLabelAreParsedOutOfTheVersion() {
        let name = ROMName("Resident Evil 2 - Dual Shock Ver. (USA) (Disc 2) (Claire)")
        #expect(name.disc == 2)
        #expect(name.discLabel == "Claire")
        #expect(name.version == "USA")
        #expect(ROMName("Gran Turismo 2 (USA) (Disc 1) (Arcade Mode) (Rev 1)").version == "USA · Rev 1")
    }

    @Test func regionsComeFromNoIntroAndGoodToolsTags() {
        #expect(ROMName("Holy Diver (Japan)").regions == [.japan])
        #expect(ROMName("Soccer (E) (M3) [S][!]").regions == [.europe])
        #expect(ROMName("Tetris (World)").regions == [.japan, .usa, .europe])
        #expect(ROMName("Feed_IT_Souls_v1.4").regions == nil)
    }
}
