import Foundation
import GRDB

/// The Box art step of every Import, after it commits: OpenEmu's Box art copied into the cache, and
/// each ROM not yet looked up in libretro-thumbnails looked up. Neither is backed up: a wiped cache
/// gets the OpenEmu copies back at the next Import and downloads libretro's again.
struct BoxArtImport {
    let journal: JournalStore
    let cache: CacheStore
    let libretro: LibretroThumbnails?

    static func openEmuPath(_ relativePath: String) -> String { "openemu/\(relativePath)" }

    /// Never fails the Import: a ROM whose lookup couldn't run (libretro or GitHub unreachable) is
    /// looked up at the next one.
    func run(_ snapshot: OpenEmuLibrarySnapshot) async {
        try? copyOpenEmuBoxArt(snapshot)
        try? await lookUp(titles: Dictionary(snapshot.roms.map { ($0.pk, $0.openVGDBTitle) }, uniquingKeysWith: { a, _ in a }))
    }

    /// Every ROM's OpenEmu Box art, except box art Sync wrote there (that's a Cover, not OpenEmu's own).
    private func copyOpenEmuBoxArt(_ snapshot: OpenEmuLibrarySnapshot) throws {
        let syncWrote = try journal.db.read { db in Set(try Int64.fetchAll(db, sql: "SELECT openEmuImagePk FROM syncedCover")) }
        var paths: [Int64: String?] = [:]
        for rom in snapshot.roms {
            guard let art = rom.boxArt, !syncWrote.contains(rom.boxArtImagePk ?? -1) else {
                paths[rom.pk] = .some(nil)
                continue
            }
            let path = art.lastPathComponent
            if cache.cachedImage(at: Self.openEmuPath(path)) == nil {
                guard let data = try? Data(contentsOf: art) else {
                    paths[rom.pk] = .some(nil)
                    continue
                }
                try cache.store(image: data, at: Self.openEmuPath(path))
            }
            paths[rom.pk] = path
        }
        try journal.db.write { db in
            for (pk, path) in paths {
                try db.execute(sql: "UPDATE rom SET openEmuBoxArt = ? WHERE openEmuPk = ?", arguments: [path, pk])
            }
        }
    }

    private func lookUp(titles openVGDBTitles: [Int64: String?]) async throws {
        guard let libretro else { return }
        let rows = try journal.db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT rom.id, rom.openEmuPk, rom.fileName, rom.name, rom.systemId, game.igdbName FROM rom
                    LEFT JOIN game ON game.id = rom.gameId WHERE NOT rom.libretroLookedUp ORDER BY rom.id
                    """)
        }
        for row in rows {
            let id: Int64 = row["id"]
            let titles = [row["name"], openVGDBTitles[row["openEmuPk"]] ?? nil, row["igdbName"]].compactMap { $0 as String? }
            let names = try await libretro.names(system: row["systemId"], fileName: row["fileName"], titles: titles) ?? LibretroNames()
            try await journal.db.write { db in
                try db.execute(
                    sql: "UPDATE rom SET libretroLookedUp = 1, libretroBoxart = ?, libretroSnap = ?, libretroTitle = ? WHERE id = ?",
                    arguments: [names.boxart, names.snap, names.title, id])
            }
        }
    }
}
