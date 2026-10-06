import CryptoKit
import Foundation
import GRDB
import Testing

@testable import LudeumCore

private let helloMD5 = "5d41402abc4b2a76b9719d911017c592"
private let helloCRC = "3610a686"

private func md5(_ data: Data) -> String { Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined() }

extension FakeROMFolder {
    @discardableResult
    func add(_ fileName: String, data: Data) throws -> URL {
        let file = url.appending(path: fileName)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
        return file
    }

    /// Packs `contents` as `fileName` into `<ROM name>.7z` with 7-Zip.
    func addArchive(_ romName: String, holding fileName: String, _ contents: String) async throws {
        try add("work/\(fileName)", contents)
        try await SevenZip.find()!.create(
            url.appending(path: "\(romName).7z"), files: [fileName], in: url.appending(path: "work"), progress: { _ in })
        try remove("work")
    }
}

@Suite struct ROMChecksumTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "rom checksum \(UUID().uuidString)")

    func checksum(_ folder: FakeROMFolder) async throws -> ROMChecksum? {
        await ROMChecksum.of(try #require(try folder.folder.scan().first), platformId: folder.platformId, sevenZip: nil)
    }

    @Test func aLooseROMIsLookedUpByItsFilesMD5() async throws {
        let gameBoy = try FakeROMFolder(in: directory, platform: 33)
        try gameBoy.add("Tetris (World).gb", "hello")

        #expect(try await checksum(gameBoy) == .md5(helloMD5))
    }

    @Test func anINESHeaderIsLeftOutAsTheDATsLeaveItOut() async throws {
        let nes = try FakeROMFolder(in: directory, platform: 18)
        try nes.add("Zelda (USA).nes", data: Data("NES\u{1A}".utf8) + Data(count: 12) + Data("hello".utf8))

        #expect(try await checksum(nes) == .md5(helloMD5))
    }

    @Test func aCopierHeaderIsLeftOutOnTheSNES() async throws {
        let snes = try FakeROMFolder(in: directory, platform: 19)
        let rom = Data(repeating: 0x41, count: 2048)
        try snes.add("Super Metroid (USA).smc", data: Data(count: 512) + rom)

        #expect(try await checksum(snes) == .md5(md5(rom)))
    }

    @Test func anSNESROMWithoutACopierHeaderIsHashedWhole() async throws {
        let snes = try FakeROMFolder(in: directory, platform: 19)
        let rom = Data(repeating: 0x41, count: 2048)
        try snes.add("Super Metroid (USA).sfc", data: rom)

        #expect(try await checksum(snes) == .md5(md5(rom)))
    }

    @Test func aCueSheetIsLookedUpByItsDataTrack() async throws {
        let ps1 = try FakeROMFolder(in: directory, platform: 7)
        try ps1.add(
            "Ape Escape (USA)/Ape Escape (USA).cue",
            "FILE \"Ape Escape (USA) (Track 1).bin\" BINARY\nFILE \"Ape Escape (USA) (Track 2).bin\" BINARY\n")
        try ps1.add("Ape Escape (USA)/Ape Escape (USA) (Track 1).bin", "hello")
        try ps1.add("Ape Escape (USA)/Ape Escape (USA) (Track 2).bin", "music")

        #expect(try await checksum(ps1) == .md5(helloMD5))
    }

    @Test func aPlaylistIsLookedUpByItsFirstDisc() async throws {
        let ps1 = try FakeROMFolder(in: directory, platform: 7)
        try ps1.add("FF7 (USA)/FF7 (USA).m3u", "FF7 (USA) (Disc 1).cue\nFF7 (USA) (Disc 2).cue\n")
        try ps1.add("FF7 (USA)/FF7 (USA) (Disc 1).cue", "FILE \"FF7 (USA) (Disc 1).bin\" BINARY\n")
        try ps1.add("FF7 (USA)/FF7 (USA) (Disc 1).bin", "hello")
        try ps1.add("FF7 (USA)/FF7 (USA) (Disc 2).cue", "FILE \"FF7 (USA) (Disc 2).bin\" BINARY\n")
        try ps1.add("FF7 (USA)/FF7 (USA) (Disc 2).bin", "disc 2")

        #expect(try await checksum(ps1) == .md5(helloMD5))
    }

    @Test func aCompressedImageNoDATKnowsHasNoChecksum() async throws {
        let ps2 = try FakeROMFolder(in: directory)
        try ps2.add("Okami (USA).chd", "compressed")

        #expect(try await checksum(ps2) == nil)
    }

    @Test func anArchiveWithout7ZipHasNoChecksum() async throws {
        let ps2 = try FakeROMFolder(in: directory)
        try ps2.add("Okami (USA).7z")

        #expect(try await checksum(ps2) == nil)
    }

    @Test func anArchiveIsLookedUpByItsLargestDumpsCRC() {
        let entries = [
            SevenZip.Entry(path: "Ape Escape (USA).cue", size: 9_000_000_000, crc: "cccccccc"),
            SevenZip.Entry(path: "Ape Escape (USA) (Track 1).bin", size: 500, crc: "11111111"),
            SevenZip.Entry(path: "Ape Escape (USA) (Track 2).bin", size: 400, crc: "22222222"),
        ]

        #expect(ROMChecksum.crc(of: entries) == "11111111")
    }
}

@Suite(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
struct ArchivedROMChecksumTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "rom checksum \(UUID().uuidString)")

    @Test func anArchivedROMIsLookedUpByTheCRCInItsIndex() async throws {
        let gameBoy = try FakeROMFolder(in: directory, platform: 33)
        try await gameBoy.addArchive("Tetris (World)", holding: "Tetris (World).gb", "hello")
        let rom = try #require(try gameBoy.folder.scan().first)

        #expect(await ROMChecksum.of(rom, platformId: 33, sevenZip: SevenZip.find()) == .crc(helloCRC))
    }
}

@Suite struct ChecksumImportTests {
    let h: Harness
    let j: LudeumHarness
    let gameBoy: FakeROMFolder

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        gameBoy = try FakeROMFolder(in: h.directory, platform: 33)
        h.internet.addPlatform(33, "Game Boy")
        h.internet.addGame(1, "Tetris", fields: ["platforms": [["id": 33, "name": "Game Boy"]]])
        h.internet.addGame(2, "Dr. Mario", fields: ["platforms": [["id": 33, "name": "Game Boy"]]])
        h.internet.addSearch("Tetris", platform: 33, results: [1])
    }

    func importNow(sevenZip: SevenZip? = nil) async throws -> ImportResult {
        try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil, sevenZip: sevenZip)
            .run(romFolders: [gameBoy.folder])
    }

    func rom(_ name: String) throws -> Row? {
        try j.journal.db.read { try Row.fetchOne($0, sql: "SELECT * FROM rom WHERE folderName = ?", arguments: [name]) }
    }

    @Test func aNewROMWhoseChecksumAndNameAgreeIsMatchedAutomaticallyAndSilently() async throws {
        try gameBoy.add("Tetris (World).gb", "hello")
        h.internet.addHash(md5: helloMD5, game: 1, platform: 33)

        let result = try await importNow()

        #expect(result.matched.map(\.romName) == ["Tetris (World)"])
        #expect(result.sentToReview.isEmpty)
        #expect(!result.changedSomething)
        let row = try #require(try rom("Tetris (World)"))
        #expect(row["matchKind"] as String? == "automatic")
        #expect(row["md5"] as String? == helloMD5)
        let game = try j.journal.game(try #require(row["gameId"]))
        #expect(game.platformId == 33)
        #expect(game.igdbGameId == 1)
        #expect(try j.journal.reviewQueue().namesAgree.isEmpty)
    }

    @Test func aChecksumWhoseNamesDisagreeIsOnlySuggested() async throws {
        try gameBoy.add("Tetris (World).gb", "hello")
        h.internet.addHash(md5: helloMD5, game: 2, platform: 33)

        let result = try await importNow()

        #expect(result.sentToReview.map(\.romName) == ["Tetris (World)"])
        let item = try #require(try j.journal.reviewQueue().checksumSuggestions.first)
        #expect(item.suggestedIgdbGameId == 2)
    }

    @Test(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
    func aROMWaitingInTheReviewQueueWithoutAChecksumGetsOneAndIsMatched() async throws {
        try await gameBoy.addArchive("Tetris (World)", holding: "Tetris (World).gb", "hello")
        h.internet.addHash(crc: helloCRC, game: 1, platform: 33)
        #expect(try await importNow(sevenZip: nil).sentToReview.map(\.romName) == ["Tetris (World)"])  // no 7-Zip to read it

        let result = try await importNow(sevenZip: SevenZip.find())

        #expect(result.matched.map(\.romName) == ["Tetris (World)"])
        #expect(result.sentToReview.isEmpty)
        #expect(try rom("Tetris (World)")?["matchKind"] as String? == "automatic")
        #expect(try rom("Tetris (World)")?["crc"] as String? == helloCRC)
        #expect(try j.journal.reviewQueue().namesAgree.isEmpty)
    }

    @Test func aROMAnsweredInTheReviewQueueIsntMatchedAgain() async throws {
        try gameBoy.add("Tetris (World).gb", "hello")
        _ = try await importNow()
        let item = try #require(try j.journal.reviewQueue().namesAgree.first)
        try j.journal.assign(item, to: try j.addGame("Tetris"))
        try await j.journal.db.write { try $0.execute(sql: "UPDATE rom SET md5 = NULL") }
        h.internet.addHash(md5: helloMD5, game: 1, platform: 33)

        let result = try await importNow()

        #expect(result.matched.isEmpty)
        #expect(try rom("Tetris (World)")?["matchKind"] as String? == "manual")
    }

    @Test func aROMWithAChecksumIsntLookedUpAgain() async throws {
        try gameBoy.add("Tetris (World).gb", "hello")
        _ = try await importNow()
        h.internet.resetSent()

        _ = try await importNow()

        #expect(h.internet.sent(to: "hasheous.org").isEmpty)
    }

    @Test(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
    func anArchivedROMIsMatchedByItsArchivesCRC() async throws {
        try await gameBoy.addArchive("Tetris (World)", holding: "Tetris (World).gb", "hello")
        h.internet.addHash(crc: helloCRC, game: 1, platform: 33)

        let result = try await importNow(sevenZip: SevenZip.find())

        #expect(result.matched.map(\.romName) == ["Tetris (World)"])
        #expect(try rom("Tetris (World)")?["crc"] as String? == helloCRC)
        #expect(try rom("Tetris (World)")?["md5"] as String? == nil)
    }
}
