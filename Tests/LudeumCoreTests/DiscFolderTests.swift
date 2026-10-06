import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// A multi-disc Version kept in one subfolder: its playlist and its Discs, or its Discs waiting for a playlist.
@Suite struct DiscFolderScanTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "disc folder \(UUID().uuidString)")

    /// Fear Effect's Discs in its subfolder, each a cue sheet with its track.
    func fearEffect(in ps1: FakeROMFolder) throws -> [URL] {
        try (1...2).map { n in
            try ps1.add("Fear Effect (USA)/Fear Effect (USA) (Disc \(n)).bin")
            return try ps1.add("Fear Effect (USA)/Fear Effect (USA) (Disc \(n)).cue", "FILE \"Fear Effect (USA) (Disc \(n)).bin\" BINARY\n")
        }
    }

    @Test func aSubfolderWithAPlaylistPlaysThePlaylist() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: 7)
        try fearEffect(in: ps1)
        let playlist = try ps1.add(
            "Fear Effect (USA)/Fear Effect (USA).m3u", "Fear Effect (USA) (Disc 1).cue\nFear Effect (USA) (Disc 2).cue\n")

        let scanned = try ps1.folder.scan()

        #expect(scanned == [FolderROMFile(name: "Fear Effect (USA)", ready: playlist, archive: nil)])
        #expect(scanned.first?.fileName == "Fear Effect (USA)/Fear Effect (USA).m3u")
        #expect(scanned.first?.needsPlaylist == false)
    }

    @Test func aSubfolderOfDiscsWithNoPlaylistOpensDiscOneAndNeedsOne() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: 7)
        let discs = try fearEffect(in: ps1)

        let scanned = try #require(try ps1.folder.scan().first)

        #expect(scanned.name == "Fear Effect (USA)")
        #expect(scanned.ready == discs[0])
        #expect(scanned.discsWithoutPlaylist == discs)
        #expect(scanned.needsPlaylist)
    }

    @Test func severalCueSheetsThatArentDiscsArentAROM() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: 7)
        try ps1.add("Fear Effect (USA)/Fear Effect (USA).cue")
        try ps1.add("Fear Effect (USA)/Fear Effect (USA) (Demo).cue")

        #expect(try ps1.folder.scan().isEmpty)
    }

    @Test func discsWithARepeatedNumberArentAROM() throws {
        let ps1 = try FakeROMFolder(in: directory, platform: 7)
        try ps1.add("Fear Effect/Fear Effect (USA) (Disc 1).cue")
        try ps1.add("Fear Effect/Fear Effect (Europe) (Disc 1).cue")

        #expect(try ps1.folder.scan().isEmpty)
    }

    @Test func aPlatformThatDoesntReadPlaylistsIgnoresThem() throws {
        let gameCube = try FakeROMFolder(in: directory, platform: 21)
        try gameCube.add("Resident Evil/Resident Evil.m3u")
        let disc1 = try gameCube.add("Resident Evil/Resident Evil (USA) (Disc 1).rvz")
        try gameCube.add("Resident Evil/Resident Evil (USA) (Disc 2).rvz")

        #expect(try gameCube.folder.scan().first?.ready == disc1)
    }
}

@Suite struct DiscFolderReviewTests {
    let h: Harness
    let j: LudeumHarness
    let ps1: FakeROMFolder

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        ps1 = try FakeROMFolder(in: h.directory, platform: 7)
        h.internet.addPlatform(7, "PlayStation")
    }

    func importNow() async throws {
        _ = try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil).run(romFolders: [ps1.folder])
    }

    func rom() throws -> Row {
        try j.journal.db.read { try Row.fetchOne($0, sql: "SELECT * FROM rom")! }
    }

    func addDiscs() throws {
        for n in [2, 1] { try ps1.add("Fear Effect (USA)/Disc \(n)/Fear Effect (USA) (Disc \(n)).cue") }
    }

    @Test func discsWithNoPlaylistWaitInTheReviewQueue() async throws {
        try addDiscs()

        try await importNow()

        let items = try j.journal.reviewQueue()
        #expect(items.noPlaylist == [NoPlaylistItem(romId: try rom()["id"], romName: "Fear Effect (USA)", platformId: 7)])
        #expect(items.count == 2)  // and, unmatched, in No suggestion
        #expect(try rom()["fileName"] as String == "Fear Effect (USA)/Disc 1/Fear Effect (USA) (Disc 1).cue")
    }

    @Test func makePlaylistWritesOneLoadingTheDiscsInOrder() async throws {
        try addDiscs()
        try await importNow()
        let item = try #require(try j.journal.reviewQueue().noPlaylist.first)

        try j.journal.makePlaylist(item, romFolders: [ps1.folder])

        let playlist = ps1.url.appending(path: "Fear Effect (USA)/Fear Effect (USA).m3u")
        #expect(
            try String(contentsOf: playlist, encoding: .utf8)
                == "Disc 1/Fear Effect (USA) (Disc 1).cue\nDisc 2/Fear Effect (USA) (Disc 2).cue\n")
        #expect(try rom()["fileName"] as String == "Fear Effect (USA)/Fear Effect (USA).m3u")
        #expect(try j.journal.reviewQueue().noPlaylist.isEmpty)
    }

    @Test func makePlaylistTwiceIsRefused() async throws {
        try addDiscs()
        try await importNow()
        let item = try #require(try j.journal.reviewQueue().noPlaylist.first)
        try j.journal.makePlaylist(item, romFolders: [ps1.folder])

        #expect(throws: ReviewError.noDiscsWithoutPlaylist) { try j.journal.makePlaylist(item, romFolders: [ps1.folder]) }
    }

    @Test func aPlaylistAddedByHandClearsTheItemOnTheNextImport() async throws {
        try addDiscs()
        try await importNow()
        try ps1.add("Fear Effect (USA)/Fear Effect (USA).m3u", "Disc 1/Fear Effect (USA) (Disc 1).cue\n")

        try await importNow()

        #expect(try j.journal.reviewQueue().noPlaylist.isEmpty)
    }

    @Test func playWaitsForThePlaylist() {
        var rom = folderROM("Fear Effect (USA)", fileName: "Fear Effect (USA)/Fear Effect (USA) (Disc 1).cue")
        rom.needsPlaylist = true
        let play = Play(platformId: 7, platformName: "PlayStation", roms: [rom], settings: EmulatorSettings())

        #expect(play.availability == .refused(.needsPlaylist))
        #expect(play.availability.refusal?.message == "Its Discs have no playlist: make one in the Review queue")
    }
}
