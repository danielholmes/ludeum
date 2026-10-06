import Foundation
import Testing

@testable import LudeumCore

@Suite struct UnarchivePlanTests {
    let folder = ROMFolder.ps2(URL(filePath: "/Games/PS2", directoryHint: .isDirectory))
    let archive = URL(filePath: "/Games/PS2/ICO.7z")

    func entry(_ path: String, _ size: Int64 = 100) -> SevenZip.Entry { SevenZip.Entry(path: path, size: size) }

    func plan(_ entries: [SevenZip.Entry]) throws -> UnarchivePlan {
        try ROMArchiver.unarchivePlan(listing: entries, archive: archive, romName: "ICO", folder: folder)
    }

    @Test func everythingInTheArchiveIsKept() throws {
        let p = try plan([entry("ICO (USA).bin", 638), entry("readme.html", 1)])

        #expect(p.entries.map(\.path) == ["ICO (USA).bin", "readme.html"])
        #expect(p.bytesNeeded == 639)
        #expect(p.destination == URL(filePath: "/Games/PS2/ICO", directoryHint: .isDirectory))
    }

    @Test func aCueSheetWithItsTracksIsAGame() throws {
        _ = try plan([entry("ICO.cue", 1), entry("ICO (Track 1).bin"), entry("ICO (Track 2).bin")])
    }

    @Test func severalImagesWithoutACueSheetAreRefused() {
        #expect(throws: ArchiveError.ambiguous(["ICO.iso", "ICO (Demo).iso"])) {
            try plan([entry("ICO.iso"), entry("ICO (Demo).iso")])
        }
    }

    @Test func anArchiveWithNoImageIsRefused() {
        #expect(throws: ArchiveError.noImage) { try plan([entry("readme.txt")]) }
    }
}

@Suite struct DiscUnarchivePlanTests {
    let ps1 = ROMFolder.platform(7, URL(filePath: "/Games/PS1", directoryHint: .isDirectory))!
    let archive = URL(filePath: "/Games/PS1/Final Fantasy VII (USA).7z")

    func plan(_ paths: [String]) throws -> UnarchivePlan {
        try ROMArchiver.unarchivePlan(
            listing: paths.map { SevenZip.Entry(path: $0, size: 100) }, archive: archive, romName: "Final Fantasy VII (USA)", folder: ps1)
    }

    @Test func aPlaylistWithItsDiscsIsAGame() throws {
        let p = try plan([
            "Final Fantasy VII (USA).m3u", "Final Fantasy VII (USA) (Disc 1).cue", "Final Fantasy VII (USA) (Disc 1).bin",
            "Final Fantasy VII (USA) (Disc 2).cue", "Final Fantasy VII (USA) (Disc 2).bin",
        ])

        #expect(p.destination == URL(filePath: "/Games/PS1/Final Fantasy VII (USA)", directoryHint: .isDirectory))
    }

    @Test func discsWithoutAPlaylistAreAGame() throws {
        let p = try plan(["Final Fantasy VII (USA) (Disc 1).cue", "Final Fantasy VII (USA) (Disc 2).cue", "a.bin", "b.bin"])

        #expect(p.entries.count == 4)
    }

    @Test func twoPlaylistsAreRefused() {
        #expect(throws: ArchiveError.ambiguous(["a.m3u", "b.m3u", "a.cue"])) { try plan(["a.m3u", "b.m3u", "a.cue"]) }
    }
}

@Suite(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
struct ROMArchiverTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "archiver \(UUID().uuidString)", directoryHint: .isDirectory)
    let ps2: FakeROMFolder
    let trash: URL

    init() throws {
        ps2 = try FakeROMFolder(in: directory)
        trash = directory.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    func archiver(freeSpace: Int64 = .max) -> ROMArchiver {
        let trash = trash
        return ROMArchiver(
            sevenZip: SevenZip.find()!, freeSpace: { _ in freeSpace },
            moveToTrash: { try FileManager.default.moveItem(at: $0, to: trash.appending(path: $0.lastPathComponent)) })
    }

    func trashed() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: trash.path(percentEncoded: false)).sorted() }

    @Test func archivingPacksTheImageAndTrashesIt() async throws {
        try ps2.add("ICO.bin", String(repeating: "PS2", count: 10_000))

        try await archiver().archive("ICO", in: ps2.folder)

        #expect(try ps2.folder.scan().map(\.archived) == [true])
        #expect(try trashed() == ["ICO.bin"])
    }

    @Test func unarchivingPutsEverythingInAFolderNamedAfterTheROMAndTrashesTheArchive() async throws {
        try ps2.add("ICO.bin", String(repeating: "PS2", count: 10_000))
        try await archiver().archive("ICO", in: ps2.folder)
        let archive = try #require(try ps2.folder.scan().first?.archive)

        try await archiver().unarchive(archive, romName: "ICO", in: ps2.folder)

        let rom = try #require(try ps2.folder.scan().first)
        #expect(rom.name == "ICO")
        #expect(!rom.archived)
        #expect(rom.fileName == "ICO/ICO.bin")
        #expect(try String(contentsOf: rom.ready!, encoding: .utf8) == String(repeating: "PS2", count: 10_000))
        #expect(try trashed() == ["ICO.7z", "ICO.bin"])
    }

    @Test func archivingAROMsFolderPacksItsContentsAndTrashesTheFolder() async throws {
        try ps2.add("ICO/ICO (USA).bin", "image")
        try ps2.add("ICO/readme.html", "readme")

        try await archiver().archive("ICO", in: ps2.folder)
        #expect(try ps2.folder.scan().map(\.archived) == [true])
        #expect(try trashed() == ["ICO"])
        try await archiver().unarchive(ps2.url.appending(path: "ICO.7z"), romName: "ICO", in: ps2.folder)

        #expect(try ps2.folder.scan().first?.fileName == "ICO/ICO (USA).bin")
        #expect(FileManager.default.fileExists(atPath: ps2.url.appending(path: "ICO/readme.html").path(percentEncoded: false)))
    }

    @Test func anArchivesContentsCanBeListedWithoutUnarchivingIt() async throws {
        try ps2.add("ICO/ICO.bin", "image")
        try ps2.add("ICO/readme.html", "readme")
        try await archiver().archive("ICO", in: ps2.folder)

        let contents = try await SevenZip.find()!.contents(of: ps2.url.appending(path: "ICO.7z"))

        #expect(contents.map(\.path).sorted() == ["ICO.bin", "readme.html"])
        #expect(contents.first { $0.path == "ICO.bin" }?.size == 5)
    }

    @Test func aFileOnThisDiskIsOnDisk() throws {
        let file = try ps2.add("ICO.7z")

        #expect(SevenZip.isOnDisk(file))
    }

    @Test func withoutEnoughSpaceNothingHappens() async throws {
        try ps2.add("ICO.bin", String(repeating: "PS2", count: 1000))

        await #expect(throws: ArchiveError.notEnoughSpace(needed: 3000)) {
            try await archiver(freeSpace: 10).archive("ICO", in: ps2.folder)
        }
        #expect(try ps2.folder.scan().map(\.archived) == [false])
        #expect(try trashed().isEmpty)
    }

    @Test func aMultiDiscPS1ROMArchivesAndUnarchivesBackToItsPlaylist() async throws {
        let ps1 = try FakeROMFolder(in: directory, platform: 7)
        try ps1.add("FF7/FF7.m3u", "FF7 (Disc 1).cue\nFF7 (Disc 2).cue\n")
        for disc in 1...2 {
            try ps1.add("FF7/FF7 (Disc \(disc)).cue", "FILE \"FF7 (Disc \(disc)).bin\" BINARY\n")
            try ps1.add("FF7/FF7 (Disc \(disc)).bin", String(repeating: "PS1", count: 1000))
        }

        try await archiver().archive("FF7", in: ps1.folder)
        #expect(try ps1.folder.scan().map(\.archived) == [true])
        try await archiver().unarchive(ps1.url.appending(path: "FF7.7z"), romName: "FF7", in: ps1.folder)

        let rom = try #require(try ps1.folder.scan().first)
        #expect(rom.fileName == "FF7/FF7.m3u")
        #expect(!rom.needsPlaylist)
    }

    @Test func aGameCubeROMUnarchivesToItsOneFile() async throws {
        let gameCube = try FakeROMFolder(in: directory, platform: 21)
        try gameCube.add("Metroid Prime (USA).rvz", String(repeating: "GC", count: 10_000))

        try await archiver().archive("Metroid Prime (USA)", in: gameCube.folder)
        #expect(try gameCube.folder.scan().map(\.fileName) == ["Metroid Prime (USA).7z"])
        try await archiver().unarchive(
            gameCube.url.appending(path: "Metroid Prime (USA).7z"), romName: "Metroid Prime (USA)", in: gameCube.folder)

        #expect(try gameCube.folder.scan().map(\.fileName) == ["Metroid Prime (USA).rvz"])
    }

    @Test func leftoversFromAnInterruptedTaskAreCleanedUp() throws {
        let leftover = ps2.url.appending(path: ROMArchiver.workFolderName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)

        ROMArchiver.cleanUp(ps2.folder)

        #expect(!FileManager.default.fileExists(atPath: leftover.path(percentEncoded: false)))
    }
}

@Suite struct ArchiveSavingTests {
    @Test func theSavingIsHowMuchSmallerTheArchiveIsThanWhatsInsideIt() {
        #expect(SevenZip.saving(archiveSize: 250, unpacked: 1000) == 0.75)
    }

    @Test func anArchiveBiggerThanWhatsInsideItSavesLessThanNothing() {
        #expect(SevenZip.saving(archiveSize: 110, unpacked: 100) == -0.1)
    }

    @Test func anArchiveWithNothingInsideHasNoSaving() {
        #expect(SevenZip.saving(archiveSize: 32, unpacked: 0) == nil)
    }
}
