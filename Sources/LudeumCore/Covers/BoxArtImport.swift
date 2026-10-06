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
        try? await lookUp(romsWhere: "NOT rom.libretroLookedUp")
    }

    /// Looks up each ROM matching `condition` (SQL over `rom`) by its file name, then its name, then its
    /// Game's IGDB name. Found names replace the ROM's; with `keepingOnMiss`, a name not found keeps the old one.
    func lookUp(romsWhere condition: String, keepingOnMiss: Bool = false) async throws {
        guard let libretro else { return }
        let rows = try journal.db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT rom.id, rom.fileName, rom.name, rom.platformId, game.igdbName FROM rom
                    LEFT JOIN game ON game.id = rom.gameId WHERE \(condition) ORDER BY rom.id
                    """)
        }
        let set = ["libretroBoxart", "libretroSnap", "libretroTitle"].map { keepingOnMiss ? "\($0) = COALESCE(?, \($0))" : "\($0) = ?" }
        for row in rows {
            let id: Int64 = row["id"]
            let titles = [row["name"], row["igdbName"]].compactMap { $0 as String? }
            let names = try await libretro.names(platform: row["platformId"], fileName: row["fileName"], titles: titles) ?? LibretroNames()
            try await journal.db.write { db in
                try db.execute(
                    sql: "UPDATE rom SET libretroLookedUp = 1, \(set.joined(separator: ", ")) WHERE id = ?",
                    arguments: [names.boxart, names.snap, names.title, id])
            }
        }
    }
}
