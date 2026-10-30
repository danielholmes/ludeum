import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// A PlayStation Game's own settings are DuckStation's (ADR 0029): the journal's `v43` drops the CD speedups and clears a
/// PlayStation Game's run-ahead, keeping MesenCE's and ares's.
@Suite struct NoDuckStationSettingsTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "no duckstation settings \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test func aPlayStationGameKeepsNoSettingsOfItsOwnAndOthersKeepTheirs() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = try DatabaseQueue(path: directory.appending(path: "journal.sqlite").path(percentEncoded: false))
        try LudeumSchema.migrator.migrate(db, upTo: "v42 last disc")
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO platform (id, name) VALUES (7, 'PlayStation'), (18, 'NES'), (33, 'Game Boy');
                    INSERT INTO game (id, platformId, name, runAheadFrames, cdReadSpeedup, cdSeekSpeedup)
                    VALUES (1, 7, 'Resident Evil', 6, 0, 0);
                    INSERT INTO game (id, platformId, name, runAheadFrames) VALUES (2, 18, 'Contra', 2);
                    INSERT INTO game (id, platformId, name, gameBoyModel) VALUES (3, 33, 'Survival Kids', 'gameBoyColor');
                    UPDATE game SET updatedAt = '2026-10-01 00:00:00.000';
                    """)
        }
        try db.close()

        let journal = try LudeumStore(directory: directory)

        try journal.db.read { db in
            let columns = try db.columns(in: "game").map(\.name)
            #expect(!columns.contains("cdReadSpeedup"))
            #expect(!columns.contains("cdSeekSpeedup"))
            let updated = try String.fetchAll(db, sql: "SELECT DISTINCT updatedAt FROM game")
            #expect(updated == ["2026-10-01 00:00:00.000"])
        }
        #expect(try journal.emulatorSettings(1) == EmulatorSettings())
        #expect(try journal.emulatorSettings(2) == EmulatorSettings(runAheadFrames: 2))
        #expect(try journal.emulatorSettings(3) == EmulatorSettings(gameBoyModel: .gameBoyColor))

        // The trigger still watches the columns that are left.
        try journal.setEmulatorSettings(2, EmulatorSettings(runAheadFrames: 3))
        let contra = try journal.db.read { db in try String.fetchOne(db, sql: "SELECT updatedAt FROM game WHERE id = 2") }
        #expect(contra != "2026-10-01 00:00:00.000")
    }
}
