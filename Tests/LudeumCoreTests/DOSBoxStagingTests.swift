import CryptoKit
import Foundation
import GRDB
import Testing

@testable import LudeumCore

private func put(_ text: String, at file: URL) throws {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)
}

private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

/// How a DOS ROM, a subfolder of drives, reads in its ROM folder (ADR 0042).
@Suite struct DOSROMTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "dos rom \(UUID().uuidString)", directoryHint: .isDirectory)

    @Test func dosIsPlayedInDOSBoxStaging() {
        #expect(Emulator.of(platformId: ROMPlatform.dos) == .dosBoxStaging)
        #expect(Emulator.dosBoxStaging.isLudeums)
        #expect(ROMPlatform.all[ROMPlatform.dos]?.folderName == "DOS")
    }

    @Test func aSubfolderWithFilesOnItsDriveCIsAROMOpenedByItsDrive() throws {
        let dos = try FakeROMFolder(in: directory, platform: ROMPlatform.dos)
        try dos.add("Commander Keen (1990)/C/KEEN1/KEEN1.EXE")
        try dos.add("Commander Keen (1990)/C/KEEN1/LEVEL01.CK1")

        let rom = try #require(try dos.folder.scan().first)
        #expect(rom.name == "Commander Keen (1990)")
        #expect(rom.ready?.lastPathComponent == "C")
        #expect(rom.fileName == "Commander Keen (1990)/C")
        #expect(try dos.folder.files(named: rom.name).count == 2)
    }

    @Test func aCDGameWithNoDriveCOpensAtDisc1() throws {
        let dos = try FakeROMFolder(in: directory, platform: ROMPlatform.dos)
        try dos.add("Cricket 96 (1995)/CD/Cricket 96 (Disc 2).cue")
        let disc1 = try dos.add("Cricket 96 (1995)/CD/Cricket 96 (Disc 1).cue")

        #expect(try dos.folder.scan().first?.ready == disc1)
    }

    @Test func aGamesOwnBINsAndIMGsOnDriveCArentDiscs() throws {
        let dos = try FakeROMFolder(in: directory, platform: ROMPlatform.dos)
        try dos.add("Hero Quest (1991)/C/QUEST1.BIN")
        try dos.add("Hero Quest (1991)/C/MAPS.IMG")
        try dos.add("Hero Quest (1991)/C/HERO.EXE")

        #expect(try dos.folder.scan().first?.ready?.lastPathComponent == "C")
    }

    @Test func noLooseFileIsAROMAndNeitherIsAFolderWithoutDrives() throws {
        let dos = try FakeROMFolder(in: directory, platform: ROMPlatform.dos)
        try dos.add("Loose (1995).iso")
        try dos.add("Not Shaped (1992)/GAME.EXE")
        try dos.add("Empty Drive (1993)/C/.DS_Store")
        try FileManager.default.createDirectory(at: dos.url.appending(path: "Empty Drive (1993)/CD"), withIntermediateDirectories: true)

        #expect(try dos.folder.scan().isEmpty)
    }

    @Test func itsArchiveIsTheROMArchived() throws {
        let dos = try FakeROMFolder(in: directory, platform: ROMPlatform.dos)
        try dos.add("Wolfenstein 3D (1992).7z")

        let rom = try #require(try dos.folder.scan().first)
        #expect(rom.archived)
    }

    @Test func onlyFindersFilesAreClutter() {
        let folder = ROMFolder.platform(ROMPlatform.dos, directory)!

        #expect(folder.isClutter("C/.DS_Store"))
        #expect(folder.isClutter("C/._KEEN1.EXE"))
        #expect(!folder.isClutter("C/README.TXT"))
        #expect(!folder.isClutter("C/TITLE.PNG"))
    }

    @Test func noChecksumIsTaken() async throws {
        let dos = try FakeROMFolder(in: directory, platform: ROMPlatform.dos)
        try dos.add("Keen (1990)/C/KEEN1.EXE")
        let rom = try #require(try dos.folder.scan().first)

        #expect(await ROMChecksum.read(rom, platformId: ROMPlatform.dos, sevenZip: nil, isOnDisk: { _ in true }) == .noDump)
    }
}

/// What's picked to Add as a DOS ROM (ADR 0042).
@Suite struct DOSROMSourceTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "dos source \(UUID().uuidString)", directoryHint: .isDirectory)

    @discardableResult
    func file(_ path: String) throws -> URL {
        let url = directory.appending(path: path)
        try put("x", at: url)
        return url
    }

    func folder(_ path: String) -> URL { directory.appending(path: path, directoryHint: .isDirectory) }

    @Test func aGamesFolderIsReadAsDOSsByItsProgram() async throws {
        try file("Keen/KEEN1.EXE")
        try file("Keen/LEVEL01.CK1")

        #expect(try await ROMSource([folder("Keen")]).platforms(sevenZip: nil) == [ROMPlatform.dos])
    }

    @Test func aFolderAlreadyOfDrivesIsDOSsAlone() async throws {
        try file("Cricket/CD/Cricket.iso")

        #expect(try await ROMSource([folder("Cricket")]).platforms(sevenZip: nil) == [ROMPlatform.dos])
    }

    @Test func aFolderPickedWithItsDiscsIsOneGameNamedForTheFolder() async throws {
        try file("Cricket 96/CRICKET.EXE")
        let cue = try file("Cricket 96.cue")
        let bin = try file("Cricket 96.bin")

        let sources = await ROMSource.split([cue, folder("Cricket 96"), bin])

        #expect(sources.count == 1)
        #expect(sources[0].romName == "Cricket 96")
        #expect(try await sources[0].platforms(sevenZip: nil) == [ROMPlatform.dos])
    }

    @Test func aFolderWithNoProgramIsntPickedWithDiscs() async throws {
        try file("Okami/Okami.iso")
        let cue = try file("Other.cue")

        #expect(await ROMSource.split([folder("Okami"), cue]).count == 2)
    }

    @Test func aDiscImageIsDOSsTooButNeverPresumedSo() async throws {
        let source = ROMSource([try file("Game.iso")])
        let platforms = try await source.platforms(sevenZip: nil)

        #expect(platforms.contains(ROMPlatform.dos))
        #expect(source.likeliestPlatform(of: platforms) != ROMPlatform.dos)
    }
}

/// Adding a DOS ROM, laid out as its drives (ADR 0042).
@Suite struct DOSAddROMTests {
    let j: LudeumHarness
    let directory = FileManager.default.temporaryDirectory.appending(path: "dos add \(UUID().uuidString)", directoryHint: .isDirectory)
    let picked: URL

    init() throws {
        j = try LudeumHarness()
        picked = directory.appending(path: "Downloads", directoryHint: .isDirectory)
    }

    var adder: AddROM { AddROM(journal: j.journal, sevenZip: SevenZip.find(), moveToTrash: { _ in }) }

    @discardableResult
    func pick(_ path: String) throws -> URL {
        let url = picked.appending(path: path)
        try put("x", at: url)
        return url
    }

    func add(_ urls: [URL], named name: String) async throws -> FakeROMFolder {
        let dos = try FakeROMFolder(in: directory, platform: ROMPlatform.dos)
        try await adder.add(ROMSource(urls), to: dos.folder, match: .byHand(name: name), keepingOriginals: true)
        return dos
    }

    func tree(_ dos: FakeROMFolder) throws -> [String] {
        try FileManager.default.subpathsOfDirectory(atPath: dos.url.path(percentEncoded: false)).filter {
            (try? dos.url.appending(path: $0).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted()
    }

    @Test func aGamesFolderBecomesDriveC() async throws {
        try pick("Keen/KEEN1.EXE")
        try pick("Keen/SAVES/.DS_Store")
        try pick("Keen/README.TXT")

        let dos = try await add([picked.appending(path: "Keen", directoryHint: .isDirectory)], named: "Commander Keen")

        #expect(try tree(dos) == ["Keen/C/KEEN1.EXE", "Keen/C/README.TXT"])
        let row = try j.journal.db.read { try Row.fetchOne($0, sql: "SELECT fileName, md5, crc FROM rom") }
        #expect(row?["fileName"] as String? == "Keen/C")
        #expect(row?["crc"] as String? == nil)
    }

    @Test func discsGoInCDWithACueSheetsTracks() async throws {
        let cue = try pick("Cricket 96.cue")
        try put("FILE \"Cricket 96.bin\" BINARY\n", at: cue)
        try pick("Cricket 96.bin")

        let dos = try await add([cue], named: "Cricket 96")

        #expect(try tree(dos) == ["Cricket 96/CD/Cricket 96.bin", "Cricket 96/CD/Cricket 96.cue"])
    }

    @Test func aFolderWithItsDiscsIsBothDrives() async throws {
        try pick("Cricket 96/CRICKET.EXE")
        let iso = try pick("Cricket 96.iso")

        let dos = try await add([picked.appending(path: "Cricket 96", directoryHint: .isDirectory), iso], named: "Cricket 96")

        #expect(try tree(dos) == ["Cricket 96/C/CRICKET.EXE", "Cricket 96/CD/Cricket 96.iso"])
    }

    @Test func aFolderAlreadyOfDrivesGoesInAsItIs() async throws {
        try pick("Doom/C/DOOM/DOOM.EXE")
        try pick("Doom/CD/Doom.iso")

        let dos = try await add([picked.appending(path: "Doom", directoryHint: .isDirectory)], named: "Doom")

        #expect(try tree(dos) == ["Doom/C/DOOM/DOOM.EXE", "Doom/CD/Doom.iso"])
    }

    @Test func aFolderOfDiscsAloneIsAGamesDiscs() async throws {
        try pick("Rebel Assault/Rebel Assault.iso")

        let dos = try await add([picked.appending(path: "Rebel Assault", directoryHint: .isDirectory)], named: "Rebel Assault")

        #expect(try tree(dos) == ["Rebel Assault/CD/Rebel Assault.iso"])
    }

    @Test func aFolderOfDiscsWithAReadmeIsStillAGamesDiscs() async throws {
        try pick("Rebel Assault/Rebel Assault.iso")
        try pick("Rebel Assault/README.TXT")

        let dos = try await add([picked.appending(path: "Rebel Assault", directoryHint: .isDirectory)], named: "Rebel Assault")

        #expect(try tree(dos) == ["Rebel Assault/CD/README.TXT", "Rebel Assault/CD/Rebel Assault.iso"])
    }
}

/// Which files in a DOS ROM's `CD/` are its Discs, the same for finding the ROM as for its Play (ADR 0042).
@Suite struct DOSDiscTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "dos discs \(UUID().uuidString)", directoryHint: .isDirectory)

    @Test func discsThatDontSayWhichTheyAreAreInNameOrder() throws {
        let dos = try FakeROMFolder(in: directory, platform: ROMPlatform.dos)
        let a = try dos.add("Game/CD/Install.iso")
        let b = try dos.add("Game/CD/Play.iso")

        #expect(try dos.folder.scan().first?.ready == a)
        #expect(ROMFolder.cdDiscs(among: [b, a]) == [a, b])
    }

    @Test func aCueSheetsOwnImageIsntADiscOfItsOwn() throws {
        let dos = try FakeROMFolder(in: directory, platform: ROMPlatform.dos)
        let cue = try dos.add("Game/CD/Game.cue", "FILE \"Game.iso\" BINARY\n")
        let iso = try dos.add("Game/CD/Game.iso")

        #expect(ROMFolder.cdDiscs(among: [iso, cue]) == [cue])
    }
}

/// Archiving and Unarchiving a DOS ROM, whose empty folders go with it (ADR 0042).
@Suite(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
struct DOSArchiveTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "dos archive \(UUID().uuidString)", directoryHint: .isDirectory)
    let trash: URL

    init() throws {
        trash = directory.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    var archiver: ROMArchiver {
        let trash = trash
        return ROMArchiver(
            sevenZip: SevenZip.find()!,
            moveToTrash: { try FileManager.default.moveItem(at: $0, to: trash.appending(path: UUID().uuidString)) })
    }

    @Test func itComesBackWithItsEmptyFoldersAndWithoutFindersFiles() async throws {
        let dos = try FakeROMFolder(in: directory, platform: ROMPlatform.dos)
        try dos.add("Keen (1990)/C/KEEN1/KEEN1.EXE", "keen")
        try dos.add("Keen (1990)/C/KEEN1/.DS_Store")
        try dos.add("Keen (1990)/CD/Keen.iso", "iso")
        try FileManager.default.createDirectory(at: dos.url.appending(path: "Keen (1990)/C/SAVES"), withIntermediateDirectories: true)

        try await archiver.archive("Keen (1990)", in: dos.folder)
        #expect(try dos.folder.scan().first?.archived == true)
        try await archiver.unarchive(dos.url.appending(path: "Keen (1990).7z"), romName: "Keen (1990)", in: dos.folder)

        let rom = try #require(try dos.folder.scan().first)
        #expect(rom.ready?.lastPathComponent == "C")
        #expect(exists(dos.url.appending(path: "Keen (1990)/C/SAVES")))
        #expect(exists(dos.url.appending(path: "Keen (1990)/CD/Keen.iso")))
        #expect(!exists(dos.url.appending(path: "Keen (1990)/C/KEEN1/.DS_Store")))
    }
}

/// The programs a DOS Game can start with, and how (ADR 0042).
@Suite struct DOSProgramTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "dos programs \(UUID().uuidString)", directoryHint: .isDirectory)

    @Test func onlyNamesDOSKnowsAsTheyAreAreShort() {
        #expect(DOSPrograms.isShortName("KEEN1.EXE"))
        #expect(DOSPrograms.isShortName("setup.bat"))
        #expect(DOSPrograms.isShortName("SIERRA"))
        #expect(DOSPrograms.isShortName("A_B~1.COM"))
        #expect(!DOSPrograms.isShortName("Keen 1 (1990)"))
        #expect(!DOSPrograms.isShortName("TOOLONGNAME.EXE"))
        #expect(!DOSPrograms.isShortName("GAME.EXEC"))
        #expect(!DOSPrograms.isShortName("A.B.C"))
    }

    @Test func theProgramsOnDriveCAreItsAndItsGameSavesLessWhatsDeleted() throws {
        let c = directory.appending(path: "C", directoryHint: .isDirectory)
        let save = directory.appending(path: "Save", directoryHint: .isDirectory)
        try put("", at: c.appending(path: "KEEN1/KEEN1.EXE"))
        try put("", at: c.appending(path: "KEEN1/install.bat"))
        try put("", at: c.appending(path: "KEEN1/OLD.COM"))
        try put("", at: c.appending(path: "KEEN1/LEVEL01.CK1"))
        try put("", at: c.appending(path: "Long Name/GAME.EXE"))
        try put("", at: save.appending(path: "KEEN2/KEEN2.EXE"))
        try put("", at: save.appending(path: "KEEN1/DBOVERLAY_DEL_OLD.COM"))

        #expect(DOSPrograms.on(c: c, gameSave: save) == ["KEEN1\\INSTALL.BAT", "KEEN1\\KEEN1.EXE", "KEEN2\\KEEN2.EXE"])
    }

    @Test func aProgramIsStartedFromItsFolderAndABatchFileCalled() {
        #expect(DOSPrograms.commands(starting: "KEEN1\\KEEN1.EXE") == ["C:", "CD \\KEEN1", "KEEN1.EXE"])
        #expect(DOSPrograms.commands(starting: "SIERRA\\KQ5\\KQ5.BAT") == ["C:", "CD \\SIERRA\\KQ5", "CALL KQ5.BAT"])
        #expect(DOSPrograms.commands(starting: "GAME.COM") == ["C:", "CD \\", "GAME.COM"])
    }

    @Test func aGameKeepsItsProgram() throws {
        let h = try LudeumHarness()
        try h.journal.addPlatform(id: ROMPlatform.dos, name: "DOS")
        let game = try h.journal.addGame(platformId: ROMPlatform.dos, name: "Keen")

        try h.journal.setEmulatorSettings(game, EmulatorSettings(dosProgram: "KEEN1\\KEEN1.EXE"))

        #expect(try h.journal.emulatorSettings(game).dosProgram == "KEEN1\\KEEN1.EXE")
    }
}

/// Playing a DOS Game in DOSBox Staging (ADR 0042).
@Suite struct DOSBoxStagingPlayTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "dosbox play \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: directory.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var dosBoxStaging: DOSBoxStagingSettings { DOSBoxStagingSettings(ludeum: ludeum) }
    let name = "Commander Keen (1990)"

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    func install() throws {
        let executable = ludeum.dosBoxStagingApp.appending(path: "Contents/MacOS/dosbox")
        try put("", at: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
        try put("sf2", at: ludeum.dosBoxStagingSoundFont)
    }

    func dos(c: Bool = true, discs: [String] = []) throws -> FakeROMFolder {
        let dos = try FakeROMFolder(in: directory, platform: ROMPlatform.dos)
        if c { try dos.add("\(name)/C/KEEN1/KEEN1.EXE") }
        for disc in discs { try dos.add("\(name)/CD/\(disc)") }
        return dos
    }

    func press(
        _ dos: FakeROMFolder, settings: EmulatorSettings = .init(), prompt: Bool = false, open: DOSBoxStagingsOpen = .none
    ) throws -> Play.Outcome {
        let rom = try #require(try dos.folder.scan().first)
        let journal = LudeumROM(
            id: 1, folderName: name, platformId: ROMPlatform.dos, fileName: rom.fileName, name: name, version: "", disc: nil,
            missing: false,
            archived: false)
        // Another DOSBox Staging being open (`running`) isn't what stops a Play: only one playing this ROM is.
        return Play(platformId: ROMPlatform.dos, platformName: "DOS", roms: [journal], settings: settings)
            .prepare(
                locator: ROMLocator(romFolders: [dos.folder]), version: .ok, app: { _ in nil }, prompt: prompt,
                dosBoxStaging: dosBoxStaging,
                running: { _ in true }, dosBoxStagingsOpen: open)
    }

    /// The `-c` commands of a command line, in order.
    func commands(_ outcome: Play.Outcome) -> [String] {
        let arguments = outcome.arguments ?? []
        return arguments.indices.filter { arguments[$0] == "-c" && $0 + 1 < arguments.count }.map { arguments[$0 + 1] }
    }

    func path(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    @Test func itsRefusedUntilDOSBoxStagingIsInstalled() throws {
        #expect(try press(try dos()).refusal == .notInstalled(.dosBoxStaging))
    }

    @Test func itMountsDriveCWithItsGameSaveOverItAndStartsItsProgram() throws {
        try install()
        let dos = try dos()

        let outcome = try press(dos, settings: EmulatorSettings(dosProgram: "KEEN1\\KEEN1.EXE"))

        guard case .open(let app, let arguments, _, _, let environment) = outcome else {
            Issue.record("refused: \(String(describing: outcome.refusal))")
            return
        }
        #expect(app == ludeum.dosBoxStagingApp)
        #expect(environment == ["HOME": ludeum.dosBoxStagingHome.path(percentEncoded: false)])
        #expect(Array(arguments.prefix(4)) == ["--noprimaryconf", "--nolocalconf", "--conf", path(ludeum.dosBoxStagingStanding)])
        #expect(arguments.last == "--exit")
        #expect(
            commands(outcome) == [
                "mount c \"\(path(dos.url.appending(path: "\(name)/C")))\"",
                "mount c \"\(path(ludeum.dosGameSave(ofROM: name)))\" -t overlay",
                "C:", "CD \\KEEN1", "KEEN1.EXE",
            ])
        #expect(exists(ludeum.dosGameSave(ofROM: name)))
        #expect(exists(ludeum.dosBoxStagingHome.appending(path: "Library/Preferences")))
    }

    @Test func theStandingSettingsPlayGeneralMIDIWithTheSoundFont() throws {
        try install()

        _ = try press(try dos())

        let standing = try String(contentsOf: ludeum.dosBoxStagingStanding, encoding: .utf8).components(separatedBy: "\n")
        #expect(standing.contains("mididevice = fluidsynth"))
        #expect(standing.contains("soundfont = \(ludeum.dosBoxStagingSoundFont.path(percentEncoded: false))"))
        #expect(standing.contains("soundfont_dir = \(ludeum.dosSoundFonts.path(percentEncoded: false))"))
        #expect(standing.contains("romdir = \(ludeum.dosMT32ROMs.path(percentEncoded: false))"))
        #expect(exists(ludeum.dosSoundFonts) && exists(ludeum.dosMT32ROMs))
    }

    @Test func theStandingSettingsHaveNoJoystick() throws {
        try install()

        _ = try press(try dos())

        let standing = try String(contentsOf: ludeum.dosBoxStagingStanding, encoding: .utf8).components(separatedBy: "\n")
        #expect(standing.contains("[joystick]"))
        #expect(standing.contains("joysticktype = none"))
    }

    @Test func withNoProgramOrAtAPromptItStaysAtDriveC() throws {
        try install()
        let dos = try dos()

        for outcome in [try press(dos), try press(dos, settings: EmulatorSettings(dosProgram: "KEEN1\\KEEN1.EXE"), prompt: true)] {
            #expect(commands(outcome).last == "C:")
            #expect(outcome.arguments?.contains("--exit") == false)
        }
    }

    @Test func itsOwnSettingsAreLaidOverTheStandingOnes() throws {
        try install()
        let own = try dosBoxStaging.gameSettings(ofROM: name)

        let arguments = try press(try dos()).arguments ?? []

        #expect(Array(arguments.prefix(6)).suffix(2) == ["--conf", own.path(percentEncoded: false)])
    }

    @Test func itsOwnSettingsStartAsANoteAndArentWrittenOver() throws {
        let file = try dosBoxStaging.gameSettings(ofROM: name)
        #expect(try String(contentsOf: file, encoding: .utf8).contains("cpu_cycles"))
        try put("[cpu]\ncpu_cycles = 8000\n", at: file)

        #expect(try dosBoxStaging.gameSettings(ofROM: name) == file)
        #expect(try String(contentsOf: file, encoding: .utf8) == "[cpu]\ncpu_cycles = 8000\n")
    }

    @Test func itsDiscsAreInDriveDDisc1First() throws {
        try install()
        let dos = try dos(discs: ["Cricket (Disc 2).cue", "Cricket (Disc 2).bin", "Cricket (Disc 1).iso"])
        try put("FILE \"Cricket (Disc 2).bin\" BINARY\n", at: dos.url.appending(path: "\(name)/CD/Cricket (Disc 2).cue"))

        let cd = dos.url.appending(path: "\(name)/CD")
        #expect(
            commands(try press(dos)).contains(
                "mount d \"\(path(cd.appending(path: "Cricket (Disc 1).iso")))\" \"\(path(cd.appending(path: "Cricket (Disc 2).cue")))\""))
    }

    @Test func aPathWithADoubleQuoteIsRefusedAsItWouldEndItsQuotes() throws {
        let subfolder = directory.appending(path: "ROMs/DOS/The \"Game\"", directoryHint: .isDirectory)
        try put("", at: subfolder.appending(path: "C/GAME.EXE"))

        #expect(throws: DOSBoxStagingPlayError.quoteInPath("C")) {
            try dosBoxStaging.arguments(subfolder: subfolder, romName: "The Game", settings: .init(), prompt: false)
        }
    }

    @Test func aCDGameWithNoDriveCHasItsGameSaveForDriveC() throws {
        try install()

        let outcome = try press(try dos(c: false, discs: ["Cricket.iso"]))

        #expect(commands(outcome).first == "mount c \"\(path(ludeum.dosGameSave(ofROM: name)))\"")
        #expect(!commands(outcome).contains { $0.hasSuffix("-t overlay") })
    }

    @Test func itsRefusedWhileADOSBoxStagingIsPlayingTheROMButNotAnother() throws {
        try install()
        let dos = try dos()
        func playing(_ name: String) -> [String] {
            ["/x/dosbox", "-c", "mount c \"/ROMs/C\"", "-c", "mount c \"\(path(ludeum.dosGameSave(ofROM: name)))\" -t overlay"]
        }

        let refused = try press(dos, open: DOSBoxStagingsOpen(commandLines: [playing(name)], ludeum: ludeum))
        #expect(refused.refusal == .running(.dosBoxStaging))
        #expect(refused.refusal?.message.contains("only one") == true)

        #expect(try press(dos, open: DOSBoxStagingsOpen(commandLines: [playing("Doom (1993)")], ludeum: ludeum)).refusal == nil)
        #expect(try press(dos, open: DOSBoxStagingsOpen(commandLines: [nil], ludeum: ludeum)).refusal == .running(.dosBoxStaging))
    }

    @Test func aDOSPromptIsOfferedOnlyOnceThereIsAProgram() {
        let rom = LudeumROM(
            id: 1, folderName: name, platformId: ROMPlatform.dos, fileName: "\(name)/C", name: name, version: "", disc: nil,
            missing: false, archived: false)
        func starts(_ settings: EmulatorSettings) -> [PlayStart] {
            Play(platformId: ROMPlatform.dos, platformName: "DOS", roms: [rom], settings: settings).starts(discs: [], resume: nil)
        }

        #expect(starts(.init()) == [.rom])
        #expect(starts(.init(dosProgram: "KEEN1\\KEEN1.EXE")) == [.rom, .prompt])
        #expect(PlayStart.prompt.prompt)
    }
}

/// Renaming a DOS ROM takes its Game save and own settings along (ADR 0042).
@Suite struct DOSRenameTests {
    let h: LudeumHarness
    let game: GameID
    let directory = FileManager.default.temporaryDirectory.appending(path: "dos rename \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: directory.appending(path: "Ludeum", directoryHint: .isDirectory)) }

    init() throws {
        h = try LudeumHarness()
        try h.journal.addPlatform(id: ROMPlatform.dos, name: "DOS")
        game = try h.journal.addGame(platformId: ROMPlatform.dos, name: "Keen")
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    func recorded(in folder: FakeROMFolder) throws -> LudeumROM {
        try folder.add("Keen/C/KEEN1.EXE")
        // Named for its subfolder, as Import names it.
        let game = game
        try h.journal.db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO rom (folderName, fileName, name, regions, platformId, missing, gameId, matchKind, matchedAt)
                    VALUES ('Keen', 'Keen/C', 'Keen', '[]', ?, 0, ?, 'manual', ?)
                    """, arguments: [ROMPlatform.dos, game, Date()])
        }
        let rom = try #require(try h.journal.roms(of: game).first)
        try h.journal.checkROMAgain(rom.id, in: folder.folder)
        return try #require(try h.journal.rom(rom.id))
    }

    @Test func itsGameSaveAndSettingsFollowItsName() throws {
        let dos = try FakeROMFolder(in: directory, platform: ROMPlatform.dos)
        let rom = try recorded(in: dos)
        try put("save", at: ludeum.dosGameSave(ofROM: "Keen").appending(path: "KEEN1/SAVE1.CK1"))
        try put("[cpu]", at: ludeum.dosGameSettings(ofROM: "Keen"))

        try h.journal.renameDOSBoxStagingROM(rom.id, from: "Keen", to: "Keen (1990)", in: dos.folder, ludeum: ludeum)

        #expect(try h.journal.rom(rom.id)?.folderName == "Keen (1990)")
        #expect(exists(ludeum.dosGameSave(ofROM: "Keen (1990)").appending(path: "KEEN1/SAVE1.CK1")))
        #expect(exists(ludeum.dosGameSettings(ofROM: "Keen (1990)")))
        #expect(!exists(ludeum.dosGameSave(ofROM: "Keen")))
    }

    @Test func itsRefusedWithAGameSaveUnderTheNewName() throws {
        let dos = try FakeROMFolder(in: directory, platform: ROMPlatform.dos)
        let rom = try recorded(in: dos)
        try put("save", at: ludeum.dosGameSave(ofROM: "Keen").appending(path: "A"))
        try put("save", at: ludeum.dosGameSave(ofROM: "Keen (1990)").appending(path: "B"))

        #expect(throws: DOSBoxStagingRenameError.inTheWay("Keen (1990)")) {
            try h.journal.renameDOSBoxStagingROM(rom.id, from: "Keen", to: "Keen (1990)", in: dos.folder, ludeum: ludeum)
        }
        #expect(try h.journal.rom(rom.id)?.folderName == "Keen")
    }

    @Test func itsRefusedWithADeletedROMsSettingsUnderTheNewNameThoughItHasNone() throws {
        let dos = try FakeROMFolder(in: directory, platform: ROMPlatform.dos)
        let rom = try recorded(in: dos)
        try put("[cpu]", at: ludeum.dosGameSettings(ofROM: "Keen (1990)"))

        #expect(throws: DOSBoxStagingRenameError.inTheWay("Keen (1990)")) {
            try h.journal.renameDOSBoxStagingROM(rom.id, from: "Keen", to: "Keen (1990)", in: dos.folder, ludeum: ludeum)
        }
    }

    @Test func aRenameThatFailsLeavesItsGameSaveWhereItWas() throws {
        let dos = try FakeROMFolder(in: directory, platform: ROMPlatform.dos)
        let rom = try recorded(in: dos)
        try put("save", at: ludeum.dosGameSave(ofROM: "Keen").appending(path: "A"))
        try FileManager.default.removeItem(at: dos.url.appending(path: "Keen"))

        #expect(throws: (any Error).self) {
            try h.journal.renameDOSBoxStagingROM(rom.id, from: "Keen", to: "Keen (1990)", in: dos.folder, ludeum: ludeum)
        }
        #expect(exists(ludeum.dosGameSave(ofROM: "Keen").appending(path: "A")))
    }
}

/// Installing the DOSBox Staging Ludeum keeps, with its SoundFont (ADR 0042), from a real disk image.
@Suite struct DOSBoxStagingInstallTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "dosbox install \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var settings: DOSBoxStagingSettings { DOSBoxStagingSettings(ludeum: ludeum) }
    let soundFont = Data("RIFF sf2".utf8)

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    /// Where the fake DOSBox Staging notes it was run: Install has no need to run it.
    var ran: URL { root.appending(path: "dosbox ran") }

    func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// A disk image like the release's, holding a fake DOSBox Staging.app saying it's `appVersion`.
    func image(appVersion: String = "0.83.0-7b400", noApp: Bool = false) throws -> Data {
        let staging = root.appending(path: "staging \(UUID().uuidString)", directoryHint: .isDirectory)
        let app = staging.appending(path: noApp ? "Other.app" : "DOSBox Staging.app", directoryHint: .isDirectory)
        let plist: [String: Any] = [
            "CFBundleShortVersionString": appVersion, "CFBundleExecutable": "dosbox", "CFBundleIdentifier": "fake.dosbox",
        ]
        try FileManager.default.createDirectory(at: app.appending(path: "Contents/MacOS"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(
            to: app.appending(path: "Contents/Info.plist"))
        let executable = app.appending(path: "Contents/MacOS/dosbox")
        try put("#!/bin/sh\ntouch '\(ran.path(percentEncoded: false))'\n", at: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
        let file = root.appending(path: "image \(UUID().uuidString).dmg")
        let hdiutil = Process()
        hdiutil.executableURL = URL(filePath: "/usr/bin/hdiutil")
        hdiutil.arguments = [
            "create", "-quiet", "-fs", "HFS+", "-format", "UDZO", "-volname", "DOSBox Staging", "-srcfolder",
            staging.path(percentEncoded: false), file.path(percentEncoded: false),
        ]
        try hdiutil.run()
        hdiutil.waitUntilExit()
        try #require(hdiutil.terminationStatus == 0)
        return try Data(contentsOf: file)
    }

    func installer(image: Data, soundFont: Data? = nil, soundFontSHA256: String? = nil) -> DOSBoxStagingInstaller {
        let release = DOSBoxStagingRelease(
            version: "0.83.0", sha256: digest(image), soundFontCommit: "abc", soundFontSHA256: soundFontSHA256 ?? digest(self.soundFont))
        return DOSBoxStagingInstaller(
            ludeum: ludeum, release: release,
            transport: FakeReleases([release.url: image, release.soundFontURL: soundFont ?? self.soundFont]))
    }

    @Test func theReleaseAndSoundFontArePinned() {
        let pinned = DOSBoxStagingRelease.pinned
        #expect(
            pinned.url.absoluteString
                == "https://github.com/dosbox-staging/dosbox-staging/releases/download/v0.83.0/dosbox-staging-macOS-v0.83.0.dmg")
        #expect(
            pinned.soundFontURL.absoluteString
                == "https://raw.githubusercontent.com/mrbumpy409/GeneralUser-GS/97049183643d5fc5a9322a69c5b09efb667c6c3a/GeneralUser-GS.sf2"
        )
        #expect(pinned.sha256.count == 64 && pinned.soundFontSHA256.count == 64)
        #expect(Emulator.dosBoxStaging.expectedVersion == "0.83.0")
    }

    @Test func installingPutsTheAppAndSoundFontInTheLudeumFolderWithoutRunningIt() async throws {
        try await installer(image: try image()).install()

        #expect(settings.isInstalled)
        #expect(try Data(contentsOf: ludeum.dosBoxStagingSoundFont) == soundFont)
        #expect(EmulatorVersions.check(.dosBoxStaging, app: settings.app)?.check == .ok)
        #expect(!exists(ludeum.emulators.appending(path: ".installing DOSBox Staging")))
        #expect(!exists(ran))
    }

    @Test func aSoundFontThatIsntTheOnePinnedReplacesNothing() async throws {
        try await installer(image: try image()).install()

        await #expect(throws: DOSBoxStagingInstallError.self) {
            try await installer(image: try image(), soundFont: Data("other".utf8)).install()
        }
        #expect(settings.isInstalled)
        #expect(try Data(contentsOf: ludeum.dosBoxStagingSoundFont) == soundFont)
    }

    @Test func aBuildThatSaysItsAnotherVersionIsRefused() async throws {
        await #expect(throws: DOSBoxStagingInstallError.wrongBuild(found: "0.82.2")) {
            try await installer(image: try image(appVersion: "0.82.2")).install()
        }
        #expect(!exists(settings.app))
    }

    @Test func aDiskImageWithNoAppIsRefused() async throws {
        await #expect(throws: DOSBoxStagingInstallError.noApp) { try await installer(image: try image(noApp: true)).install() }
        #expect(!exists(settings.app))
    }
}
