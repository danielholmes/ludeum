import Foundation
import Testing

@testable import LudeumCore

/// Renaming a ROM after its Game: the Game's name, keeping the ROM's tags.
@Suite struct ROMRenameNameTests {
    @Test func aROMNamedOtherwiseIsOfferedTheGamesNameWithItsTags() {
        #expect(ROMRename.newName(forROM: "Ōkami (USA)", gameName: "Okami") == "Okami (USA)")
        #expect(ROMRename.newName(forROM: "okami_usa_final", gameName: "Okami") == "Okami")
        #expect(ROMRename.newName(forROM: "MP2 (USA) (Disc 2) [!]", gameName: "Metroid Prime 2") == "Metroid Prime 2 (USA) (Disc 2) [!]")
    }

    @Test func aROMAlreadyNamedAfterItsGameBeforeItsTagsIsntOffered() {
        #expect(ROMRename.newName(forROM: "Okami (USA)", gameName: "Okami") == nil)
        #expect(ROMRename.newName(forROM: "Okami", gameName: "Okami") == nil)
        #expect(ROMRename.newName(forROM: "Okami  (USA)", gameName: "Okami") == nil)
    }

    @Test func aROMWhoseTitleOnlyStartsWithTheGamesNameIsOffered() {
        #expect(ROMRename.newName(forROM: "Okami HD (USA)", gameName: "Okami") == "Okami (USA)")
    }

    /// Once renamed, it isn't offered again, though the Game's name has a tag of its own.
    @Test func aGameNameWithItsOwnTagIsOfferedOnce() {
        #expect(ROMRename.newName(forROM: "Bar (USA)", gameName: "Foo (2008)") == "Foo (2008) (USA)")
        #expect(ROMRename.newName(forROM: "Foo (2008) (USA)", gameName: "Foo (2008)") == nil)
    }

    /// A ROM folder doesn't read a name starting with a dot: the file would be hidden.
    @Test func aGameNameStartingWithADotIsntOffered() {
        #expect(ROMRename.newName(forROM: "Hack Infection (USA)", gameName: ".hack//Infection") == nil)
    }

    /// A colon is No-Intro's " - "; a slash, which no file name can hold, is a "-".
    @Test func aGameNameIsMadeFitForAFileName() {
        #expect(ROMRename.newName(forROM: "MP2 (USA)", gameName: "Metroid Prime 2: Echoes") == "Metroid Prime 2 - Echoes (USA)")
        #expect(ROMRename.newName(forROM: "Metroid Prime 2 - Echoes (USA)", gameName: "Metroid Prime 2: Echoes") == nil)
        #expect(ROMRename.newName(forROM: "DQ (Japan)", gameName: "Dragon Quest I/II") == "Dragon Quest I-II (Japan)")
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
