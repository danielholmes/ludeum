import Foundation
import Testing

@testable import LudeumCore

/// The one-off move from Ludeum naming each ROM's card by Serial (ADR 0023) to DuckStation naming its own (ADR 0024),
/// run by hand through `ludeum-import`.
@Suite struct DuckStationCardMigrationTests {
    let h: LudeumHarness
    let root = FileManager.default.temporaryDirectory.appending(path: "card migration \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var resources: URL { root.appending(path: "DuckStation.app/Contents/Resources", directoryHint: .isDirectory) }
    var settings: DuckStationSettings {
        DuckStationSettings(app: root.appending(path: "DuckStation.app"), dataFolder: root.appending(path: "DuckStation"), ludeum: ludeum)
    }
    var cards: URL { ludeum.duckStationMemoryCards }
    var gameSettings: URL { ludeum.duckStation(.gameSettings) }
    var migration: DuckStationCardMigration { DuckStationCardMigration(journal: h.journal, duckStation: settings, resources: resources) }

    init() throws {
        h = try LudeumHarness()
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
        try settings.writeStanding()
        try write("SLUS-00551:\n  name: \"Resident Evil - Director's Cut (USA)\"\n", to: resources.appending(path: "discdb.yaml"))
        try write("", to: resources.appending(path: "discsets.yaml"))
        try h.journal.addPlatform(id: 7, name: "PlayStation")
        let game = try h.journal.addGame(platformId: 7, name: "Resident Evil")
        try h.journal.db.write { db in
            for (name, serials) in [("Resident Evil - Director's Cut (USA)", #"["SLUS-00551"]"#), ("Ape Escape (USA)", #"["SCUS-94423"]"#)]
            {
                try db.execute(
                    sql: """
                        INSERT INTO rom (folderName, fileName, name, platformId, gameId, matchKind, matchedAt, serials, serialsLookedUp)
                        VALUES (?, ?, ?, 7, ?, 'confirmed', ?, ?, 1)
                        """, arguments: [name, "\(name)/\(name).cue", name, game, Date(), serials])
            }
        }
    }

    func write(_ text: String, to file: URL, saved: Date? = nil) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
        if let saved { try FileManager.default.setAttributes([.modificationDate: saved], ofItemAtPath: file.path(percentEncoded: false)) }
    }

    func contents(_ file: URL) -> String? { try? String(contentsOf: file, encoding: .utf8) }

    @Test func serialNamedCardsTakeDuckStationsNamesAndPerGameFilesLoseWhatEveryPlayWrote() throws {
        let older = Date(timeIntervalSince1970: 1_000_000)
        let newer = Date(timeIntervalSince1970: 2_000_000)
        // Resident Evil: Ludeum's Serial-named card, played on since it was copied from DuckStation's, which is still there.
        try write("ludeum's", to: cards.appending(path: "SLUS-00551.mcd"), saved: newer)
        try write("duckstation's", to: cards.appending(path: "Resident Evil - Director's Cut (USA)_1.mcd"), saved: older)
        // Ape Escape: a disc DuckStation's database doesn't know, so its card is named by the file Play opens.
        try write("ape", to: cards.appending(path: "SCUS-94423.mcd"))
        try write(
            "[MemoryCards]\nCard1Path = \(cards.path(percentEncoded: false))SLUS-00551.mcd\nCard1Type = Shared\n\n[BIOS]\nFastForwardBoot = true\n"
                + "PatchFastBoot = true\n\n[Main]\nRunaheadFrameCount = 1\n\n", to: gameSettings.appending(path: "SLUS-00551.ini"))
        try write("[GPU]\nResolutionScale = 4\n", to: gameSettings.appending(path: "SLPS-00001.ini"))
        let re = cards.appending(path: "Resident Evil - Director's Cut (USA)_1.mcd")

        let plan = try migration.plan()

        #expect(
            plan == [
                .stripped(gameSettings.appending(path: "SLUS-00551.ini")),
                .renamed(from: cards.appending(path: "SCUS-94423.mcd"), to: cards.appending(path: "Ape Escape (USA)_1.mcd")),
                .setAside(re, as: cards.appending(path: "Resident Evil - Director's Cut (USA)_1 (older).mcd")),
                .renamed(from: cards.appending(path: "SLUS-00551.mcd"), to: re),
            ])
        // A plan does nothing.
        #expect(contents(cards.appending(path: "SLUS-00551.mcd")) == "ludeum's")

        #expect(try migration.run() == plan)

        #expect(contents(re) == "ludeum's")
        #expect(contents(cards.appending(path: "Resident Evil - Director's Cut (USA)_1 (older).mcd")) == "duckstation's")
        #expect(contents(cards.appending(path: "Ape Escape (USA)_1.mcd")) == "ape")
        #expect(contents(gameSettings.appending(path: "SLUS-00551.ini")) == "[Main]\nRunaheadFrameCount = 1\n\n")
        #expect(contents(gameSettings.appending(path: "SLPS-00001.ini")) == "[GPU]\nResolutionScale = 4\n")
        // Done once, there's nothing left to do.
        #expect(try migration.plan() == [])
    }

    @Test func duckStationsCardKeepsItsNameWhenItsTheNewer() throws {
        let older = Date(timeIntervalSince1970: 1_000_000)
        let newer = Date(timeIntervalSince1970: 2_000_000)
        try write("stale", to: cards.appending(path: "SLUS-00551.mcd"), saved: older)
        try write("current", to: cards.appending(path: "Resident Evil - Director's Cut (USA)_1.mcd"), saved: newer)

        let done = try migration.run()

        #expect(done == [.setAside(cards.appending(path: "SLUS-00551.mcd"), as: cards.appending(path: "SLUS-00551 (older).mcd"))])
        #expect(contents(cards.appending(path: "Resident Evil - Director's Cut (USA)_1.mcd")) == "current")
        #expect(contents(cards.appending(path: "SLUS-00551 (older).mcd")) == "stale")
    }

    @Test func aROMWhoseCardDuckStationWontKeepIsReported() throws {
        try write("ludeum's", to: cards.appending(path: "SLUS-00551.mcd"))
        try write("[MemoryCards]\nCard1Type = None\n", to: gameSettings.appending(path: "SLUS-00551.ini"))

        #expect(try migration.plan() == [.unnamed(serial: "SLUS-00551", rom: "Resident Evil - Director's Cut (USA)")])
        #expect(contents(cards.appending(path: "SLUS-00551.mcd")) == "ludeum's")
    }
}
