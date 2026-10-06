import Foundation
import GRDB

/// The Box art step of every Import, after it commits: each ROM not yet looked up in libretro-thumbnails
/// looked up. Not backed up: a wiped cache downloads libretro's images again.
struct BoxArtImport {
    let journal: LudeumStore
    let libretro: LibretroThumbnails?

    /// Never fails the Import: a ROM whose lookup couldn't run (libretro or GitHub unreachable) is
    /// looked up at the next one. Returns whether any ROM's Box art changed, so its Game's Cover may have.
    @discardableResult
    func run() async -> Bool {
        guard let ids = try? await journal.db.read({ try Int64.fetchAll($0, sql: "SELECT id FROM rom WHERE NOT libretroLookedUp") })
        else { return false }
        return (try? await boxArtChanges(lookingUp: ids)) ?? false
    }

    /// Looks up each ROM by its file name, then its name, then its Game's IGDB name. Found names replace the
    /// ROM's; a name not found keeps the old one, so a ROM looked up again never loses its Box art to a miss.
    /// A Platform's listing is read once for all its ROMs; when it can't be, they're left as they were, not looked up,
    /// and the other Platforms' carry on.
    func lookUp(_ romIds: [Int64]) async throws { _ = try await boxArtChanges(lookingUp: romIds) }

    /// `lookUp`, returning whether any ROM's Box art changed.
    func boxArtChanges(lookingUp romIds: [Int64]) async throws -> Bool {
        guard let libretro, !romIds.isEmpty else { return false }
        let rows = try journal.db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT rom.id, rom.fileName, rom.name, rom.platformId, rom.libretroBoxart, game.igdbName FROM rom
                    LEFT JOIN game ON game.id = rom.gameId WHERE rom.id IN (\(databaseQuestionMarks(count: romIds.count)))
                    ORDER BY rom.id
                    """, arguments: StatementArguments(romIds))
        }
        var changed = false
        for (platform, rows) in Dictionary(grouping: rows, by: { $0["platformId"] as Int64 }).sorted(by: { $0.key < $1.key }) {
            guard var listing = try? await libretro.listing(platform: platform) else { continue }
            let found = rows.map { row in
                (
                    id: row["id"] as Int64, boxArtBefore: row["libretroBoxart"] as String?,
                    names: listing.names(fileName: row["fileName"], titles: [row["name"], row["igdbName"]].compactMap { $0 as String? })
                )
            }
            try await journal.db.write { db in
                for rom in found {
                    try db.execute(
                        sql: """
                            UPDATE rom SET libretroLookedUp = 1, libretroBoxart = COALESCE(?, libretroBoxart),
                                libretroSnap = COALESCE(?, libretroSnap), libretroTitle = COALESCE(?, libretroTitle)
                            WHERE id = ?
                            """,
                        arguments: [rom.names.boxart, rom.names.snap, rom.names.title, rom.id])
                }
            }
            if found.contains(where: { $0.names.boxart != nil && $0.names.boxart != $0.boxArtBefore }) { changed = true }
        }
        return changed
    }
}
