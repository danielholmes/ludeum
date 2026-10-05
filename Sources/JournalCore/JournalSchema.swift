import GRDB

/// The journal's migrations. Append-only since the first real Import into the production database.
enum JournalSchema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            /// A Partial date column holds `YYYY`, `YYYY-MM` or `YYYY-MM-DD`, or nothing.
            func partialDateCheck(_ column: String) -> String {
                let year = "[0-9][0-9][0-9][0-9]"
                let pair = "-[0-9][0-9]"
                return "\(column) IS NULL OR "
                    + ["\(year)", "\(year)\(pair)", "\(year)\(pair)\(pair)"].map { "\(column) GLOB '\($0)'" }
                    .joined(separator: " OR ")
            }

            try db.create(table: "platform") { t in
                t.primaryKey("id", .integer)  // IGDB platform id
                t.column("name", .text).notNull()
            }
            try db.create(table: "game") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("platformId", .integer).notNull().references("platform")
                t.column("igdbGameId", .integer)
                t.column("igdbName", .text)
                t.column("name", .text)
                t.column("nameOverride", .text)
                t.column("childhood", .boolean).notNull().defaults(to: false)
                t.column("intent", .text).check { ["backlog", "upNext"].contains($0) }
                t.column("intentSetAt", .datetime)
                t.uniqueKey(["igdbGameId", "platformId"])
                t.check(sql: "COALESCE(nameOverride, igdbName, name) IS NOT NULL")
                t.check(sql: "intent IS NOT NULL OR intentSetAt IS NULL")
            }
            try db.create(table: "ratingEntry") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("gameId", .integer).notNull().indexed().references("game", onDelete: .cascade)
                t.column("day", .text).notNull()
                t.column("rating", .integer).check { $0 >= 0 && $0 <= 100 }  // tenths; NULL = cleared
                t.column("imported", .boolean).notNull().defaults(to: false)
                t.uniqueKey(["gameId", "day", "imported"])
            }
            try db.create(table: "playthrough") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("gameId", .integer).notNull().indexed().references("game", onDelete: .cascade)
                t.column("start", .text).check(sql: partialDateCheck("start"))
                t.column("end", .text).check(sql: partialDateCheck("end"))
                t.column("outcome", .text).check { ["finished", "dropped"].contains($0) }
                t.column("notes", .text)
                t.column("version", .text)
                t.column("playedVia", .text)
                t.check(sql: "outcome IS NOT NULL OR start IS NOT NULL")
            }
            try db.create(table: "list") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
            }
            try db.create(table: "listGame") { t in
                t.column("listId", .integer).notNull().references("list", onDelete: .cascade)
                t.column("gameId", .integer).notNull().indexed().references("game", onDelete: .cascade)
                t.primaryKey(["listId", "gameId"])
            }
            try db.create(table: "cover") { t in
                t.primaryKey("gameId", .integer).references("game", onDelete: .cascade)
                t.column("jpeg", .blob).notNull()
                t.column("width", .integer).notNull()
                t.column("height", .integer).notNull()
                t.column("origin", .text).notNull().check { ["carried", "uploaded"].contains($0) }
                t.column("sha256", .text).notNull()
            }
            try db.create(table: "rom") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("openEmuPk", .integer).notNull().unique()
                t.column("md5", .text).notNull()
                t.column("fileName", .text).notNull()
                t.column("name", .text)  // OpenEmu's name for it (ZGAME.ZNAME); the file name when unknown
                t.column("systemId", .text).notNull()
                t.column("missing", .boolean).notNull().defaults(to: false)
                t.column("version", .text)
                t.column("discNumber", .integer)
                t.column("discLabel", .text)
                t.column("gameId", .integer).indexed().references("game", onDelete: .cascade)
                t.column("matchKind", .text).check { ["automatic", "confirmed", "manual"].contains($0) }
                t.column("matchedAt", .datetime)
                t.column("suggestedIgdbGameId", .integer)
                t.column("suggestionKind", .text).check { ["checksum", "name"].contains($0) }
                t.column("checksumIgdbGameId", .integer)
                t.column("namesAgree", .boolean)
                t.check(sql: "(gameId IS NULL) = (matchKind IS NULL) AND (gameId IS NULL) = (matchedAt IS NULL)")
            }
            try db.create(table: "import") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("startedAt", .datetime).notNull()
                t.column("isFirst", .boolean).notNull()
            }
            try db.create(table: "activitySnapshot") { t in
                t.column("importId", .integer).notNull().references("import", onDelete: .cascade)
                t.column("romId", .integer).notNull().indexed().references("rom", onDelete: .cascade)
                t.column("playCount", .integer).notNull()
                t.column("lastPlayedAt", .datetime)
                t.column("playTimeSeconds", .double).notNull()
                t.primaryKey(["importId", "romId"])
            }
            try db.create(table: "syncedCollection") { t in
                t.primaryKey("openEmuPk", .integer)
                t.column("listId", .integer).unique().references("list", onDelete: .setNull)
                t.column("special", .text).unique().check { ["_TODO", "_TODO Next", "_Current", "_Completed"].contains($0) }
                t.check(sql: "listId IS NULL OR special IS NULL")
            }
            try db.create(table: "syncedCover") { t in
                t.primaryKey("openEmuImagePk", .integer)
                t.column("romId", .integer).notNull().indexed().references("rom", onDelete: .cascade)
                t.column("coverKey", .text).notNull()
            }
            try db.create(table: "openEmuLibrary") { t in
                t.primaryKey("id", .integer).check { $0 == 1 }
                t.column("storeUUID", .text).notNull()
            }
            // An unmatched ROM's OpenEmu data from the first Import, applied when the Review queue
            // resolves it: stars (0–5), collection names (JSON array) and a `_Current` start date
            // answer (a Partial date, or 'notPlaying').
            try db.create(table: "heldOpenEmuData") { t in
                t.primaryKey("romId", .integer).references("rom", onDelete: .cascade)
                t.column("stars", .integer).notNull()
                t.column("collections", .text).notNull()
                t.column("currentStart", .text)
            }
        }
        // Box-art Covers: libretro-thumbnails names and the cached OpenEmu Box art on each ROM;
        // the `cover` table holds uploads only, so carried-over Covers go (the cache copy replaces them).
        migrator.registerMigration("v2 box art") { db in
            try db.alter(table: "rom") { t in
                t.add(column: "libretroLookedUp", .boolean).notNull().defaults(to: false)
                t.add(column: "libretroBoxart", .text)
                t.add(column: "libretroSnap", .text)
                t.add(column: "libretroTitle", .text)
                t.add(column: "openEmuBoxArt", .text)  // ZIMAGE.ZRELATIVEPATH, copied into the cache
            }
            try db.create(table: "newCover") { t in
                t.primaryKey("gameId", .integer).references("game", onDelete: .cascade)
                t.column("jpeg", .blob).notNull()
                t.column("width", .integer).notNull()
                t.column("height", .integer).notNull()
                t.column("sha256", .text).notNull()
            }
            try db.execute(
                sql: """
                    INSERT INTO newCover SELECT gameId, jpeg, width, height, sha256 FROM cover WHERE origin = 'uploaded';
                    DROP TABLE cover;
                    ALTER TABLE newCover RENAME TO cover;
                    """)
        }
        return migrator
    }
}
