import Foundation
import GRDB
import Testing

@testable import LudeumCore

@Suite struct ROMSourceTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "rom source \(UUID().uuidString)", directoryHint: .isDirectory)

    @discardableResult
    func file(_ path: String, _ contents: String = "x") throws -> URL {
        let url = directory.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func aFileIsReadByEveryPlatformWhoseEmulatorOpensIt() async throws {
        let source = ROMSource([try file("Tetris (World).gb")])

        #expect(source.romName == "Tetris (World)")
        #expect(try await source.platforms(sevenZip: nil) == [22, 33])
    }

    @Test func aFolderIsReadOnlyWhereROMsAreKeptInSubfolders() async throws {
        try file("Okami (USA)/Okami (USA).iso")
        let source = ROMSource([directory.appending(path: "Okami (USA)", directoryHint: .isDirectory)])

        #expect(source.isFolder)
        #expect(source.romName == "Okami (USA)")
        #expect(try await source.platforms(sevenZip: nil) == [7, ROMPlatform.ps2, 32, 78])
    }

    @Test func severalDiscsAreOneROMNamedAfterDisc1WithoutItsDisc() async throws {
        let source = ROMSource([try file("Fear Effect (USA) (Disc 2).chd"), try file("Fear Effect (USA) (Disc 1).chd")])

        #expect(source.romName == "Fear Effect (USA)")
        #expect(try await source.platforms(sevenZip: nil) == [7, ROMPlatform.ps2, 32, 78, 150])
    }

    @Test func severalFilesThatArentDiscsArentOneGame() async throws {
        let source = ROMSource([try file("Tetris (World).gb"), try file("Zelda (USA).gb")])

        await #expect(throws: AddROMError.notOneGame) { try await source.platforms(sevenZip: nil) }
    }
}

@Suite(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
struct AddROMTests {
    let j: LudeumHarness
    let directory = FileManager.default.temporaryDirectory.appending(path: "add rom \(UUID().uuidString)", directoryHint: .isDirectory)
    let picked: URL
    let trash: URL
    let sevenZip = SevenZip.find()!

    init() throws {
        j = try LudeumHarness()
        picked = directory.appending(path: "Downloads", directoryHint: .isDirectory)
        trash = directory.appending(path: "Trash", directoryHint: .isDirectory)
        for folder in [picked, trash] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    }

    var adder: AddROM {
        let trash = trash
        return AddROM(
            journal: j.journal, sevenZip: sevenZip,
            moveToTrash: { try FileManager.default.moveItem(at: $0, to: trash.appending(path: $0.lastPathComponent)) })
    }

    @discardableResult
    func pick(_ path: String, _ contents: String = "x") throws -> URL {
        let url = picked.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func trashed() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: trash.path(percentEncoded: false)).sorted() }

    func romRow(_ name: String) throws -> Row? {
        try j.journal.db.read { try Row.fetchOne($0, sql: "SELECT * FROM rom WHERE folderName = ?", arguments: [name]) }
    }

    func igdb(_ id: Int64, _ name: String, on platform: Int64) -> AddROMMatch {
        .igdb(gameId: id, name: name, platform: IGDBPlatform(id: platform, name: ROMPlatform.all[platform]!.name))
    }

    @Test func aCartridgeROMIsCompactedRecordedAndMatchedByHandKeepingTheOriginalWhenCopied() async throws {
        let gameBoy = try FakeROMFolder(in: directory, platform: 33)
        let original = try pick("Tetris (World).gb", String(repeating: "GB", count: 10_000))

        let game = try await adder.add(
            ROMSource([original]), to: gameBoy.folder, match: igdb(1, "Tetris", on: 33), keepingOriginals: true)

        let rom = try #require(try gameBoy.folder.scan().first)
        #expect(rom.fileName == "Tetris (World).7z")
        #expect(try await sevenZip.contents(of: rom.ready!).map { "\($0.path) \($0.size)" } == ["Tetris (World).gb 20000"])
        #expect(FileManager.default.fileExists(atPath: original.path(percentEncoded: false)))
        #expect(try trashed().isEmpty)
        let row = try #require(try romRow("Tetris (World)"))
        #expect(row["gameId"] as GameID == game)
        #expect(row["matchKind"] as String == "manual")
        #expect(row["fileName"] as String == "Tetris (World).7z")
        #expect(row["md5"] as String? == nil && row["crc"] as String? != nil)
        #expect(try j.journal.game(game).igdbGameId == 1)
    }

    @Test func movingSendsThePickedFileToTheTrashOnceItsIn() async throws {
        let gameBoy = try FakeROMFolder(in: directory, platform: 33)
        let original = try pick("Tetris (World).gb", "GB")

        try await adder.add(ROMSource([original]), to: gameBoy.folder, match: igdb(1, "Tetris", on: 33), keepingOriginals: false)

        #expect(!FileManager.default.fileExists(atPath: original.path(percentEncoded: false)))
        #expect(try trashed() == ["Tetris (World).gb"])
    }

    @Test func aZipIsRepackedAsTheArchiveItsEmulatorOpensItsGameNamedAfterTheROM() async throws {
        let gameBoy = try FakeROMFolder(in: directory, platform: 33)
        try pick("work/tetris.gb", String(repeating: "GB", count: 1000))
        try pick("work/readme.txt", "hi")
        let zip = picked.appending(path: "Tetris (World).zip")
        try await sevenZip.create(zip, format: "zip", files: ["tetris.gb", "readme.txt"], in: picked.appending(path: "work")) { _ in }

        try await adder.add(ROMSource([zip]), to: gameBoy.folder, match: igdb(1, "Tetris", on: 33), keepingOriginals: false)

        let rom = try #require(try gameBoy.folder.scan().first)
        #expect(rom.fileName == "Tetris (World).7z")
        #expect(try await sevenZip.contents(of: rom.ready!).map(\.path) == ["Tetris (World).gb"])
        #expect(try trashed() == ["Tetris (World).zip"])
    }

    @Test func anArchiveItsEmulatorAlreadyOpensGoesInAsItIs() async throws {
        let megaDrive = try FakeROMFolder(in: directory, platform: 29)
        try pick("work/Sonic (USA).md", "MD")
        let zip = picked.appending(path: "Sonic (USA).zip")
        try await sevenZip.create(zip, format: "zip", files: ["Sonic (USA).md"], in: picked.appending(path: "work")) { _ in }

        try await adder.add(ROMSource([zip]), to: megaDrive.folder, match: igdb(2, "Sonic", on: 29), keepingOriginals: true)

        #expect(try megaDrive.folder.scan().map(\.fileName) == ["Sonic (USA).zip"])
        #expect(try Data(contentsOf: megaDrive.url.appending(path: "Sonic (USA).zip")) == Data(contentsOf: zip))
    }

    @Test func discsGoIntoASubfolderWithAPlaylist() async throws {
        let ps1 = try FakeROMFolder(in: directory, platform: 7)
        var discs: [URL] = []
        for n in 1...2 {
            let name = "Fear Effect (USA) (Disc \(n))"
            discs.append(try pick("\(name).cue", "FILE \"\(name).bin\" BINARY\n"))
            try pick("\(name).bin", "disc \(n)")
        }

        try await adder.add(ROMSource(discs), to: ps1.folder, match: igdb(3, "Fear Effect", on: 7), keepingOriginals: false)

        let rom = try #require(try ps1.folder.scan().first)
        #expect(rom.name == "Fear Effect (USA)")
        #expect(rom.fileName == "Fear Effect (USA)/Fear Effect (USA).m3u")
        #expect(
            try String(contentsOf: rom.ready!, encoding: .utf8) == "Fear Effect (USA) (Disc 1).cue\nFear Effect (USA) (Disc 2).cue\n")
        #expect(try ps1.folder.files(named: "Fear Effect (USA)").count == 5)
        #expect(try trashed().count == 4)
        #expect(try romRow("Fear Effect (USA)")?["needsPlaylist"] as Bool? == false)
    }

    @Test func aFolderBecomesTheROMsSubfolder() async throws {
        let ps2 = try FakeROMFolder(in: directory, platform: ROMPlatform.ps2)
        try pick("Okami (USA)/Okami (USA).iso", "PS2")
        let folder = picked.appending(path: "Okami (USA)", directoryHint: .isDirectory)

        try await adder.add(ROMSource([folder]), to: ps2.folder, match: igdb(4, "Okami", on: 8), keepingOriginals: true)

        #expect(try ps2.folder.scan().map(\.fileName) == ["Okami (USA)/Okami (USA).iso"])
        #expect(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    @Test func aLooseFileOnAPlatformThatDoesntCompactStaysLooseNamedAfterTheROM() async throws {
        let psp = try FakeROMFolder(in: directory, platform: ROMPlatform.psp)
        let iso = try pick("Lumines (USA).ISO", "PSP")

        try await adder.add(ROMSource([iso]), to: psp.folder, match: igdb(5, "Lumines", on: 38), keepingOriginals: true)

        #expect(try psp.folder.scan().map(\.fileName) == ["Lumines (USA).iso"])
    }

    @Test func aROMAlreadyInTheROMFolderIsRefusedWithNothingTouched() async throws {
        let gameBoy = try FakeROMFolder(in: directory, platform: 33)
        try gameBoy.add("Tetris (World).7z")
        let original = try pick("Tetris (World).gb", "GB")

        await #expect(throws: AddROMError.alreadyInROMFolder("Tetris (World)")) {
            try await adder.add(ROMSource([original]), to: gameBoy.folder, match: igdb(1, "Tetris", on: 33), keepingOriginals: false)
        }
        #expect(try gameBoy.folder.scan().map(\.fileName) == ["Tetris (World).7z"])
        #expect(try trashed().isEmpty)
        #expect(try romRow("Tetris (World)") == nil)
    }

    @Test func aPlatformThatDoesntReadItIsRefused() async throws {
        let snes = try FakeROMFolder(in: directory, platform: 19)
        let original = try pick("Tetris (World).gb", "GB")

        await #expect(throws: AddROMError.platformWontReadIt("Super Nintendo Entertainment System")) {
            try await adder.add(ROMSource([original]), to: snes.folder, match: igdb(1, "Tetris", on: 19), keepingOriginals: false)
        }
    }

    /// A Game whose ROMs are all missing, its one ROM Matched by hand.
    func missingGame(_ romName: String, on platform: Int64) throws -> GameID {
        try j.journal.db.write { db in
            try ROMPlatform.ensureKnown(db, platform)
            try db.execute(sql: "INSERT INTO game (platformId, name) VALUES (?, 'Tetris')", arguments: [platform])
            let game = db.lastInsertedRowID
            try db.execute(
                sql: """
                    INSERT INTO rom (folderName, fileName, name, platformId, missing, gameId, matchKind, matchedAt)
                    VALUES (?, ?, ?, ?, 1, ?, 'manual', ?)
                    """, arguments: [romName, "\(romName).7z", romName, platform, game, Date()])
            return game
        }
    }

    @Test func aMissingROMsGameGainsTheNewROMAndForgetsItsMissingOnes() async throws {
        let gameBoy = try FakeROMFolder(in: directory, platform: 33)
        let game = try missingGame("Tetris (Japan)", on: 33)
        let original = try pick("Tetris (World) (Rev 1).gb", "GB")

        try await adder.add(ROMSource([original]), to: gameBoy.folder, match: .game(game, forgettingMissing: true), keepingOriginals: true)

        #expect(try j.journal.roms(of: game).map(\.folderName) == ["Tetris (World) (Rev 1)"])
        #expect(try j.journal.reviewQueue().missingROMs.isEmpty)
    }

    @Test func aFileOfTheMissingROMsNameBringsItBack() async throws {
        let gameBoy = try FakeROMFolder(in: directory, platform: 33)
        let game = try missingGame("Tetris (World)", on: 33)
        let id = try #require(try romRow("Tetris (World)")?["id"] as Int64?)
        let original = try pick("Tetris (World).gb", "GB")

        try await adder.add(ROMSource([original]), to: gameBoy.folder, match: .game(game, forgettingMissing: true), keepingOriginals: true)

        let roms = try j.journal.roms(of: game)
        #expect(roms.map(\.id) == [id])
        #expect(roms.map(\.missing) == [false])
    }

    @Test func aMissingROMOfThatNameOnAnotherGameIsRefused() async throws {
        let gameBoy = try FakeROMFolder(in: directory, platform: 33)
        _ = try missingGame("Tetris (World)", on: 33)
        let original = try pick("Tetris (World).gb", "GB")

        await #expect(throws: AddROMError.missingROMIsAnotherGames("Tetris (World)")) {
            try await adder.add(ROMSource([original]), to: gameBoy.folder, match: igdb(1, "Tetris", on: 33), keepingOriginals: true)
        }
        #expect(try gameBoy.folder.scan().isEmpty)
    }

    @Test func anImportThatReadTheROMBeforeItWasRecordedLeavesItAsAddROMRecordedIt() async throws {
        let gameBoy = try FakeROMFolder(in: directory, platform: 33)
        let original = try pick("Tetris (World).gb", "GB")
        try await adder.add(ROMSource([original]), to: gameBoy.folder, match: igdb(1, "Tetris", on: 33), keepingOriginals: true)
        let file = try #require(try gameBoy.folder.scan().first)
        var plan = ImportPlan()
        plan.new = [NewFolderROM(platformId: 33, file: file, checksum: nil, match: .noSuggestion)]

        let result = try j.journal.applyImport(plan)

        #expect(result.sentToReview.isEmpty)
        #expect(try romRow("Tetris (World)")?["matchKind"] as String? == "manual")
    }
}
