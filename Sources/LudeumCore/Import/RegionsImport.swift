import Foundation
import GRDB

/// The Regions step of every Import, after it commits and reads Serials, and of Add ROM: a ROM whose name had no region
/// tag, so it has no Regions, takes the Regions its Discs' Serials say (`Serials.regions`), else those of the DAT entry
/// its checksum is in Hasheous (`HasheousMatch.regions`). One on a Platform whose Serials are read waits for them, so
/// one they give Regions is never asked about by Hasheous. Each ROM is given Regions once, whether or not either knows
/// them. One that has Regions, or no Serials to give them and no checksum, or whose Copy details I've edited, never is.
struct RegionsImport {
    let journal: LudeumStore
    /// Without it, only Serials give Regions; the rest are looked up at the next Import.
    let hasheous: HasheousClient?

    /// Never fails the Import: a ROM whose lookup couldn't run is looked up at the next one. After a few in a row fail,
    /// Hasheous is taken to be unreachable and the rest wait for the next one too. Returns whether any ROM was given
    /// Regions, so its Game's Cover may have changed. Journal edits are allowed while it runs, so a ROM is only given
    /// Regions it still hasn't got. With `only`, just those ROMs are given them: the one Add ROM has just put in.
    @discardableResult
    func run(only romIds: [Int64]? = nil) async -> Bool {
        guard
            let roms = try? await journal.db.read({ db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, platformId, md5, crc, serials, serialsLookedUp FROM rom
                        WHERE regions IS NULL AND NOT regionsLookedUp
                        \(romIds.map { "AND id IN (\(databaseQuestionMarks(count: $0.count)))" } ?? "")
                        ORDER BY id
                        """, arguments: StatementArguments(romIds ?? [])
                ).map { row in
                    (
                        id: row["id"] as Int64, md5: row["md5"] as String?, crc: row["crc"] as String?,
                        serials: Serials.platforms.contains(row["platformId"]) ? Serials(row) : nil
                    )
                }
            })
        else { return false }
        var changed = false
        var failedInARow = 0
        for rom in roms {
            guard !Task.isCancelled else { break }
            // Its Serials say its Regions for certain, once they've been read.
            if rom.serials == .notRead { continue }
            var regions = rom.serials?.regions ?? []
            if regions.isEmpty {
                guard let hasheous, failedInARow < Self.failuresBeforeGivingUp else { continue }
                do {
                    guard let answer = try await hasheous.lookup(md5: rom.md5, crc: rom.crc) else { continue }
                    regions = answer.match?.regions ?? []
                    failedInARow = 0
                } catch {
                    failedInARow += 1
                    continue
                }
            }
            let encoded = Regions.encode(regions)
            let given = try? await journal.db.write { db in
                try db.execute(
                    sql: "UPDATE rom SET regions = ?, regionsLookedUp = 1 WHERE id = ? AND regions IS NULL AND NOT regionsLookedUp",
                    arguments: [encoded, rom.id])
                return db.changesCount > 0
            }
            guard let given else { break }
            if given && encoded != nil { changed = true }
        }
        return changed
    }

    /// How many lookups in a row can fail before the rest are left for the next Import.
    static let failuresBeforeGivingUp = 3
}
