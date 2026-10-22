import Foundation
import GRDB

/// The Regions step of every Import, after it commits, and of Add ROM: a ROM whose name had no region tag, so it has no
/// Regions, takes the Regions of the DAT entry its checksum is in Hasheous (`HasheousMatch.regions`). Each ROM is looked
/// up once, whether or not Hasheous knows it. One that has Regions, or no checksum, or whose Copy details I've edited, is
/// never looked up.
struct RegionsImport {
    let journal: LudeumStore
    let hasheous: HasheousClient

    /// Never fails the Import: a ROM whose lookup couldn't run is looked up at the next one. After a few in a row fail,
    /// Hasheous is taken to be unreachable and the rest wait for the next one too. Returns whether any ROM was given
    /// Regions, so its Game's Cover may have changed. Journal edits are allowed while it runs, so a ROM is only given
    /// Regions it still hasn't got. With `only`, just those ROMs are looked up: the one Add ROM has just put in.
    @discardableResult
    func run(only romIds: [Int64]? = nil) async -> Bool {
        guard
            let roms = try? await journal.db.read({ db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, md5, crc FROM rom
                        WHERE regions IS NULL AND NOT regionsLookedUp AND (md5 IS NOT NULL OR crc IS NOT NULL)
                        \(romIds.map { "AND id IN (\(databaseQuestionMarks(count: $0.count)))" } ?? "")
                        ORDER BY id
                        """, arguments: StatementArguments(romIds ?? [])
                ).map { (id: $0["id"] as Int64, md5: $0["md5"] as String?, crc: $0["crc"] as String?) }
            })
        else { return false }
        var changed = false
        var failedInARow = 0
        for rom in roms {
            guard !Task.isCancelled, failedInARow < Self.failuresBeforeGivingUp else { break }
            let found: HasheousResult
            do {
                guard let answer = try await hasheous.lookup(md5: rom.md5, crc: rom.crc) else { continue }
                found = answer
                failedInARow = 0
            } catch {
                failedInARow += 1
                continue
            }
            let regions = Regions.encode(found.match?.regions ?? [])
            let given = try? await journal.db.write { db in
                try db.execute(
                    sql: "UPDATE rom SET regions = ?, regionsLookedUp = 1 WHERE id = ? AND regions IS NULL AND NOT regionsLookedUp",
                    arguments: [regions, rom.id])
                return db.changesCount > 0
            }
            guard let given else { break }
            if given && regions != nil { changed = true }
        }
        return changed
    }

    /// How many lookups in a row can fail before the rest are left for the next Import.
    static let failuresBeforeGivingUp = 3
}
