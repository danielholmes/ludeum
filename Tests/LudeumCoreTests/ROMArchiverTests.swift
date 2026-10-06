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

    @Test func leftoversFromAnInterruptedTaskAreCleanedUp() throws {
        let leftover = ps2.url.appending(path: ROMArchiver.workFolderName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)

        ROMArchiver.cleanUp(ps2.folder)

        #expect(!FileManager.default.fileExists(atPath: leftover.path(percentEncoded: false)))
    }
}
