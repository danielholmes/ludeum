import Foundation
import Testing

@testable import LudeumCore

/// Delete ROM from the Review queue: an unmatched ROM's files go to the Trash and it's forgotten.
@Suite struct DeleteROMTests {
    let h: Harness
    let j: LudeumHarness
    let snes: FakeROMFolder
    let trash: URL

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        snes = try FakeROMFolder(in: h.directory, platform: 19)
        trash = h.directory.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        h.internet.addPlatform(19, "Super Nintendo Entertainment System")
    }

    /// Imports the ROM folder, then the No suggestion item named `name`.
    func item(_ name: String) async throws -> ReviewItem {
        _ = try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil).run(romFolders: [snes.folder])
        return try #require(try j.journal.reviewQueue().noSuggestion.first { $0.romName == name })
    }

    /// Deletes the ROM, the Trash being a folder the test can look in.
    func delete(_ item: ReviewItem) throws {
        let trash = trash
        try j.journal.deleteROM(item, romFolders: [snes.folder]) {
            try FileManager.default.moveItem(at: $0, to: trash.appending(path: $0.lastPathComponent))
        }
    }

    func trashed() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: trash.path(percentEncoded: false)).sorted() }

    @Test func deletingAROMTrashesItsFilesAndForgetsIt() async throws {
        try snes.add("Bootleg Thing (USA).sfc")
        try snes.add("Other Thing (USA).sfc")

        try delete(try await item("Bootleg Thing (USA)"))

        #expect(try trashed() == ["Bootleg Thing (USA).sfc"])
        #expect(try snes.folder.scan().map(\.fileName) == ["Other Thing (USA).sfc"])
        #expect(try j.journal.reviewQueue().noSuggestion.map(\.romName) == ["Other Thing (USA)"])
    }

    @Test func aMissingROMIsJustForgotten() async throws {
        try snes.add("Bootleg Thing (USA).sfc")
        let item = try await item("Bootleg Thing (USA)")
        try snes.remove("Bootleg Thing (USA).sfc")
        _ = try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil).run(romFolders: [snes.folder])

        try delete(try #require(try j.journal.reviewQueue().noSuggestion.first { $0.id == item.id }))

        #expect(try trashed().isEmpty)
        #expect(try j.journal.reviewQueue().noSuggestion.isEmpty)
    }

    @Test func deletingIsRefusedOnceTheROMIsMatched() async throws {
        try snes.add("Bootleg Thing (USA).sfc")
        let item = try await item("Bootleg Thing (USA)")
        try j.journal.assign(item, to: try j.journal.addGame(platformId: 19, name: "Bootleg Thing"))

        #expect(throws: ReviewError.alreadyMatched) { try delete(item) }

        #expect(try trashed().isEmpty)
        #expect(try snes.folder.scan().count == 1)
    }

    @Test func deletingIsRefusedWithNothingTrashedWhenItsFilesAreGone() async throws {
        try snes.add("Bootleg Thing (USA).sfc")
        let item = try await item("Bootleg Thing (USA)")
        try snes.remove("Bootleg Thing (USA).sfc")

        #expect(throws: ReviewError.romFilesNotFound) { try delete(item) }

        #expect(try j.journal.reviewQueue().noSuggestion.map(\.id) == [item.id])
    }
}
