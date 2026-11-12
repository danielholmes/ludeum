import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// The one-off making Legacy Mobile Device Games' jar Attachments ROMs (ADR 0044), deleted with it once it has run.
@Suite struct MobileAttachmentsMigrationTests {
    let j: LudeumHarness
    let ludeum: LudeumFolder
    let picked: URL
    let trash: URL
    var folder: ROMFolder { .platform(ROMPlatform.legacyMobile, ludeum.romFolder(platform: ROMPlatform.legacyMobile)!)! }

    init() throws {
        j = try LudeumHarness()
        ludeum = LudeumFolder(url: j.directory, data: j.directory.appending(path: "Data", directoryHint: .isDirectory))
        picked = j.directory.appending(path: "Downloads", directoryHint: .isDirectory)
        trash = j.directory.appending(path: "Trash", directoryHint: .isDirectory)
        for folder in [picked, trash] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try j.journal.addPlatform(id: ROMPlatform.legacyMobile, name: "Legacy Mobile Device")
    }

    var moveToTrash: @Sendable (URL) throws -> Void {
        let trash = trash
        return { file in
            try FileManager.default.moveItem(at: file, to: trash.appending(path: "\(UUID().uuidString) \(file.lastPathComponent)"))
        }
    }

    /// A Game with these files as its Attachments.
    @discardableResult
    func game(_ name: String, attaching files: [String]) throws -> GameID {
        let game = try j.journal.addGame(platformId: ROMPlatform.legacyMobile, name: name)
        let urls = try files.map { file in
            let url = picked.appending(path: file)
            try Data(file.utf8).write(to: url)
            return url
        }
        try Attachments(journal: j.journal, root: ludeum.attachments).add(urls, to: game)
        return game
    }

    var migration: MobileAttachmentsMigration {
        MobileAttachmentsMigration(journal: j.journal, ludeum: ludeum, folder: folder, moveToTrash: moveToTrash)
    }

    func romNames(of game: GameID) throws -> [String] {
        try j.journal.db.read { db in
            try String.fetchAll(db, sql: "SELECT folderName FROM rom WHERE gameId = ? ORDER BY folderName", arguments: [game])
        }
    }

    @Test func eachJarBecomesARomUnderItsGamesNameAndItsAttachmentGoes() async throws {
        let genesis = try game("Resident Evil: Genesis", attaching: ["residentev_asvd7ay4.jar", "Manual.pdf"])

        let plan = try migration.plan()
        #expect(plan.roms.map(\.name) == ["Resident Evil - Genesis"])
        try await migration.run(plan) { _ in }

        #expect(try romNames(of: genesis) == ["Resident Evil - Genesis"])
        #expect(
            try Data(contentsOf: folder.url.appending(path: "Resident Evil - Genesis.jar")) == Data("residentev_asvd7ay4.jar".utf8))
        // The manual stays.
        #expect(try Attachments(journal: j.journal, root: ludeum.attachments).attachments(of: genesis).map(\.fileName) == ["Manual.pdf"])
    }

    @Test func numberedFilesAreOneROMOfDiscsInOrder() async throws {
        let report = try game(
            "Resident Evil: Confidential Report",
            attaching: (1...3).reversed().map { "Resident Evil - Confidential Report (File \($0)).jar" })

        try await migration.run(try migration.plan()) { _ in }

        let name = "Resident Evil - Confidential Report"
        #expect(try romNames(of: report) == [name])
        let playlist = folder.url.appending(path: "\(name)/\(name).m3u")
        #expect(try String(contentsOf: playlist, encoding: .utf8) == (1...3).map { "\(name) (Disc \($0)).jar\n" }.joined())
        #expect(
            try Data(contentsOf: folder.url.appending(path: "\(name)/\(name) (Disc 2).jar"))
                == Data("Resident Evil - Confidential Report (File 2).jar".utf8))
        #expect(try Attachments(journal: j.journal, root: ludeum.attachments).attachments(of: report).isEmpty)
        // Its folder went, with the Platform's, and only the run's own backup was taken.
        #expect(
            !FileManager.default.fileExists(atPath: ludeum.attachments.appending(path: "Legacy Mobile Device").path(percentEncoded: false)))
        let folderName = try await j.journal.db.read { db in
            try String?.fetchOne(db, sql: "SELECT attachmentFolder FROM game WHERE id = ?", arguments: [report]) ?? nil
        }
        #expect(folderName == nil)
    }

    @Test func aSecondJarIsAnAlt() async throws {
        let degeneration = try game("Resident Evil: Degeneration", attaching: ["residentev_hjkx7cni.jar", "residentev_vm3cc428.jar"])

        try await migration.run(try migration.plan()) { _ in }

        #expect(try romNames(of: degeneration) == ["Resident Evil - Degeneration", "Resident Evil - Degeneration (Alt)"])
        #expect(
            try Data(contentsOf: folder.url.appending(path: "Resident Evil - Degeneration (Alt).jar"))
                == Data("residentev_vm3cc428.jar".utf8))
    }

    @Test func aMissingFileIsLeft() throws {
        try game("Resident Evil: Uprising", attaching: ["resident_evil_upris_259530.jar"])
        try j.journal.db.write { db in try db.execute(sql: "UPDATE attachment SET missing = 1") }

        let plan = try migration.plan()

        #expect(plan.roms.isEmpty)
        #expect(plan.left.map(\.what) == ["resident_evil_upris_259530.jar"])
    }
}
