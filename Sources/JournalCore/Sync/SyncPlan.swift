import Foundation
import GRDB
import ImageIO

/// Everything one Sync writes, worked out from the journal and a fresh read of OpenEmu.
struct SyncPlan {
    /// Who owns a journal-owned collection.
    enum Owner: Hashable {
        case list(Int64)
        case special(String)
    }

    struct SyncedGame {
        let id: GameID
        let name: String
        let stars: Int
        /// Its ROMs' journal ids and OpenEmu game rows.
        let rows: [(romId: Int64, openEmuGame: Int64)]
    }

    struct PlannedCollection {
        let owner: Owner
        let name: String
        let members: Set<Int64>
        /// The OpenEmu games whose membership the journal decides: those of its Games. Others (ROMs
        /// still in the Review queue, games it doesn't know) keep their memberships.
        let managed: Set<Int64>
        /// Its `Z_PK` when it exists in OpenEmu (journal-owned, or adopted by name); nil to create.
        let existing: OpenEmuStore.Collection?
    }

    struct CoverWrite {
        let gameName: String
        let romId: Int64
        let openEmuGame: Int64
        let key: String
        let jpeg: Data
        let width: Int
        let height: Int
        /// The `ZIMAGE` row Sync wrote before, to update in place.
        let replacing: (pk: Int64, file: String?)?
        /// Filled in while writing.
        var file = ""
        var imagePK: Int64 = 0
    }

    let store: OpenEmuStore
    var games: [SyncedGame] = []
    var notSynced: [Game] = []
    var collections: [PlannedCollection] = []
    /// Collections of deleted Lists: deleted without asking.
    var orphans: [OpenEmuStore.Collection] = []
    var others: [OpenEmuStore.Collection] = []
    var deleting: [OpenEmuStore.Collection] = []
    var coverWrites: [CoverWrite] = []
    var skippedCovers: [SyncPreview.SkippedCover] = []
    /// `syncedCover` rows (by ROM) whose box art I've changed in OpenEmu: forgotten.
    var forgottenCovers: [Int64] = []
    /// Existing `syncedCover` rows by ROM: (`ZIMAGE` pk, cover key).
    var syncedCovers: [Int64: (pk: Int64, key: String)] = [:]
    /// Files of replaced covers, deleted after the commit.
    var replacedFiles: [String] = []
    /// New files whose write was skipped because the box art changed meanwhile, deleted after the commit.
    var unusedFiles: [String] = []

    // MARK: Covers

    mutating func planCovers(for game: SyncedGame, source: CoverSource, downloadFailed: Bool) {
        // OpenEmu takes JPEG: IGDB's and OpenEmu's bytes as they are, libretro's PNG re-encoded.
        let jpeg: Data? =
            switch source {
            case .upload(let cover): cover.jpeg
            case .libretro(let file, _): (try? Data(contentsOf: file)).flatMap { try? CoverImage.normalise($0).jpeg }
            case .openEmu(let file, _), .igdb(let file, _): try? Data(contentsOf: file)
            case .placeholder: nil
            }
        let image = source.key.flatMap { key in jpeg.map { (key: key, jpeg: $0) } }
        for row in game.rows {
            guard let oe = store.games[row.openEmuGame] else { continue }
            if let synced = syncedCovers[row.romId] {
                guard oe.boxImage == synced.pk else {
                    // I changed the box art in OpenEmu: leave it, and forget Sync's record.
                    forgottenCovers.append(row.romId)
                    continue
                }
                if let image, image.key != synced.key { add(write(game, row, image, replacing: synced.pk)) }
                continue
            }
            guard image != nil || downloadFailed else { continue }
            if oe.boxImage != nil {
                skippedCovers.append(.init(gameName: game.name, reason: .hasBoxArt))
            } else if oe.status != 0 {
                skippedCovers.append(.init(gameName: game.name, reason: .awaitingOpenVGDB))
            } else if let image {
                add(write(game, row, image, replacing: nil))
            } else {
                skippedCovers.append(.init(gameName: game.name, reason: .downloadFailed))
            }
        }
    }

    /// A Cover whose size can't be read isn't written: OpenEmu needs its pixel width and height.
    private mutating func add(_ write: CoverWrite) {
        if write.width > 0, write.height > 0 {
            coverWrites.append(write)
        } else {
            skippedCovers.append(.init(gameName: write.gameName, reason: .unreadable))
        }
    }

    private func write(_ game: SyncedGame, _ row: (romId: Int64, openEmuGame: Int64), _ image: (key: String, jpeg: Data), replacing: Int64?)
        -> CoverWrite
    {
        let source = CGImageSourceCreateWithData(image.jpeg as CFData, nil)
        let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        return CoverWrite(
            gameName: game.name, romId: row.romId, openEmuGame: row.openEmuGame, key: image.key, jpeg: image.jpeg,
            width: properties?[kCGImagePropertyPixelWidth] as? Int ?? 0, height: properties?[kCGImagePropertyPixelHeight] as? Int ?? 0,
            replacing: replacing.map { ($0, nil) })
    }

    // MARK: Preview

    func preview(failedGuards: [SyncGuard]) -> SyncPreview {
        let stars = games.compactMap { game -> SyncPreview.StarChange? in
            let current = game.rows.compactMap { store.games[$0.openEmuGame] }.filter { $0.stars != game.stars }.map(\.stars)
            return current.isEmpty ? nil : .init(gameName: game.name, stars: game.stars, current: current)
        }
        let changes = collections.compactMap { c -> SyncPreview.CollectionChange? in
            let before = c.existing?.members ?? []
            let renamed = c.existing.map(\.name).flatMap { $0 == c.name ? nil : $0 }
            let change = SyncPreview.CollectionChange(
                name: c.name, renamedFrom: renamed, isNew: c.existing == nil, added: c.members.subtracting(before).count,
                removed: before.intersection(c.managed).subtracting(c.members).count)
            return change.isNew || change.renamedFrom != nil || change.added > 0 || change.removed > 0 ? change : nil
        }
        return SyncPreview(
            failedGuards: failedGuards, starChanges: stars, collectionChanges: changes, deletedListCollections: orphans.map(\.name),
            otherCollections: others.map { .init(pk: $0.pk, name: $0.name, gameCount: $0.members.count) }.sorted { $0.name < $1.name },
            coversAdded: coverWrites.filter { $0.replacing == nil }.map { .init(gameName: $0.gameName) },
            coversReplaced: coverWrites.filter { $0.replacing != nil }.map { .init(gameName: $0.gameName) },
            coversSkipped: skippedCovers, notSynced: notSynced)
    }

    // MARK: Writing

    /// Writes into OpenEmu's store in one transaction, then checkpoints the WAL so Dropbox sees a
    /// complete main file. Cover files are written first and removed again if the transaction fails.
    mutating func write(library: URL) throws {
        let artwork = library.appending(path: "Artwork", directoryHint: .isDirectory)
        let db = try DatabaseQueue(path: OpenEmuLibrary.databaseFile(in: library).path(percentEncoded: false))
        defer { try? db.close() }
        do {
            for i in coverWrites.indices {
                let name = UUID().uuidString
                try coverWrites[i].jpeg.write(to: artwork.appending(path: name))
                coverWrites[i].file = name
            }
            try db.write { db in try writeTransaction(db) }
        } catch {
            for write in coverWrites where !write.file.isEmpty {
                try? FileManager.default.removeItem(at: artwork.appending(path: write.file))
            }
            throw error
        }
        try db.writeWithoutTransaction { try $0.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)") }
    }

    private mutating func writeTransaction(_ db: Database) throws {
        let s = store
        func nextKey(_ root: Int) throws -> Int64 {
            try db.execute(sql: "UPDATE Z_PRIMARYKEY SET Z_MAX = Z_MAX + 1 WHERE Z_ENT = ?", arguments: [root])
            return try Int64.fetchOne(db, sql: "SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_ENT = ?", arguments: [root])!
        }
        func touch(games: Set<Int64>) throws {
            for game in games { try db.execute(sql: "UPDATE ZGAME SET Z_OPT = Z_OPT + 1 WHERE Z_PK = ?", arguments: [game]) }
        }

        // Stars, on every OpenEmu game row of each Game.
        for game in games {
            for row in game.rows where (s.games[row.openEmuGame]?.stars ?? game.stars) != game.stars {
                try db.execute(
                    sql: "UPDATE ZGAME SET ZRATING = ?, Z_OPT = Z_OPT + 1 WHERE Z_PK = ?", arguments: [game.stars, row.openEmuGame])
            }
        }

        // Journal-owned collections: in place (name and membership), or created.
        for (i, c) in collections.enumerated() {
            let pk: Int64
            let before: Set<Int64>
            if let existing = c.existing {
                pk = existing.pk
                before = existing.members
            } else {
                pk = try nextKey(s.collectionRoot)
                before = []
                try db.execute(
                    sql: "INSERT INTO ZABSTRACTCOLLECTION (Z_PK, Z_ENT, Z_OPT, ZFOLDER, ZNAME) VALUES (?, ?, 1, NULL, ?)",
                    arguments: [pk, s.collectionEntity, c.name])
                collections[i] = PlannedCollection(
                    owner: c.owner, name: c.name, members: c.members, managed: c.managed, existing: .init(pk: pk, name: c.name, members: [])
                )
            }
            let added = c.members.subtracting(before)
            let removed = before.intersection(c.managed).subtracting(c.members)
            for game in added {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO \(s.joinTable) (\(s.joinCollection), \(s.joinGame)) VALUES (?, ?)", arguments: [pk, game])
            }
            for game in removed {
                try db.execute(
                    sql: "DELETE FROM \(s.joinTable) WHERE \(s.joinCollection) = ? AND \(s.joinGame) = ?", arguments: [pk, game])
            }
            try touch(games: added.union(removed))
            let renamed = c.existing.map { $0.name != c.name } ?? false
            if c.existing != nil, renamed || !added.isEmpty || !removed.isEmpty {
                try db.execute(sql: "UPDATE ZABSTRACTCOLLECTION SET ZNAME = ?, Z_OPT = Z_OPT + 1 WHERE Z_PK = ?", arguments: [c.name, pk])
            }
        }

        // Deleted Lists' collections, and the other collections I ticked: only regular Collection rows.
        for c in orphans + deleting {
            try touch(games: c.members)
            try db.execute(sql: "DELETE FROM \(s.joinTable) WHERE \(s.joinCollection) = ?", arguments: [c.pk])
            try db.execute(sql: "DELETE FROM ZABSTRACTCOLLECTION WHERE Z_PK = ? AND Z_ENT = ?", arguments: [c.pk, s.collectionEntity])
        }

        // Covers: a new ZIMAGE row linked both ways, or Sync's own row updated in place.
        for i in coverWrites.indices {
            let w = coverWrites[i]
            // Only while the game's box art is still Sync's row (to replace) or there is none (to add).
            let current = try Int64?.fetchOne(db, sql: "SELECT ZBOXIMAGE FROM ZGAME WHERE Z_PK = ?", arguments: [w.openEmuGame]) ?? nil
            if let replacing = w.replacing {
                guard current == replacing.pk else {
                    unusedFiles.append(w.file)
                    continue
                }
                let old = try String.fetchOne(db, sql: "SELECT ZRELATIVEPATH FROM ZIMAGE WHERE Z_PK = ?", arguments: [replacing.pk])
                try db.execute(
                    sql: "UPDATE ZIMAGE SET ZRELATIVEPATH = ?, ZWIDTH = ?, ZHEIGHT = ?, Z_OPT = Z_OPT + 1 WHERE Z_PK = ?",
                    arguments: [w.file, w.width, w.height, replacing.pk])
                coverWrites[i].imagePK = replacing.pk
                if let old { replacedFiles.append(old) }
            } else {
                guard current == nil else {
                    unusedFiles.append(w.file)
                    continue
                }
                let pk = try nextKey(s.imageRoot)
                try db.execute(
                    sql: """
                        INSERT INTO ZIMAGE (Z_PK, Z_ENT, Z_OPT, ZFORMAT, ZBOX, ZHEIGHT, ZWIDTH, ZRELATIVEPATH, ZSOURCE)
                        VALUES (?, ?, 1, 3, ?, ?, ?, ?, NULL)
                        """, arguments: [pk, s.imageEntity, w.openEmuGame, w.height, w.width, w.file])
                try db.execute(
                    sql: "UPDATE ZGAME SET ZBOXIMAGE = ?, Z_OPT = Z_OPT + 1 WHERE Z_PK = ? AND ZBOXIMAGE IS NULL",
                    arguments: [pk, w.openEmuGame])
                coverWrites[i].imagePK = pk
            }
        }
    }

    /// The journal's Sync bookkeeping: which collections and covers it owns in OpenEmu.
    func recordInJournal(_ journal: JournalStore) throws {
        try journal.db.write { db in
            for c in orphans { try db.execute(sql: "DELETE FROM syncedCollection WHERE openEmuPk = ?", arguments: [c.pk]) }
            for c in collections {
                guard let pk = c.existing?.pk else { continue }
                switch c.owner {
                case .list(let id):
                    try db.execute(sql: "DELETE FROM syncedCollection WHERE listId = ? OR openEmuPk = ?", arguments: [id, pk])
                    try db.execute(sql: "INSERT INTO syncedCollection (openEmuPk, listId) VALUES (?, ?)", arguments: [pk, id])
                case .special(let name):
                    try db.execute(sql: "DELETE FROM syncedCollection WHERE special = ? OR openEmuPk = ?", arguments: [name, pk])
                    try db.execute(sql: "INSERT INTO syncedCollection (openEmuPk, special) VALUES (?, ?)", arguments: [pk, name])
                }
            }
            for rom in forgottenCovers { try db.execute(sql: "DELETE FROM syncedCover WHERE romId = ?", arguments: [rom]) }
            for w in coverWrites where w.imagePK != 0 {
                try db.execute(sql: "DELETE FROM syncedCover WHERE openEmuImagePk = ? OR romId = ?", arguments: [w.imagePK, w.romId])
                try db.execute(
                    sql: "INSERT INTO syncedCover (openEmuImagePk, romId, coverKey) VALUES (?, ?, ?)",
                    arguments: [w.imagePK, w.romId, w.key])
            }
        }
    }

    func deleteReplacedFiles(library: URL) {
        let artwork = library.appending(path: "Artwork", directoryHint: .isDirectory)
        for file in replacedFiles + unusedFiles { try? FileManager.default.removeItem(at: artwork.appending(path: file)) }
    }
}

extension JournalStore {
    /// Works out the Sync from the journal: stars per Game, the journal-owned collections and which
    /// OpenEmu collections they are, and the Games left out for Duplicate Versions.
    func syncPlan(store: OpenEmuStore) throws -> SyncPlan {
        var plan = SyncPlan(store: store)
        let duplicates = Set(try reviewQueue().duplicateVersions.map(\.id))
        let rows = try db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT g.id, COALESCE(g.nameOverride, g.igdbName, g.name) AS name, g.intent,
                        (SELECT rating FROM ratingEntry WHERE gameId = g.id \(Self.ratingOrder) LIMIT 1) AS rating,
                        EXISTS (SELECT 1 FROM playthrough WHERE gameId = g.id AND outcome IS NULL) AS playing,
                        EXISTS (SELECT 1 FROM playthrough WHERE gameId = g.id AND outcome = 'finished') AS finished
                    FROM game g ORDER BY g.id
                    """)
        }
        let roms = try db.read { db in try Row.fetchAll(db, sql: "SELECT id, gameId, openEmuPk FROM rom WHERE gameId IS NOT NULL") }
        let romsByGame = Dictionary(grouping: roms, by: { $0["gameId"] as GameID })
        var special: [String: Set<Int64>] = ["_TODO": [], "_TODO Next": [], "_Current": [], "_Completed": []]
        var openEmuGames: [GameID: Set<Int64>] = [:]
        for row in rows {
            let id: GameID = row["id"]
            if duplicates.contains(id) {
                plan.notSynced.append(try game(id))
                continue
            }
            let mapped = (romsByGame[id] ?? []).compactMap { r -> (romId: Int64, openEmuGame: Int64)? in
                store.gameOfROM[r["openEmuPk"]].map { (r["id"], $0) }
            }
            guard !mapped.isEmpty else { continue }
            let stars = OpenEmuSync.stars(for: (row["rating"] as Int?).flatMap { Rating(tenths: $0) })
            plan.games.append(.init(id: id, name: row["name"], stars: stars, rows: mapped))
            let pks = Set(mapped.map(\.openEmuGame))
            openEmuGames[id] = pks
            switch row["intent"] as String? {
            case "backlog": special["_TODO"]!.formUnion(pks)
            case "upNext": special["_TODO Next"]!.formUnion(pks)
            default: break
            }
            if row["playing"] as Bool { special["_Current"]!.formUnion(pks) }
            if row["finished"] as Bool { special["_Completed"]!.formUnion(pks) }
        }

        // Games with Duplicate Versions keep their memberships too, as they aren't synced.
        let managed = Set(openEmuGames.values.joined())
        let synced = try db.read { db in try Row.fetchAll(db, sql: "SELECT openEmuPk, listId, special FROM syncedCollection") }
        var owned: [SyncPlan.Owner: Int64] = [:]
        for row in synced {
            if let list = row["listId"] as Int64? {
                owned[.list(list)] = row["openEmuPk"]
            } else if let name = row["special"] as String? {
                owned[.special(name)] = row["openEmuPk"]
            } else if let c = store.collections[row["openEmuPk"]] {
                plan.orphans.append(c)  // a deleted List's collection
            }
        }
        var claimed = Set(plan.orphans.map(\.pk))
        func existing(_ owner: SyncPlan.Owner, name: String) -> OpenEmuStore.Collection? {
            if let pk = owned[owner], let c = store.collections[pk] { return c }
            // Adopt OpenEmu's own collection of that name (the first Sync), else it's created.
            return store.collections.values.filter { $0.name == name && !claimed.contains($0.pk) && !owned.values.contains($0.pk) }
                .min { $0.pk < $1.pk }
        }
        for name in ["_TODO", "_TODO Next", "_Current", "_Completed"] {
            let c = existing(.special(name), name: name)
            if let c { claimed.insert(c.pk) }
            plan.collections.append(.init(owner: .special(name), name: name, members: special[name]!, managed: managed, existing: c))
        }
        for list in try lists() {
            let members = Set(try games(in: list.id).flatMap { openEmuGames[$0] ?? [] })
            let c = existing(.list(list.id), name: list.name)
            if let c { claimed.insert(c.pk) }
            plan.collections.append(.init(owner: .list(list.id), name: list.name, members: members, managed: managed, existing: c))
        }
        plan.others = store.collections.values.filter { !claimed.contains($0.pk) }.sorted { $0.pk < $1.pk }

        let covers = try db.read { db in try Row.fetchAll(db, sql: "SELECT openEmuImagePk, romId, coverKey FROM syncedCover") }
        for row in covers { plan.syncedCovers[row["romId"]] = (row["openEmuImagePk"], row["coverKey"]) }
        return plan
    }
}
