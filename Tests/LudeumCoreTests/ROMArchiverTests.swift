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

    @Test func oneImageNamedLikeTheROMNeedsNothingConfirmed() throws {
        let p = try plan([entry("ICO.bin", 638)])

        #expect(p.kept.map(\.path) == ["ICO.bin"])
        #expect(p.discarded.isEmpty)
        #expect(!p.needsRename)
        #expect(p.bytesNeeded == 638)
    }

    @Test func filesThatArentTheGameAreDiscarded() throws {
        let p = try plan([entry("ICO.bin"), entry("readme.html", 1)])

        #expect(p.kept.map(\.path) == ["ICO.bin"])
        #expect(p.discarded == ["readme.html"])
    }

    @Test func anImageNamedDifferentlyAsksToBeRenamed() throws {
        let p = try plan([entry("ICO (USA)/ICO (USA).iso")])

        #expect(p.needsRename)
        #expect(p.mainFile == "ICO (USA).iso")
        #expect(p.renamedMainFile == "ICO.iso")
    }

    @Test func aCueSheetKeepsItsTracks() throws {
        let p = try plan([entry("ICO.cue", 1), entry("ICO (Track 1).bin"), entry("ICO (Track 2).bin"), entry("cover.jpg")])

        #expect(p.kept.map(\.path) == ["ICO.cue", "ICO (Track 1).bin", "ICO (Track 2).bin"])
        #expect(p.mainFile == "ICO.cue")
        #expect(p.discarded == ["cover.jpg"])
    }

    @Test func aCueSheetKeepsOnlyItsTracksNotOtherImages() throws {
        let p = try plan([entry("ICO.cue", 1), entry("ICO.bin"), entry("ICO (Demo).iso")])

        #expect(p.kept.map(\.path) == ["ICO.cue", "ICO.bin"])
        #expect(p.discarded == ["ICO (Demo).iso"])
    }

    @Test func filesThatWouldLandOnTheSameNameAreRefused() {
        #expect(throws: ArchiveError.ambiguous(["Track 1.bin", "Track 1.bin"])) {
            try plan([entry("ICO.cue", 1), entry("CD1/Track 1.bin"), entry("CD2/Track 1.bin")])
        }
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

    @Test func unarchivingExtractsTheImageAndTrashesTheArchive() async throws {
        try ps2.add("ICO.bin", String(repeating: "PS2", count: 10_000))
        try await archiver().archive("ICO", in: ps2.folder)
        let archive = try #require(try ps2.folder.scan().first?.archive)
        let plan = try await archiver().planUnarchive(archive, romName: "ICO", in: ps2.folder)

        try await archiver().unarchive(plan, renaming: false, in: ps2.folder)

        let rom = try #require(try ps2.folder.scan().first)
        #expect(!rom.archived)
        #expect(try String(contentsOf: rom.ready!, encoding: .utf8) == String(repeating: "PS2", count: 10_000))
        #expect(try trashed() == ["ICO.7z", "ICO.bin"])
    }

    @Test func unarchivingCanRenameTheImageToTheROMsName() async throws {
        try ps2.add("ICO (USA).iso", "image")
        try await archiver().archive("ICO (USA)", in: ps2.folder)
        try FileManager.default.moveItem(at: ps2.url.appending(path: "ICO (USA).7z"), to: ps2.url.appending(path: "ICO.7z"))
        let plan = try await archiver().planUnarchive(ps2.url.appending(path: "ICO.7z"), romName: "ICO", in: ps2.folder)
        #expect(plan.needsRename)

        try await archiver().unarchive(plan, renaming: true, in: ps2.folder)

        #expect(try ps2.folder.scan().map(\.name) == ["ICO"])
        #expect(try ps2.folder.readyFile(named: "ICO")?.lastPathComponent == "ICO.iso")
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
