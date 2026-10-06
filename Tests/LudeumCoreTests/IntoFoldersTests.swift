import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// `into-folders`: each loose ROM of a disc Platform moves into a subfolder named after it.
@Suite struct IntoFoldersTests {
    let h: Harness
    let j: LudeumHarness
    /// Stands in for the Data folder: the real one is never touched.
    let data: URL
    let ps1: FakeROMFolder

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        data = j.directory.appending(path: "Data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: data.appending(path: "Backups"), withIntermediateDirectories: true)
        ps1 = try FakeROMFolder(at: LudeumFolder(url: j.directory, data: data).romFolder(platform: 7)!, platform: 7)
        try j.journal.addPlatform(id: 7, name: "PlayStation")
    }

    var intoFolders: IntoFolders { IntoFolders(journal: j.journal, folder: LudeumFolder(url: j.directory, data: data), libretro: nil) }

    /// A cue sheet and its one track, loose.
    func addCue(_ name: String) throws {
        try ps1.add("\(name).bin")
        try ps1.add("\(name).cue", "FILE \"\(name).bin\" BINARY\n")
    }

    /// A ROM row as an Import left it, Matched to `game` if given.
    @discardableResult
    func row(_ name: String, fileName: String? = nil, game: GameID? = nil) throws -> Int64 {
        try j.journal.db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO rom (folderName, fileName, name, platformId, discNumber, gameId, matchKind, matchedAt)
                    VALUES (?, ?, ?, 7, ?, ?, ?, ?)
                    """,
                arguments: [
                    name, fileName ?? "\(name).cue", name, ROMName(name).disc, game, game.map { _ in "confirmed" },
                    game.map { _ in Date() },
                ])
            return db.lastInsertedRowID
        }
    }

    func rows() throws -> [Row] {
        try j.journal.db.read { try Row.fetchAll($0, sql: "SELECT * FROM rom ORDER BY id") }
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: ps1.url.appending(path: path).path(percentEncoded: false))
    }

    @Test func aCueSheetMovesWithItsTracksIntoItsFolderAndKeepsItsMatch() async throws {
        let game = try j.journal.addGame(platformId: 7, name: "Ape Escape")
        try addCue("Ape Escape (USA)")
        let rom = try row("Ape Escape (USA)", game: game)

        try await intoFolders.run()

        #expect(exists("Ape Escape (USA)/Ape Escape (USA).cue"))
        #expect(exists("Ape Escape (USA)/Ape Escape (USA).bin"))
        #expect(!exists("Ape Escape (USA).cue"))
        let after = try #require(try rows().first)
        #expect(after["id"] as Int64 == rom)
        #expect(after["gameId"] as GameID? == game)
        #expect(after["fileName"] as String == "Ape Escape (USA)/Ape Escape (USA).cue")
    }

    @Test func aPlaylistAndItsDiscsBecomeOneROM() async throws {
        let game = try j.journal.addGame(platformId: 7, name: "Fear Effect")
        try addCue("Fear Effect (Disc 1)")
        try addCue("Fear Effect (Disc 2)")
        try ps1.add("Fear Effect.m3u", "Fear Effect (Disc 1).cue\nFear Effect (Disc 2).cue")
        let playlist = try row("Fear Effect", fileName: "Fear Effect.m3u", game: game)
        try row("Fear Effect (Disc 1)", game: game)
        try row("Fear Effect (Disc 2)", game: game)

        try await intoFolders.run()

        #expect(exists("Fear Effect/Fear Effect.m3u"))
        #expect(exists("Fear Effect/Fear Effect (Disc 2).bin"))
        let after = try rows()
        #expect(after.map { $0["id"] as Int64 } == [playlist])
        #expect(after[0]["fileName"] as String == "Fear Effect/Fear Effect.m3u")
        #expect(try ps1.folder.scan().map(\.name) == ["Fear Effect"])
    }

    @Test func discsWithNoPlaylistBecomeOneROMWaitingForOne() async throws {
        let game = try j.journal.addGame(platformId: 7, name: "Gran Turismo 2")
        try addCue("Gran Turismo 2 (Europe) (Disc 1) (Arcade Mode Disc)")
        try addCue("Gran Turismo 2 (Europe) (En,Fr,De,Es,It) (Disc 2) (Gran Turismo Mode)")
        let disc1 = try row("Gran Turismo 2 (Europe) (Disc 1) (Arcade Mode Disc)", game: game)
        try row("Gran Turismo 2 (Europe) (En,Fr,De,Es,It) (Disc 2) (Gran Turismo Mode)", game: game)

        let plan = try intoFolders.plan()
        #expect(plan.folders.map(\.name) == ["Gran Turismo 2 (Europe)"])
        #expect(plan.folders.first?.needsPlaylist == true)
        try await intoFolders.run()

        let after = try rows()
        #expect(after.count == 1)
        #expect(after[0]["id"] as Int64 == disc1)
        #expect(after[0]["gameId"] as GameID? == game)
        #expect(after[0]["folderName"] as String == "Gran Turismo 2 (Europe)")
        #expect(after[0]["discNumber"] as Int? == nil)
        #expect(after[0]["needsPlaylist"] as Bool == true)
        #expect(
            try j.journal.reviewQueue().noPlaylist == [NoPlaylistItem(romId: disc1, romName: "Gran Turismo 2 (Europe)", platformId: 7)])
    }

    @Test func discsMatchedToAnotherGameThanTheirPlaylistAreLeftLoose() async throws {
        let original = try j.journal.addGame(platformId: 7, name: "Resident Evil 2")
        let dualShock = try j.journal.addGame(platformId: 7, name: "Resident Evil 2: Dual Shock Ver.")
        try addCue("Resident Evil 2 (USA) (Disc 1) (Leon)")
        try ps1.add("Resident Evil 2.m3u", "Resident Evil 2 (USA) (Disc 1) (Leon).cue")
        try row("Resident Evil 2", fileName: "Resident Evil 2.m3u", game: original)
        try row("Resident Evil 2 (USA) (Disc 1) (Leon)", game: dualShock)

        let plan = try intoFolders.plan()
        try await intoFolders.run()

        #expect(plan.leftLoose == ["PS1/Resident Evil 2: its ROMs are Matched to different Games"])
        #expect(exists("Resident Evil 2.m3u"))
        #expect(exists("Resident Evil 2 (USA) (Disc 1) (Leon).cue"))
        #expect(try rows().count == 2)
    }

    @Test func aSubfolderAlreadyThereStopsTheRunBeforeAnythingMoves() async throws {
        try addCue("Ape Escape (USA)")
        try addCue("Crash Bandicoot (USA)")
        try ps1.add("Ape Escape (USA)/readme.txt")

        let plan = try intoFolders.plan()

        #expect(plan.clashes == ["PS1/Ape Escape (USA): already a ROM or folder there"])
        await #expect(throws: IntoFoldersError.self) { try await intoFolders.run() }
        #expect(exists("Crash Bandicoot (USA).cue"))
    }

    @Test func theDryRunChangesNothing() throws {
        try addCue("Ape Escape (USA)")

        let plan = try intoFolders.plan()

        #expect(plan.folders.first?.moves.count == 2)
        #expect(exists("Ape Escape (USA).cue"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: data.appending(path: "Backups").path(percentEncoded: false)).isEmpty)
    }

    @Test func anArchiveStaysLooseBesideItsFolder() async throws {
        try addCue("Ape Escape (USA)")
        try ps1.add("Ape Escape (USA).7z")

        try await intoFolders.run()

        #expect(exists("Ape Escape (USA).7z"))
        #expect(try ps1.folder.scan().first?.archive != nil)
    }

    @Test func itBacksUpFirstAndLogsEachMove() async throws {
        try addCue("Ape Escape (USA)")

        let result = try await intoFolders.run()

        #expect(result.backup.lastPathComponent.hasSuffix("before-into-folders.sqlite"))
        let log = try String(contentsOf: result.log, encoding: .utf8)
        #expect(log.split(separator: "\n").count == 2)
    }
}
