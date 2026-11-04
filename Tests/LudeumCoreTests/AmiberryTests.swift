import CryptoKit
import Foundation
import Testing

@testable import LudeumCore

private let disk1 = "Hero Quest II (1994)(Gremlin)(M3)[cr TRSi](Disk 1 of 3).adf"
private let disk2 = "Hero Quest II (1994)(Gremlin)(M3)[cr TRSi](Disk 2 of 3).adf"
private let disk3 = "Hero Quest II (1994)(Gremlin)(M3)[cr TRSi](Disk 3 of 3).adf"
private let setName = "Hero Quest II (1994)(Gremlin)(M3)[cr TRSi]"

/// An Amiga ROM's name, as TOSEC writes a floppy set's.
@Suite struct AmigaROMNameTests {
    @Test func tosecsDiskOfIsADisc() {
        let name = ROMName("Hero Quest II - Legacy of Sorasil (1994)(Gremlin)(M3)[cr TRSi - ZNT](Disk 2 of 3)")

        #expect(name.disc == 2)
        #expect(name.discLabel == nil)
        #expect(name.title == "Hero Quest II - Legacy of Sorasil")
        #expect(name.withoutDisc == "Hero Quest II - Legacy of Sorasil (1994)(Gremlin)(M3)[cr TRSi - ZNT]")
    }

    @Test func aTrainedDisk1KeepsWhatFollowsItsDisk() {
        let name = ROMName("Hero Quest II (1994)(Gremlin)(M3)[cr TRSi](Disk 1 of 3)[t +85 HLM]")

        #expect(name.disc == 1)
        #expect(name.withoutDisc == "Hero Quest II (1994)(Gremlin)(M3)[cr TRSi][t +85 HLM]")
    }

    @Test func itsStandardNameIsTheGamesWithTheTagsItCantPlaceKept() {
        #expect(
            ROMRename.newName(
                forROM: "Hero Quest II - Legacy of Sorasil (1994)(Gremlin)(M3)[cr TRSi - ZNT]", gameName: "HeroQuest II: Legacy of Sorasil",
                regions: [], platformId: ROMPlatform.amiga) == "HeroQuest II - Legacy of Sorasil (1994) (Gremlin) [cr TRSi - ZNT]")
    }

    @Test func itsNameAgreesWithIGDBsDespiteTheSpace() {
        let rom = romTitles("Hero Quest II - Legacy of Sorasil (1994)(Gremlin)(M3)[cr TRSi - ZNT]").map(nameKey)

        #expect(rom.contains(nameKey(cleanName("HeroQuest II: Legacy of Sorasil"))))
    }
}

/// An Amiga ROM in its ROM folder (ADR 0035).
@Suite struct AmigaROMFolderTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "amiga folder \(UUID().uuidString)", directoryHint: .isDirectory)

    @Test func aLooseDiskAndAnArchiveAreEachAPlayableROM() throws {
        let amiga = try FakeROMFolder(in: directory, platform: ROMPlatform.amiga)
        let loose = try amiga.add("HeroQuest.adf")
        let packed = try amiga.add("Hero Quest II.7z")

        #expect(
            try amiga.folder.scan() == [
                FolderROMFile(name: "Hero Quest II", ready: packed, archive: packed),
                FolderROMFile(name: "HeroQuest", ready: loose, archive: nil),
            ])
    }

    @Test func aLooseDiskCanBeCompactedAndAnArchiveNeedsNothing() throws {
        func rom(_ fileName: String) -> LudeumROM {
            LudeumROM(
                id: 1, folderName: "HeroQuest", platformId: ROMPlatform.amiga, fileName: fileName, name: "HeroQuest", version: "",
                disc: nil, missing: false, archived: false)
        }

        #expect(ROMArchiving.action(for: rom("HeroQuest.adf")) == .compact)
        #expect(ROMArchiving.compactFileName(for: rom("HeroQuest.adf")) == "HeroQuest.7z")
        #expect(ROMArchiving.action(for: rom("HeroQuest.7z")) == nil)
    }

    @Test func everyAddMakesTheOneArchive() throws {
        let amiga = try FakeROMFolder(in: directory, platform: ROMPlatform.amiga)
        let discs = [directory.appending(path: disk1), directory.appending(path: disk2)]

        #expect(AddROM.fileName(of: ROMSource(discs), in: amiga.folder) == "\(setName).7z")
        #expect(AddROM.fileName(of: ROMSource([directory.appending(path: "HeroQuest.adf")]), in: amiga.folder) == "HeroQuest.7z")
    }
}

/// What a Play gives Amiberry (ADR 0035).
@Suite(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
struct AmiberryArgumentsTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "amiberry \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: directory.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var settings: AmiberrySettings { AmiberrySettings(ludeum: ludeum) }
    let sevenZip = SevenZip.find()!

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    /// `name`.7z in the folder `in`, holding `disks`.
    func archive(_ name: String, holding disks: [String]) async throws -> URL {
        let work = directory.appending(path: "disks \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        for disk in disks { try Data(disk.utf8).write(to: work.appending(path: disk)) }
        let archive = directory.appending(path: "\(name).7z")
        try await sevenZip.create(archive, files: disks, in: work) { _ in }
        return archive
    }

    func path(_ url: URL) -> String { url.path(percentEncoded: false) }

    func savedDisks(_ rom: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path(ludeum.amiberrySavedDisks(ofROM: rom))).sorted()
    }

    @Test func anEmptySaveImageIsExactlyWhatAmiberryMakes() {
        let image = AmiberrySettings.emptySaveImage

        // Amiberry 8.5.0's, made by turning off a zipped disk's write protection.
        #expect(image.count == 2_124_148)
        #expect(Insecure.MD5.hash(data: image).map { String(format: "%02x", $0) }.joined() == "998910b039a7cc7dd1a5d443ae7fa96c")
    }

    @Test func aSaveImageIsNamedAfterItsDiskInsideTheArchive() {
        #expect(AmiberrySettings.saveImageName(ofDisk: "HeroQuest.adf") == "HeroQuest_save.adf")
        #expect(AmiberrySettings.saveImageName(ofDisk: "set/Vol. 2 (Disk 1).dms") == "Vol. 2 (Disk 1)_save.adf")
    }

    @Test func disksAreInDiscOrderAndOnlyWhatItOpens() {
        let entries = [disk3, "readme.txt", disk1, disk2].map { SevenZip.Entry(path: $0, size: 1) }

        #expect(AmiberrySettings.disks(in: entries).map(\.path) == [disk1, disk2, disk3])
    }

    @Test func disksWithNoNumberAreInNameOrderAfterAnyWithOne() {
        let entries = ["Save Disk.adf", "Game (Disk 1).adf", "Extra.adf"].map { SevenZip.Entry(path: $0, size: 1) }

        #expect(AmiberrySettings.disks(in: entries).map(\.path) == ["Game (Disk 1).adf", "Extra.adf", "Save Disk.adf"])
    }

    @Test func aOneDiskROMGoesInTheFirstDriveWithNoSwapper() async throws {
        let rom = try await archive("HeroQuest", holding: ["HeroQuest.adf"])

        let arguments = try settings.arguments(rom: rom, romName: "HeroQuest")

        #expect(
            arguments == [
                "--rescan-roms", "--model", "A500", "-G",
                "-o", "amiberry_config=\(path(ludeum.data))Emulators/Amiberry/amiberry.conf",
                "-o", "saveimage_dir=\(path(ludeum.data))Emulators/Amiberry/Saved Disks/HeroQuest/",
                "-s", "floppy0=\(path(rom))/HeroQuest.adf",
            ])
        #expect(try savedDisks("HeroQuest") == ["HeroQuest_save.adf"])
    }

    @Test func aDiskWhosePathAmiberryWouldLeaveEmptyIsRefusedMakingNothing() async throws {
        let name = String(repeating: "x", count: 120)
        let rom = try await archive(name, holding: ["\(name).adf"])

        let length = path(rom).utf8.count + 1 + name.count + 4
        #expect(length > AmiberrySettings.longestDiskPath)
        #expect(throws: AmiberryPlayError.pathTooLong(length)) { try settings.arguments(rom: rom, romName: name) }
        #expect(!FileManager.default.fileExists(atPath: path(ludeum.amiberrySavedDisks(ofROM: name))))
    }

    @Test func aDiskPathOfExactlyTheLongestAmiberryOpensGoesIn() async throws {
        let prefix = path(directory).utf8.count + ".7z/.adf".utf8.count
        let room = AmiberrySettings.longestDiskPath - prefix
        let archiveName = String(repeating: "x", count: room / 2)
        let diskName = String(repeating: "y", count: room - room / 2) + ".adf"
        let rom = try await archive(archiveName, holding: [diskName])

        #expect((path(rom) + "/" + diskName).utf8.count == AmiberrySettings.longestDiskPath)
        #expect(try settings.arguments(rom: rom, romName: archiveName).last == "floppy0=\(path(rom))/\(diskName)")
    }

    @Test func aDiskSetsFirstTwoAreInTheDrivesAndEveryOneInTheSwapper() async throws {
        let rom = try await archive(setName, holding: [disk3, disk1, disk2])

        let arguments = try settings.arguments(rom: rom, romName: setName)

        let paths = [disk1, disk2, disk3].map { path(rom) + "/" + $0 }
        #expect(
            Array(arguments.suffix(10)) == [
                "-s", "floppy0=\(paths[0])", "-s", "floppy1=\(paths[1])",
                "-s", "diskimage0=\(paths[0])", "-s", "diskimage1=\(paths[1])", "-s", "diskimage2=\(paths[2])",
            ])
        #expect(try savedDisks(setName).count == 3)
        #expect(try savedDisks(setName).first == (disk1 as NSString).deletingPathExtension + "_save.adf")
    }

    @Test func aSaveImageAlreadyThereIsLeftAloneAsItHoldsTheGamesSaves() async throws {
        let rom = try await archive("HeroQuest", holding: ["HeroQuest.adf"])
        let image = ludeum.amiberrySavedDisks(ofROM: "HeroQuest").appending(path: "HeroQuest_save.adf")
        try FileManager.default.createDirectory(at: image.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("what the game saved".utf8).write(to: image)

        _ = try settings.arguments(rom: rom, romName: "HeroQuest")

        #expect(try Data(contentsOf: image) == Data("what the game saved".utf8))
    }

    @Test func theArchiveIsntTouched() async throws {
        let rom = try await archive("HeroQuest", holding: ["HeroQuest.adf"])
        let before = try Data(contentsOf: rom)

        _ = try settings.arguments(rom: rom, romName: "HeroQuest")

        #expect(try Data(contentsOf: rom) == before)
    }

    @Test func anArchiveHoldingNoDiskIsRefused() async throws {
        let rom = try await archive("Readme", holding: ["readme.txt"])

        #expect(throws: ArchiveError.noImage) { try settings.arguments(rom: rom, romName: "Readme") }
    }

    @Test func itsRefusedWithoutSevenZip() async throws {
        let rom = try await archive("HeroQuest", holding: ["HeroQuest.adf"])

        #expect(throws: ArchiveError.noSevenZip) {
            try AmiberrySettings(ludeum: ludeum, sevenZip: nil).arguments(rom: rom, romName: "HeroQuest")
        }
    }

    @Test func itsRefusedWithoutTheDataFolder() async throws {
        let rom = try await archive("HeroQuest", holding: ["HeroQuest.adf"])
        try FileManager.default.removeItem(at: ludeum.data)

        #expect(throws: DataFolderMissing.self) { try settings.arguments(rom: rom, romName: "HeroQuest") }
        #expect(!FileManager.default.fileExists(atPath: path(ludeum.data)))
    }

    @Test func itsHomeIsTheDataFoldersAmiberryFolder() {
        #expect(settings.environment == ["AMIBERRY_HOME_DIR": path(ludeum.data) + "Emulators/Amiberry"])
    }
}

/// Play in the Amiberry Ludeum installs (ADR 0035).
@Suite(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
struct AmiberryPlayTests {
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "amiberry play \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: directory.appending(path: "Ludeum", directoryHint: .isDirectory)) }

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    func install() throws {
        let executable = ludeum.amiberryApp.appending(path: "Contents/MacOS/Amiberry")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
    }

    func rom(_ fileName: String) -> LudeumROM {
        LudeumROM(
            id: 1, folderName: "HeroQuest", platformId: ROMPlatform.amiga, fileName: fileName, name: "HeroQuest", version: "", disc: nil,
            missing: false, archived: false)
    }

    func press(_ fileName: String, in amiga: FakeROMFolder, running: Bool = false) -> Play.Outcome {
        Play(platformId: ROMPlatform.amiga, platformName: "Amiga", roms: [rom(fileName)], settings: .init())
            .prepare(
                locator: ROMLocator(romFolders: [amiga.folder]), version: .ok, app: { _ in URL(filePath: "/Applications/Amiberry.app") },
                amiberry: AmiberrySettings(ludeum: ludeum), running: { _ in running })
    }

    /// `HeroQuest.7z` holding one disk, in a new Amiga ROM folder.
    func compacted() async throws -> FakeROMFolder {
        let amiga = try FakeROMFolder(in: directory, platform: ROMPlatform.amiga)
        try amiga.add("HeroQuest.adf", "disk")
        try await SevenZip.find()!.create(amiga.url.appending(path: "HeroQuest.7z"), files: ["HeroQuest.adf"], in: amiga.url) { _ in }
        try amiga.remove("HeroQuest.adf")
        return amiga
    }

    @Test func amigaIsPlayedInAmiberry() {
        #expect(Emulator.of(platformId: ROMPlatform.amiga) == .amiberry)
        #expect(Emulator.amiberry.isLudeums)
        #expect(Emulator.all.contains(.amiberry))
    }

    @Test func itOpensLudeumsCopyWithItsHomeInTheEnvironment() async throws {
        try install()
        let amiga = try await compacted()

        guard case .open(let app, let arguments, _, _, let environment) = press("HeroQuest.7z", in: amiga) else {
            Issue.record("Play was refused")
            return
        }

        #expect(app == ludeum.amiberryApp)
        #expect(arguments.last == "floppy0=" + amiga.url.appending(path: "HeroQuest.7z").path(percentEncoded: false) + "/HeroQuest.adf")
        #expect(environment == AmiberrySettings(ludeum: ludeum).environment)
    }

    @Test func aLooseDiskIsRefusedAsAGameWouldSaveOntoIt() throws {
        try install()
        let amiga = try FakeROMFolder(in: directory, platform: ROMPlatform.amiga)
        try amiga.add("HeroQuest.adf")

        #expect(press("HeroQuest.adf", in: amiga).refusal == .needsCompacting)
    }

    @Test func withoutTheAmiberryLudeumInstallsPlayIsRefused() async throws {
        let amiga = try await compacted()

        #expect(press("HeroQuest.7z", in: amiga).refusal == .notInstalled(.amiberry))
    }

    @Test func playIsRefusedWhileAnyAmiberryIsOpen() async throws {
        try install()
        let amiga = try await compacted()

        #expect(press("HeroQuest.7z", in: amiga, running: true).refusal == .running(.amiberry))
    }

    @Test func anArchiveItCantReadIsRefusedSayingSo() throws {
        try install()
        let amiga = try FakeROMFolder(in: directory, platform: ROMPlatform.amiga)
        try amiga.add("HeroQuest.7z", "not an archive")

        guard case .couldntGetDisksReady = press("HeroQuest.7z", in: amiga).refusal else {
            Issue.record("expected a refusal saying its disks couldn't be got ready")
            return
        }
    }
}

/// Adding an Amiga ROM: its disks in one archive (ADR 0035).
@Suite(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
struct AmigaAddROMTests {
    let j: LudeumHarness
    let directory = FileManager.default.temporaryDirectory.appending(path: "amiga add \(UUID().uuidString)", directoryHint: .isDirectory)
    let picked: URL
    let sevenZip = SevenZip.find()!

    init() throws {
        j = try LudeumHarness()
        picked = directory.appending(path: "Downloads", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
    }

    var adder: AddROM { AddROM(journal: j.journal, sevenZip: sevenZip, moveToTrash: { _ in }) }
    var match: AddROMMatch { .byHand(name: "HeroQuest II") }

    func pick(_ name: String) throws -> URL {
        let url = picked.appending(path: name)
        try Data(name.utf8).write(to: url)
        return url
    }

    /// `name`.`format`, as TOSEC keeps a disk: alone in an archive of its name.
    func pickArchive(_ disk: String, format: String = "zip") async throws -> URL {
        let adf = try pick(disk)
        let archive = adf.deletingPathExtension().appendingPathExtension(format)
        try await sevenZip.create(archive, format: format, files: [disk], in: picked) { _ in }
        try FileManager.default.removeItem(at: adf)
        return archive
    }

    func inside(_ rom: FolderROMFile) async throws -> [String] {
        try await sevenZip.contents(of: try #require(rom.ready)).map(\.path).sorted()
    }

    @Test func oneDiskIsCompactedUnderTheROMsName() async throws {
        let amiga = try FakeROMFolder(in: directory, platform: ROMPlatform.amiga)
        let source = ROMSource([try pick("HeroQuest.adf")])

        #expect(try await source.platforms(sevenZip: nil) == [ROMPlatform.amiga])
        try await adder.add(source, to: amiga.folder, match: .byHand(name: "HeroQuest"), keepingOriginals: true)

        let rom = try #require(try amiga.folder.scan().first)
        #expect(rom.fileName == "HeroQuest.7z")
        #expect(try await inside(rom) == ["HeroQuest.adf"])
    }

    @Test func eachDiskPickedLooseGoesInOneArchiveKeepingItsName() async throws {
        let amiga = try FakeROMFolder(in: directory, platform: ROMPlatform.amiga)
        let source = ROMSource([try pick(disk3), try pick(disk1), try pick(disk2)])

        #expect(source.romName == setName)
        try await adder.add(source, to: amiga.folder, match: match, keepingOriginals: true)

        let rom = try #require(try amiga.folder.scan().first)
        #expect(rom.name == setName)
        #expect(rom.fileName == "\(setName).7z")
        #expect(try await inside(rom) == [disk1, disk2, disk3])
    }

    @Test func eachDiskPickedInItsOwnArchiveGoesInOneArchive() async throws {
        let amiga = try FakeROMFolder(in: directory, platform: ROMPlatform.amiga)
        let source = ROMSource([try await pickArchive(disk1), try await pickArchive(disk2), try await pickArchive(disk3)])

        #expect(try await source.platforms(sevenZip: sevenZip) == [ROMPlatform.amiga])
        try await adder.add(source, to: amiga.folder, match: match, keepingOriginals: true)

        let rom = try #require(try amiga.folder.scan().first)
        #expect(rom.fileName == "\(setName).7z")
        #expect(try await inside(rom) == [disk1, disk2, disk3])
    }

    @Test func aZipOfEveryDiskGoesInOneArchive() async throws {
        let amiga = try FakeROMFolder(in: directory, platform: ROMPlatform.amiga)
        _ = try [disk1, disk2, disk3].map(pick)
        let zip = picked.appending(path: "\(setName).zip")
        try await sevenZip.create(zip, format: "zip", files: [disk1, disk2, disk3], in: picked) { _ in }

        try await adder.add(ROMSource([zip]), to: amiga.folder, match: match, keepingOriginals: true)

        let rom = try #require(try amiga.folder.scan().first)
        #expect(try await inside(rom) == [disk1, disk2, disk3])
    }

    @Test func disksThatArentASetAreRefusedAsNotOneGame() async throws {
        let source = ROMSource([try pick("HeroQuest.adf"), try pick("Lemmings.adf")])

        await #expect(throws: AddROMError.notOneGame) { try await source.platforms(sevenZip: nil) }
    }

    @Test func severalPickedAtOnceAreEachVersionsDisksTogetherAndTheRestOnTheirOwn() async throws {
        let alternate = "Hero Quest II (1994)(Gremlin)(M3)[cr TRSi][a](Disk 1 of 3).adf"
        let trained = "Hero Quest II (1994)(Gremlin)(M3)[cr TRSi](Disk 1 of 3)[t +85 HLM].adf"
        var urls: [URL] = []
        for disk in [disk1, disk2, disk3, alternate, trained] { urls.append(try await pickArchive(disk)) }

        let roms = await ROMSource.split(urls)

        #expect(roms.map(\.urls.count).sorted() == [1, 1, 3])
        #expect(roms.first { $0.urls.count == 3 }?.romName == setName)
    }

    @Test func anotherPlatformsDiscsInArchivesStayARomEach() async throws {
        let disc1 = try pick("Fear Effect (USA) (Disc 1).chd")
        let disc2 = try pick("Fear Effect (USA) (Disc 2).chd")
        let archives = [disc1, disc2].map { $0.deletingPathExtension().appendingPathExtension("7z") }
        for (disc, archive) in zip([disc1, disc2], archives) {
            try await sevenZip.create(archive, files: [disc.lastPathComponent], in: picked) { _ in }
        }

        #expect(await ROMSource.split(archives).map(\.urls.count) == [1, 1])
    }
}

/// A Rename of an Amiga ROM: its saved disks go with it (ADR 0035).
@Suite struct AmiberryRenameTests {
    let h: LudeumHarness
    let game: GameID
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "amiberry rename \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: directory.appending(path: "Ludeum", directoryHint: .isDirectory)) }

    init() throws {
        h = try LudeumHarness()
        try h.journal.addPlatform(id: ROMPlatform.amiga, name: "Amiga")
        game = try h.journal.addGame(platformId: ROMPlatform.amiga, name: "HeroQuest")
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    func recorded(_ fileName: String, in folder: FakeROMFolder) throws -> LudeumROM {
        try h.journal.recordROM(game: game, fileName: fileName, missing: false)
        let rom = try #require(try h.journal.roms(of: game).first)
        try h.journal.checkROMAgain(rom.id, in: folder.folder)
        return try #require(try h.journal.rom(rom.id))
    }

    func putSavedDisk(of romName: String) throws -> URL {
        let image = ludeum.amiberrySavedDisks(ofROM: romName).appending(path: "HeroQuest_save.adf")
        try FileManager.default.createDirectory(at: image.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("saved".utf8).write(to: image)
        return image
    }

    @Test func itsSavedDisksFollowItsNameKeepingTheirOwn() throws {
        let amiga = try FakeROMFolder(in: directory, platform: ROMPlatform.amiga)
        try amiga.add("HeroQuest.7z")
        let rom = try recorded("HeroQuest.7z", in: amiga)
        _ = try putSavedDisk(of: "HeroQuest")

        try h.journal.renameAmiberryROM(rom.id, from: "HeroQuest", to: "HeroQuest (1991)", in: amiga.folder, ludeum: ludeum)

        #expect(try h.journal.rom(rom.id)?.fileName == "HeroQuest (1991).7z")
        let moved = ludeum.amiberrySavedDisks(ofROM: "HeroQuest (1991)").appending(path: "HeroQuest_save.adf")
        #expect(FileManager.default.fileExists(atPath: moved.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: ludeum.amiberrySavedDisks(ofROM: "HeroQuest").path(percentEncoded: false)))
    }

    @Test func aROMNeverPlayedHasNoSavedDisksToMove() throws {
        let amiga = try FakeROMFolder(in: directory, platform: ROMPlatform.amiga)
        try amiga.add("HeroQuest.7z")
        let rom = try recorded("HeroQuest.7z", in: amiga)

        try h.journal.renameAmiberryROM(rom.id, from: "HeroQuest", to: "HeroQuest (1991)", in: amiga.folder, ludeum: ludeum)

        #expect(try h.journal.rom(rom.id)?.fileName == "HeroQuest (1991).7z")
    }

    @Test func itsRefusedWhenAmiberryKeepsSavedDisksUnderTheNewName() throws {
        let amiga = try FakeROMFolder(in: directory, platform: ROMPlatform.amiga)
        try amiga.add("HeroQuest.7z")
        let rom = try recorded("HeroQuest.7z", in: amiga)
        _ = try putSavedDisk(of: "HeroQuest (1991)")

        #expect(throws: AmiberryRenameError.savedDisksInTheWay("HeroQuest (1991)")) {
            try h.journal.renameAmiberryROM(rom.id, from: "HeroQuest", to: "HeroQuest (1991)", in: amiga.folder, ludeum: ludeum)
        }
        #expect(try h.journal.rom(rom.id)?.fileName == "HeroQuest.7z")
    }
}

/// Installing the Amiberry Ludeum keeps (ADR 0035), from a real disk image.
@Suite struct AmiberryInstallTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "amiberry install \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var settings: AmiberrySettings { AmiberrySettings(ludeum: ludeum) }

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    /// Where the fake Amiberry notes it was run: Install has no need to run it.
    var ran: URL { root.appending(path: "Amiberry ran") }

    /// A disk image like the release's, holding a fake Amiberry.app saying it's `appVersion` (or nothing with `noApp`), and
    /// the release that names it.
    func release(appVersion: String = "8.5.0", version: String = "8.5.0", noApp: Bool = false) throws -> (
        image: Data, release: AmiberryRelease
    ) {
        let staging = root.appending(path: "staging \(UUID().uuidString)", directoryHint: .isDirectory)
        let app = staging.appending(path: "Amiberry.app", directoryHint: .isDirectory)
        let macOS = app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleShortVersionString": appVersion, "CFBundleExecutable": "Amiberry", "CFBundleIdentifier": "fake.Amiberry",
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(
            to: app.appending(path: "Contents/Info.plist"))
        let executable = macOS.appending(path: "Amiberry")
        try "#!/bin/sh\ntouch '\(ran.path(percentEncoded: false))'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
        if noApp {
            try FileManager.default.moveItem(at: app, to: staging.appending(path: "Other.app", directoryHint: .isDirectory))
        }
        let imageFile = root.appending(path: "image \(UUID().uuidString).dmg")
        let hdiutil = Process()
        hdiutil.executableURL = URL(filePath: "/usr/bin/hdiutil")
        hdiutil.arguments = [
            "create", "-quiet", "-fs", "HFS+", "-format", "UDZO", "-volname", "Amiberry", "-srcfolder", staging.path(percentEncoded: false),
            imageFile.path(percentEncoded: false),
        ]
        try hdiutil.run()
        hdiutil.waitUntilExit()
        try #require(hdiutil.terminationStatus == 0)
        let image = try Data(contentsOf: imageFile)
        let digest = SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined()
        return (image, AmiberryRelease(version: version, sha256: digest))
    }

    func installer(_ release: AmiberryRelease, image: Data) -> AmiberryInstaller {
        AmiberryInstaller(ludeum: ludeum, release: release, transport: FakeReleases([release.url: image]))
    }

    @Test func installingPutsAmiberryInTheLudeumFolderWithoutRunningIt() async throws {
        let (image, release) = try release()

        try await installer(release, image: image).install()

        #expect(settings.isInstalled)
        #expect(settings.app == ludeum.emulators.appending(path: "Amiberry.app", directoryHint: .isDirectory))
        #expect(EmulatorVersions.check(.amiberry, app: settings.app)?.check == .ok)
        #expect(!exists(ludeum.emulators.appending(path: ".installing Amiberry")))
        #expect(!exists(ran))
    }

    @Test func aReinstallReplacesTheCopyThere() async throws {
        let (image, release) = try release()
        try await installer(release, image: image).install()
        let stale = settings.app.appending(path: "Contents/stale")
        try Data().write(to: stale)

        try await installer(release, image: image).install()

        #expect(settings.isInstalled)
        #expect(!exists(stale))
        #expect(!exists(ludeum.emulators.appending(path: "Amiberry (replaced).app")))
    }

    @Test func aDownloadThatIsntTheReleaseIsRefused() async throws {
        let (image, release) = try release()
        let wrong = AmiberryRelease(version: release.version, sha256: String(repeating: "0", count: 64))

        await #expect(throws: AmiberryInstallError.badChecksum(expected: wrong.sha256, found: release.sha256)) {
            try await installer(wrong, image: image).install()
        }
        #expect(!exists(settings.app))
    }

    @Test func aBuildThatSaysItsAnotherVersionIsRefused() async throws {
        let (image, release) = try release(appVersion: "8.4.2")

        await #expect(throws: AmiberryInstallError.wrongBuild(found: "8.4.2")) { try await installer(release, image: image).install() }
        #expect(!exists(settings.app))
    }

    @Test func aDiskImageWithNoAmiberryIsRefusedAndNotLeftMounted() async throws {
        let (image, release) = try release(noApp: true)
        let installer = installer(release, image: image)

        await #expect(throws: AmiberryInstallError.noApp) { try await installer.install() }
        #expect(!exists(settings.app))
        #expect(!exists(installer.work))
    }

    @Test func aMissingDownloadIsRefused() async throws {
        let release = AmiberryRelease(version: "8.5.0", sha256: String(repeating: "0", count: 64))

        await #expect(throws: AmiberryInstallError.notFound(version: "8.5.0", status: 404)) {
            try await AmiberryInstaller(ludeum: ludeum, release: release, transport: FakeReleases([:])).install()
        }
    }

    @Test func thePinnedReleaseIsTheUniversalDiskImage() {
        #expect(
            AmiberryRelease.pinned.url.absoluteString
                == "https://github.com/BlitterStudio/amiberry/releases/download/v8.5.0/Amiberry-8.5.0-macOS-universal.dmg")
        #expect(AmiberryRelease.pinned.sha256.count == 64)
        #expect(Emulator.amiberry.expectedVersion == "8.5.0")
    }
}
