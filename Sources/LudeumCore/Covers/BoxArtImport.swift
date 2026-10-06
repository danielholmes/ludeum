import Foundation
import GRDB

/// The Box art step of every Import, after it commits: each ROM not yet looked up in libretro-thumbnails
/// looked up. Not backed up: a wiped cache downloads libretro's images again.
struct BoxArtImport {
    let journal: LudeumStore
    let libretro: LibretroThumbnails?

    /// Never fails the Import: a ROM whose lookup couldn't run (libretro or GitHub unreachable) is
    /// looked up at the next one.
    func run() async {
        guard let ids = try? await journal.db.read({ try Int64.fetchAll($0, sql: "SELECT id FROM rom WHERE NOT libretroLookedUp") })
        else { return }
        try? await lookUp(ids)
    }

    /// Looks up each ROM by its file name, then its name, then its Game's IGDB name. Found names replace the
    /// ROM's; a name not found keeps the old one, so a ROM looked up again never loses its Box art to a miss.
    /// A ROM whose lookup fails is left as it was, not looked up, and the rest carry on; once a Platform's lookup
    /// has failed, its other ROMs wait for next time too.
    func lookUp(_ romIds: [Int64]) async throws {
        guard let libretro, !romIds.isEmpty else { return }
        let rows = try journal.db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT rom.id, rom.fileName, rom.name, rom.platformId, game.igdbName FROM rom
                    LEFT JOIN game ON game.id = rom.gameId WHERE rom.id IN (\(databaseQuestionMarks(count: romIds.count)))
                    ORDER BY rom.id
                    """, arguments: StatementArguments(romIds))
        }
        var failedPlatforms: Set<Int64> = []
        for row in rows {
            let id: Int64 = row["id"]
            let platform: Int64 = row["platformId"]
            guard !failedPlatforms.contains(platform) else { continue }
            let titles = [row["name"], row["igdbName"]].compactMap { $0 as String? }
            let names: LibretroNames
            do {
                names = try await libretro.names(platform: platform, fileName: row["fileName"], titles: titles) ?? LibretroNames()
            } catch {
                failedPlatforms.insert(platform)
                continue
            }
            try await journal.db.write { db in
                try db.execute(
                    sql: """
                        UPDATE rom SET libretroLookedUp = 1, libretroBoxart = COALESCE(?, libretroBoxart),
                            libretroSnap = COALESCE(?, libretroSnap), libretroTitle = COALESCE(?, libretroTitle)
                        WHERE id = ?
                        """,
                    arguments: [names.boxart, names.snap, names.title, id])
            }
        }
    }
}
