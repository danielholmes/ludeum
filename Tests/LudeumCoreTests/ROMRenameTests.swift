import Foundation
import Testing

@testable import LudeumCore

/// The name Rename offers: No-Intro's (Redump's on disc Platforms), from the Game's name, the ROM's Regions and what
/// else its name says about its Version and Disc.
@Suite struct ROMRenameNameTests {
    func offered(_ rom: String, _ game: String, _ regions: [String] = [], on platform: Int64 = 19) -> String? {
        ROMRename.newName(forROM: rom, gameName: game, regions: regions, platformId: platform)
    }

    @Test func theRegionTagIsTheROMsRegionsNotItsNames() {
        #expect(offered("Super Mario World (U)", "Super Mario World", ["USA"]) == "Super Mario World (USA)")
        #expect(offered("Tanglewood", "Tanglewood", ["Europe"]) == "Tanglewood (Europe)")
        #expect(offered("Tony Hawk's Underground (UE)", "Tony Hawk's Underground", ["Europe"]) == "Tony Hawk's Underground (Europe)")
    }

    @Test func aROMWithNoRegionsHasNoRegionTag() {
        #expect(offered("Gods (E)", "Gods") == "Gods")
        #expect(offered("Gods", "Gods") == nil)
    }

    @Test func aROMAlreadyWithItsNameIsntOffered() {
        #expect(offered("Okami (USA)", "Okami", ["USA"]) == nil)
        #expect(offered("Legend of Zelda, The - Spirit Tracks (USA)", "The Legend of Zelda: Spirit Tracks", ["USA"]) == nil)
    }

    /// Once renamed, it isn't offered again, though the Game's name has a tag of its own.
    @Test func aGameNameWithItsOwnTagIsOfferedOnce() {
        #expect(offered("Bar (USA)", "Foo (2008)", ["USA"]) == "Foo (2008) (USA)")
        #expect(offered("Foo (2008) (USA)", "Foo (2008)", ["USA"]) == nil)
    }

    /// A leading article moves to the end of the main title, before any subtitle; one starting a subtitle stays.
    @Test func aLeadingArticleMovesToTheEndOfTheMainTitle() {
        #expect(offered("Zelda ST", "The Legend of Zelda: Spirit Tracks") == "Legend of Zelda, The - Spirit Tracks")
        #expect(offered("Zelda", "Zelda: A Link to the Past") == "Zelda - A Link to the Past")
        #expect(offered("Fievel", "An American Tail: Fievel Goes West") == "American Tail, An - Fievel Goes West")
        #expect(offered("Blob", "A Boy and His Blob") == "Boy and His Blob, A")
        #expect(offered("Theme", "Theme Park") == "Theme Park")
    }

    /// No-Intro's names are ASCII: accents go, and so do symbols, though a letter of another script stays.
    @Test func aGameNameIsWrittenInASCIIWhereItCanBe() {
        #expect(offered("Okami HD", "Ōkami") == "Okami")
        #expect(offered("Snap", "Pokémon Snap") == "Pokemon Snap")
        #expect(offered("THPS", "Tony Hawk’s Pro Skater™") == "Tony Hawk's Pro Skater")
        #expect(offered("Ranma", "Ranma ½: Hard Battle") == "Ranma 1-2 - Hard Battle")
        #expect(offered("Zelda", "ゼルダの伝説") == "ゼルダの伝説")
    }

    /// A colon is " - "; the characters No-Intro forbids are dropped, though one joining two words is a "-".
    @Test func charactersNoIntroForbidsAreDropped() {
        #expect(offered("MP2", "Metroid Prime 2: Echoes") == "Metroid Prime 2 - Echoes")
        #expect(offered("Roger", "Who Framed Roger Rabbit?") == "Who Framed Roger Rabbit")
        #expect(offered("Qbert", "Q*bert") == "Q-bert")
        #expect(offered("DQ", "Dragon Quest I/II") == "Dragon Quest I-II")
        #expect(offered("Ys", #"Ys "Book" <I>"#) == "Ys Book I")
    }

    /// A ROM folder doesn't read a name starting with a dot: the file would be hidden.
    @Test func aGameNameStartingWithADotIsntOffered() {
        #expect(offered("Hack Infection (USA)", ".hack//Infection", ["USA"]) == nil)
    }

    /// Dump flags and scene language counts go; a bad dump, a hack, a trainer and a translation stay, last.
    @Test func dumpFlagsGoButWhatSaysWhatsInTheFileStays() {
        #expect(offered("Super Mario World (U) [!]", "Super Mario World", ["USA"]) == "Super Mario World (USA)")
        #expect(offered("Zelda (U) [a1][o2][f1][p1][!]", "Zelda", ["USA"]) == "Zelda (USA)")
        #expect(offered("Zelda (U) [T+Eng1.0][h1C][b1][t2]", "Zelda", ["USA"]) == "Zelda (USA) [h1C] [b1] [t2] [T+Eng1.0]")
        #expect(offered("Soccer (E) (M3) [S][!]", "Soccer", ["Europe"]) == "Soccer (Europe)")
        #expect(offered("Ape Escape (U) [SCUS-94423]", "Ape Escape", ["USA"], on: 7) == "Ape Escape (USA)")
    }

    @Test func languagesAreKeptInNoIntrosOrder() {
        #expect(offered("Godzilla (USA) (De,En,Fr)", "Godzilla", ["USA"]) == "Godzilla (USA) (En,Fr,De)")
        #expect(offered("Q-bert (Japan, USA) (En)", "Q-bert", ["Japan", "USA"]) == nil)
    }

    /// GoodTools' V1.1 is No-Intro's Rev 1; its V1.0 has no tag.
    @Test func goodToolsVersionsAreNoIntrosRevs() {
        #expect(offered("Mortal Kombat II (U) (V1.1)", "Mortal Kombat II", ["USA"]) == "Mortal Kombat II (USA) (Rev 1)")
        #expect(offered("Jurassic Park (V1.0) (U)", "Jurassic Park", ["USA"]) == "Jurassic Park (USA)")
        #expect(offered("Pac-Man (USA) (v1.1)", "Pac-Man", ["USA"]) == nil)
    }

    /// GoodTools' PRG1 on NES is No-Intro's Rev 1, and its region codes can be in square brackets or in any order.
    @Test func moreGoodToolsTagsAreRead() {
        #expect(
            offered("Legend of Zelda, The (U) (PRG1) [!]", "The Legend of Zelda", ["USA"], on: 18) == "Legend of Zelda, The (USA) (Rev 1)")
        #expect(offered("Point Blank [SLUS-00481] [U] [bin+cue]", "Point Blank", ["USA"], on: 7) == "Point Blank (USA) [bin+cue]")
        #expect(offered("Urban Strike (UEJ) [!]", "Urban Strike", ["USA", "Europe", "Japan"]) == "Urban Strike (World)")
        #expect(offered("Pang (A)", "Pang", ["Australia"]) == "Pang (Australia)")
        #expect(offered("Pang (HK) (C)", "Pang", ["Hong Kong"]) == "Pang (Hong Kong)")
    }

    @Test func noIntrosOwnEditionTagsArePlaced() throws {
        let standard = try #require(
            ROMRename.standardName(
                forROM: "Assassin's Creed II - Discovery (DSi Enhanced) (US)(M3)(XenoPhobia)", gameName: "Assassin's Creed II: Discovery",
                regions: ["USA"], platformId: 20))
        #expect(standard.name() == "Assassin's Creed II - Discovery (USA) (DSi Enhanced) (XenoPhobia)")
        #expect(standard.unplacedTags == ["(XenoPhobia)"])
        #expect(offered("Pong (USA) (WiiWare)", "Pong", ["USA"], on: 5) == nil)
        #expect(offered("Pong (USA) (PSN)", "Pong", ["USA"], on: 38) == nil)
    }

    /// Region, Languages, Disc and its label, Version, development status, then the rest.
    @Test func tagsAreInTheirOrder() {
        #expect(
            offered("Tetris (Beta) (SGB Enhanced) (Rev A) (W)", "Tetris", ["World"]) == "Tetris (World) (Rev A) (Beta) (SGB Enhanced)")
        #expect(
            offered("GT2 (USA) (Rev 1) (Disc 1) (Arcade Mode)", "Gran Turismo 2", ["USA"], on: 7)
                == "Gran Turismo 2 (USA) (Disc 1) (Arcade Mode) (Rev 1)")
        #expect(offered("FF (Disc 2) (Europe) (Fr,En)", "Final Fantasy", ["Europe"], on: 7) == "Final Fantasy (Europe) (En,Fr) (Disc 2)")
        #expect(
            offered("Resident Evil 2 (Disc 2) (Claire) (USA)", "Resident Evil 2", ["USA"], on: 7)
                == "Resident Evil 2 (USA) (Disc 2) (Claire)")
    }

    /// A translation patch named after the tags stays; a copy number or other file artefact goes.
    @Test func whatFollowsTheTagsStaysOnlyWhenItsATranslation() {
        #expect(offered("Sweet Home (J) - English patch", "Sweet Home", ["Japan"]) == "Sweet Home (Japan) - English patch")
        #expect(offered("Metroid II (USA) 2", "Metroid II", ["USA"]) == "Metroid II (USA)")
    }

    /// A scene group's tag and an edition's can't be told apart, so they're kept unless dropped.
    @Test func aTagItCantPlaceIsKeptUnlessDropped() throws {
        let standard = try #require(
            ROMRename.standardName(
                forROM: "Broken Sword - Director's Cut (US)(M5)(BAHAMUT)", gameName: "Broken Sword: Director's Cut", regions: ["USA"],
                platformId: 20))
        #expect(standard.unplacedTags == ["(BAHAMUT)"])
        #expect(standard.name() == "Broken Sword - Director's Cut (USA) (BAHAMUT)")
        #expect(standard.name(dropping: ["(BAHAMUT)"]) == "Broken Sword - Director's Cut (USA)")
        #expect(offered("Broken Sword - Director's Cut (USA)", "Broken Sword: Director's Cut", ["USA"], on: 20) == nil)
        #expect(offered("Broken Sword - Director's Cut (USA) (BAHAMUT)", "Broken Sword: Director's Cut", ["USA"], on: 20) == nil)
    }

    /// No-Intro's order, as its names have it: Japan, USA, Europe, then the rest alphabetically; all three are World.
    @Test func regionsAreInNoIntrosOrderAndSpelling() {
        #expect(offered("Kirby", "Kirby", ["Europe", "USA"]) == "Kirby (USA, Europe)")
        #expect(offered("Kirby", "Kirby", ["USA", "Japan"]) == "Kirby (Japan, USA)")
        #expect(offered("Kirby", "Kirby", ["Europe", "USA", "Japan"]) == "Kirby (World)")
        #expect(offered("Kirby", "Kirby", ["Korea", "World"]) == "Kirby (World, Korea)")
        #expect(offered("Kirby", "Kirby", ["Europe", "Australia"]) == "Kirby (Europe, Australia)")
        #expect(offered("Kirby", "Kirby", ["Spain", "PAL", "Europe"]) == "Kirby (Europe, PAL, Spain)")
        #expect(offered("Kirby", "Kirby", ["USA", "Canada"]) == "Kirby (USA)")
        #expect(offered("Kirby", "Kirby", ["Japan", "USA", "Europe", "Canada"]) == "Kirby (World)")
        #expect(offered("Kirby", "Kirby", ["UK"]) == "Kirby (United Kingdom)")
    }

    /// The region tag it wrote is read back as one, whatever Regions it names, so it isn't offered again.
    @Test func aNameWithItsRegionTagIsntOfferedAgain() {
        #expect(offered("Kirby (United Kingdom)", "Kirby", ["UK"]) == nil)
        #expect(offered("Kirby (Europe, PAL)", "Kirby", ["Europe", "PAL"]) == nil)
        #expect(offered("Kirby (World, Korea)", "Kirby", ["Korea", "World"]) == nil)
        #expect(offered("Tekken 3 (UK, Australia)", "Tekken 3", ["UK", "Australia"], on: 7) == nil)
        #expect(offered("Kirby (Greece)", "Kirby", ["Europe"]) == "Kirby (Europe)")
    }

    /// Redump's: USA before Japan, Canada beside USA, and the UK as "UK".
    @Test func aDiscPlatformsRegionsAreInRedumpsOrderAndSpelling() {
        #expect(offered("Tekken 3", "Tekken 3", ["Japan", "USA"], on: 7) == "Tekken 3 (USA, Japan)")
        #expect(offered("Tekken 3", "Tekken 3", ["USA", "Canada"], on: 7) == "Tekken 3 (USA, Canada)")
        #expect(offered("Tekken 3", "Tekken 3", ["Australia", "United Kingdom"], on: 7) == "Tekken 3 (UK, Australia)")
        #expect(offered("Tekken 3", "Tekken 3", ["Europe", "USA", "Japan"], on: 7) == "Tekken 3 (World)")
    }
}

/// Renaming a ROM in its ROM folder, in whatever form it's kept, and in the journal, where it stays the same ROM.
@Suite struct ROMRenameTests {
    let h: LudeumHarness
    let okami: GameID

    init() throws {
        h = try LudeumHarness()
        try h.journal.addPlatform(id: ROMPlatform.ps2, name: "PlayStation 2")
        okami = try h.journal.addGame(platformId: ROMPlatform.ps2, name: "Okami")
    }

    /// The Game's one ROM, recorded as its ROM folder has it: Okami's, unless another Game is given.
    func record(_ name: String, in folder: FakeROMFolder, of game: GameID? = nil) throws -> LudeumROM {
        let game = game ?? okami
        try h.journal.recordROM(game: game, fileName: "\(name).iso", missing: false)
        let rom = try #require(try h.journal.roms(of: game).first)
        try h.journal.checkROMAgain(rom.id, in: folder.folder)
        return try #require(try h.journal.rom(rom.id))
    }

    func names(in folder: FakeROMFolder) throws -> [String] {
        try FileManager.default.subpathsOfDirectory(atPath: folder.url.path(percentEncoded: false)).sorted()
    }

    @Test func aLooseFileIsRenamedAndStaysTheSameROM() throws {
        let ps2 = try FakeROMFolder(in: h.directory)
        try ps2.add("Ōkami (USA).iso", "game")
        let rom = try record("Ōkami (USA)", in: ps2)

        try h.journal.renameROM(rom.id, to: "Okami (USA)", in: ps2.folder)

        #expect(try names(in: ps2) == ["Okami (USA).iso"])
        let renamed = try #require(try h.journal.roms(of: okami).first)
        #expect(renamed.id == rom.id)
        #expect(renamed.folderName == "Okami (USA)")
        #expect(renamed.fileName == "Okami (USA).iso")
        #expect(!renamed.missing)
    }

    /// What's inside keeps its names: a cue sheet or playlist names its tracks and Discs by file name.
    @Test func aSubfolderIsRenamedWithWhatsInsideLeftAlone() throws {
        let ps2 = try FakeROMFolder(in: h.directory)
        try ps2.add("Ōkami (USA)/Ōkami (USA).iso", "game")
        let rom = try record("Ōkami (USA)", in: ps2)

        try h.journal.renameROM(rom.id, to: "Okami (USA)", in: ps2.folder)

        #expect(try names(in: ps2) == ["Okami (USA)", "Okami (USA)/Ōkami (USA).iso"])
        let renamed = try #require(try h.journal.rom(rom.id))
        #expect(renamed.subfolder == "Okami (USA)")
        #expect(renamed.fileName == "Okami (USA)/Ōkami (USA).iso")
    }

    @Test func anArchivedROMsArchiveIsRenamed() throws {
        let ps2 = try FakeROMFolder(in: h.directory)
        try ps2.add("Ōkami (USA).7z", "packed")
        let rom = try record("Ōkami (USA)", in: ps2)

        try h.journal.renameROM(rom.id, to: "Okami (USA)", in: ps2.folder)

        #expect(try names(in: ps2) == ["Okami (USA).7z"])
        let renamed = try #require(try h.journal.rom(rom.id))
        #expect(renamed.archived)
        #expect(renamed.fileName == "Okami (USA).7z")
    }

    @Test func aCompactedROMsArchiveIsRenamedAndStillPlaysEvenWhenOnlyItsCaseChanges() throws {
        try h.journal.addPlatform(id: 33, name: "Game Boy")
        let tetris = try h.journal.addGame(platformId: 33, name: "Tetris")
        let gameBoy = try FakeROMFolder(in: h.directory, platform: 33)
        try gameBoy.add("TETRIS (World) (Rev 1).7z", "packed")
        let rom = try record("TETRIS (World) (Rev 1)", in: gameBoy, of: tetris)

        try h.journal.renameROM(rom.id, to: "Tetris (World) (Rev 1)", in: gameBoy.folder)

        #expect(try names(in: gameBoy) == ["Tetris (World) (Rev 1).7z"])
        let renamed = try #require(try h.journal.rom(rom.id))
        #expect(!renamed.archived)
        #expect(renamed.fileName == "Tetris (World) (Rev 1).7z")
    }

    @Test func aROMInBothFormsHasBothRenamed() throws {
        let ps2 = try FakeROMFolder(in: h.directory)
        try ps2.add("Ōkami (USA)/Ōkami (USA).iso", "game")
        try ps2.add("Ōkami (USA).7z", "packed")
        let rom = try record("Ōkami (USA)", in: ps2)

        try h.journal.renameROM(rom.id, to: "Okami (USA)", in: ps2.folder)

        #expect(try names(in: ps2) == ["Okami (USA)", "Okami (USA).7z", "Okami (USA)/Ōkami (USA).iso"])
    }

    @Test func aLooseROMsCompactedZipBesideItIsRenamedToo() throws {
        try h.journal.addPlatform(id: 4, name: "Nintendo 64")
        let mario = try h.journal.addGame(platformId: 4, name: "Super Mario 64")
        let n64 = try FakeROMFolder(in: h.directory, platform: 4)
        try n64.add("SM64 (USA).z64", "game")
        try n64.add("SM64 (USA).zip", "packed")
        let rom = try record("SM64 (USA)", in: n64, of: mario)

        try h.journal.renameROM(rom.id, to: "Super Mario 64 (USA)", in: n64.folder)

        #expect(try names(in: n64) == ["Super Mario 64 (USA).z64", "Super Mario 64 (USA).zip"])
    }

    /// Anything else of its name, a save or a format its Emulator prefers less, would otherwise be found as a new ROM.
    @Test func everyOtherFileOfTheROMsNameIsRenamedToo() throws {
        let ps2 = try FakeROMFolder(in: h.directory)
        try ps2.add("Ōkami (USA).iso", "game")
        try ps2.add("Ōkami (USA).chd", "game")
        try ps2.add("Ōkami (USA).sav", "save")
        try ps2.add("Ōkami (USA) (Demo).iso", "demo")
        let rom = try record("Ōkami (USA)", in: ps2)

        try h.journal.renameROM(rom.id, to: "Okami (USA)", in: ps2.folder)

        #expect(try names(in: ps2) == ["Okami (USA).chd", "Okami (USA).iso", "Okami (USA).sav", "Ōkami (USA) (Demo).iso"])
    }

    /// A loose cue sheet names its tracks inside it, so they keep their names.
    @Test func aLooseCueSheetIsRenamedWithItsTracksLeftAlone() throws {
        try h.journal.addPlatform(id: 7, name: "PlayStation")
        let vagrant = try h.journal.addGame(platformId: 7, name: "Vagrant Story")
        let ps1 = try FakeROMFolder(in: h.directory, platform: 7)
        try ps1.add("VS (USA).cue", #"FILE "VS (USA).bin" BINARY"#)
        try ps1.add("VS (USA).bin", "track")
        let rom = try record("VS (USA)", in: ps1, of: vagrant)

        try h.journal.renameROM(rom.id, to: "Vagrant Story (USA)", in: ps1.folder)

        #expect(try names(in: ps1) == ["VS (USA).bin", "Vagrant Story (USA).cue"])
        #expect(try ps1.folder.scan().map(\.name) == ["Vagrant Story (USA)"])
    }

    @Test func aNameAnotherROMHasIsRefusedWithNothingMoved() throws {
        let ps2 = try FakeROMFolder(in: h.directory)
        try ps2.add("Ōkami (USA).iso", "game")
        try ps2.add("Okami (USA).7z", "another")
        let rom = try record("Ōkami (USA)", in: ps2)

        #expect(throws: ReviewError.alreadyInROMFolder) { try h.journal.renameROM(rom.id, to: "Okami (USA)", in: ps2.folder) }

        #expect(try names(in: ps2) == ["Okami (USA).7z", "Ōkami (USA).iso"])
        #expect(try h.journal.rom(rom.id)?.folderName == "Ōkami (USA)")
    }

    /// A missing ROM keeps its name in the journal, so its file can still come back to it.
    @Test func aNameAMissingROMHasIsRefusedWithNothingMoved() throws {
        let ps2 = try FakeROMFolder(in: h.directory)
        try ps2.add("Ōkami (USA).iso", "game")
        let rom = try record("Ōkami (USA)", in: ps2)
        try h.journal.recordROM(game: okami, fileName: "Okami (USA).iso", missing: true)

        #expect(throws: ReviewError.alreadyInROMFolder) { try h.journal.renameROM(rom.id, to: "Okami (USA)", in: ps2.folder) }

        #expect(try names(in: ps2) == ["Ōkami (USA).iso"])
    }

    @Test func aNameAMissingROMHasInAnotherCaseIsRefused() throws {
        let ps2 = try FakeROMFolder(in: h.directory)
        try ps2.add("Ōkami (USA).iso", "game")
        let rom = try record("Ōkami (USA)", in: ps2)
        try h.journal.recordROM(game: okami, fileName: "okami (usa).iso", missing: true)

        #expect(throws: ReviewError.alreadyInROMFolder) { try h.journal.renameROM(rom.id, to: "Okami (USA)", in: ps2.folder) }

        #expect(try names(in: ps2) == ["Ōkami (USA).iso"])
    }

    /// Its ROM folder wouldn't find it again: a hidden file, say.
    @Test func aNameItsROMFolderWouldntReadIsRefusedWithNothingMoved() throws {
        let ps2 = try FakeROMFolder(in: h.directory)
        try ps2.add("Ōkami (USA).iso", "game")
        let rom = try record("Ōkami (USA)", in: ps2)

        #expect(throws: ROMRenameError.unreadableName) { try h.journal.renameROM(rom.id, to: ".Okami (USA)", in: ps2.folder) }
        #expect(throws: ROMRenameError.unreadableName) { try h.journal.renameROM(rom.id, to: "", in: ps2.folder) }

        #expect(try names(in: ps2) == ["Ōkami (USA).iso"])
        #expect(try h.journal.rom(rom.id)?.missing == false)
    }
}
