import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// Resolving Duplicate Versions from the Review queue: Split a Version into its own Game, or Keep only one Version.
@Suite struct DuplicateVersionsTests {
    let h: Harness
    let j: LudeumHarness
    let snes: FakeROMFolder
    let gameCube: FakeROMFolder
    let trash: URL

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        snes = try FakeROMFolder(in: h.directory, platform: 19)
        gameCube = try FakeROMFolder(in: h.directory, platform: 21)
        trash = h.directory.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        h.internet.addPlatform(19, "Super Nintendo Entertainment System")
        h.internet.addPlatform(21, "Nintendo GameCube")
    }

    var romFolders: [ROMFolder] { [snes.folder, gameCube.folder] }

    /// Imports the ROM folders, then Matches every ROM to one new Game on the Platform, giving it Duplicate Versions.
    func duplicates(on platform: Int64, _ name: String) async throws -> DuplicateVersionsGame {
        _ = try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil).run(romFolders: romFolders)
        let game = try j.journal.addGame(platformId: platform, name: name)
        for item in try j.journal.reviewQueue().noSuggestion where item.platformId == platform {
            try j.journal.assign(item, to: game)
        }
        return try #require(try j.journal.reviewQueue().duplicateVersions.first { $0.game.id == game })
    }

    func version(_ item: DuplicateVersionsGame, containing name: String) throws -> [LudeumROM] {
        try #require(item.versions.first { $0.contains { $0.name.contains(name) } })
    }

    /// Keeps only one Version, the Trash being a folder the test can look in.
    func keepOnly(_ version: [LudeumROM], of item: DuplicateVersionsGame) throws {
        let trash = trash
        try j.journal.keepOnly(version, of: item, romFolders: romFolders) {
            try FileManager.default.moveItem(at: $0, to: trash.appending(path: $0.lastPathComponent))
        }
    }

    func trashed() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: trash.path(percentEncoded: false)).sorted() }

    @Test func anItemGroupsItsROMsIntoVersionsWithAMultiDiscVersionsDiscsTogether() async throws {
        try gameCube.add("Tales of Symphonia (USA) (Disc 1).rvz")
        try gameCube.add("Tales of Symphonia (USA) (Disc 2).rvz")
        try gameCube.add("Tales of Symphonia (Europe).rvz")

        let item = try await duplicates(on: 21, "Tales of Symphonia")

        #expect(
            item.versions.map { $0.map(\.fileName) } == [
                ["Tales of Symphonia (USA) (Disc 1).rvz", "Tales of Symphonia (USA) (Disc 2).rvz"],
                ["Tales of Symphonia (Europe).rvz"],
            ])
    }

    @Test func splittingAVersionOffLeavesItUnmatchedInTheReviewQueue() async throws {
        try snes.add("Double Dragon III (Japan).7z")
        try snes.add("Double Dragon III (USA).7z")
        let item = try await duplicates(on: 19, "Double Dragon III")

        try j.journal.splitOff(try version(item, containing: "USA"), from: item)

        let queue = try j.journal.reviewQueue()
        #expect(queue.duplicateVersions.isEmpty)
        #expect(queue.noSuggestion.map(\.romName) == ["Double Dragon III (USA)"])
        #expect(try j.journal.roms(of: item.game.id).map(\.fileName) == ["Double Dragon III (Japan).7z"])
        #expect(try snes.folder.scan().count == 2)
    }

    @Test func splittingAMultiDiscVersionOffTakesAllItsDiscs() async throws {
        try gameCube.add("Tales of Symphonia (USA) (Disc 1).rvz")
        try gameCube.add("Tales of Symphonia (USA) (Disc 2).rvz")
        try gameCube.add("Tales of Symphonia (Europe).rvz")
        let item = try await duplicates(on: 21, "Tales of Symphonia")

        try j.journal.splitOff(try version(item, containing: "Disc"), from: item)

        #expect(try j.journal.reviewQueue().noSuggestion.count == 2)
        #expect(try j.journal.roms(of: item.game.id).map(\.fileName) == ["Tales of Symphonia (Europe).rvz"])
    }

    @Test func keepingOneVersionTrashesTheOthersAndDeletesThem() async throws {
        try snes.add("Double Dragon III (Japan).7z")
        try snes.add("Double Dragon III (USA).7z")
        try snes.add("Double Dragon III (Europe).sfc")
        let item = try await duplicates(on: 19, "Double Dragon III")

        try keepOnly(try version(item, containing: "USA"), of: item)

        #expect(try trashed() == ["Double Dragon III (Europe).sfc", "Double Dragon III (Japan).7z"])
        #expect(try snes.folder.scan().map(\.fileName) == ["Double Dragon III (USA).7z"])
        #expect(try j.journal.roms(of: item.game.id).map(\.fileName) == ["Double Dragon III (USA).7z"])
        let queue = try j.journal.reviewQueue()
        #expect(queue.duplicateVersions.isEmpty)
        #expect(queue.oldMissingROMs.isEmpty)
    }

    @Test func keepingAMultiDiscVersionKeepsAllItsDiscs() async throws {
        try gameCube.add("Tales of Symphonia (USA) (Disc 1).rvz")
        try gameCube.add("Tales of Symphonia (USA) (Disc 2).rvz")
        try gameCube.add("Tales of Symphonia (Europe).rvz")
        let item = try await duplicates(on: 21, "Tales of Symphonia")

        try keepOnly(try version(item, containing: "Disc"), of: item)

        #expect(try trashed() == ["Tales of Symphonia (Europe).rvz"])
        #expect(try j.journal.roms(of: item.game.id).count == 2)
    }

    @Test func keepingIsRefusedWithNothingTrashedWhenAnotherVersionsFilesAreGone() async throws {
        try snes.add("Double Dragon III (Japan).7z")
        try snes.add("Double Dragon III (USA).7z")
        try snes.add("Double Dragon III (Europe).7z")
        let item = try await duplicates(on: 19, "Double Dragon III")
        try snes.remove("Double Dragon III (Europe).7z")

        #expect(throws: ReviewError.romFilesNotFound) { try keepOnly(try version(item, containing: "USA"), of: item) }

        #expect(try trashed().isEmpty)
        #expect(try j.journal.roms(of: item.game.id).count == 3)
    }

    @Test func aROMThatReachedTheTrashBeforeAFailureIsForgottenAndTheRestStay() async throws {
        try snes.add("Double Dragon III (Europe).7z")
        try snes.add("Double Dragon III (Japan).7z")
        try snes.add("Double Dragon III (USA).7z")
        let item = try await duplicates(on: 19, "Double Dragon III")
        struct TrashFull: Error {}
        let trash = trash

        #expect(throws: TrashFull.self) {
            try j.journal.keepOnly(try version(item, containing: "USA"), of: item, romFolders: romFolders) {
                guard !$0.lastPathComponent.contains("Japan") else { throw TrashFull() }
                try FileManager.default.moveItem(at: $0, to: trash.appending(path: $0.lastPathComponent))
            }
        }

        #expect(try trashed() == ["Double Dragon III (Europe).7z"])
        #expect(
            try j.journal.roms(of: item.game.id).map(\.fileName) == ["Double Dragon III (Japan).7z", "Double Dragon III (USA).7z"])
        #expect(try j.journal.reviewQueue().oldMissingROMs.isEmpty)
    }

    @Test func bothAreRefusedWhenTheGamesVersionsHaveChangedSinceTheyWereShown() async throws {
        try snes.add("Double Dragon III (Japan).7z")
        try snes.add("Double Dragon III (USA).7z")
        try snes.add("Double Dragon III (Europe).7z")
        let item = try await duplicates(on: 19, "Double Dragon III")
        try j.journal.splitOff(try version(item, containing: "Europe"), from: item)

        #expect(throws: ReviewError.duplicateVersionsChanged) { try keepOnly(try version(item, containing: "USA"), of: item) }
        #expect(throws: ReviewError.duplicateVersionsChanged) {
            try j.journal.splitOff(try version(item, containing: "Europe"), from: item)
        }

        #expect(try trashed().isEmpty)
        #expect(try j.journal.roms(of: item.game.id).count == 2)
    }
}
