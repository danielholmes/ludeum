import GRDB

/// The journal's migrations. Append-only since the first real Import into the production database.
enum LudeumSchema {
    /// The last migration a journal with OpenEmu ROMs can take. `LudeumStore` goes no further until
    /// `migrate-openemu` has moved them into ROM folders.
    static let lastWithOpenEmu = "v15 no openemu box art"
    /// The migration that drops OpenEmu, which waits for `migrate-openemu`.
    static let withoutOpenEmu = "v16 no openemu"

    /// A migration that drops OpenEmu was asked to run while ROMs are still OpenEmu's.
    struct OpenEmuROMsRemain: Error {}

    /// ROMs keyed by Platform: an unmatched ROM's OpenEmu system has no Platform this build knows, so nothing was changed.
    public struct UnknownOpenEmuSystems: Error, Equatable, CustomStringConvertible {
        public let systems: [String]
        public var description: String {
            "Unmatched ROMs of OpenEmu systems Ludeum has no Platform for: \(systems.joined(separator: ", ")). Match them first."
        }
    }

    /// A Partial date column holds `YYYY`, `YYYY-MM` or `YYYY-MM-DD`, or nothing.
    private static func partialDateCheck(_ column: String) -> String {
        let year = "[0-9][0-9][0-9][0-9]"
        let pair = "-[0-9][0-9]"
        return "\(column) IS NULL OR "
            + ["\(year)", "\(year)\(pair)", "\(year)\(pair)\(pair)"].map { "\(column) GLOB '\($0)'" }
            .joined(separator: " OR ")
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
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
        // Franchises and series pinned to the sidebar, by IGDB name.
        migrator.registerMigration("v3 pins") { db in
            try db.create(table: "pin") { t in
                t.column("kind", .text).notNull().check { ["franchise", "series"].contains($0) }
                t.column("name", .text).notNull()
                t.primaryKey(["kind", "name"])
            }
        }
        // Themes can be pinned too: the kind's CHECK widened, which SQLite does by rebuilding the table.
        migrator.registerMigration("v4 theme pins") { db in
            try db.create(table: "newPin") { t in
                t.column("kind", .text).notNull().check { ["franchise", "series", "theme"].contains($0) }
                t.column("name", .text).notNull()
                t.primaryKey(["kind", "name"])
            }
            try db.execute(sql: "INSERT INTO newPin SELECT kind, name FROM pin; DROP TABLE pin; ALTER TABLE newPin RENAME TO pin")
        }
        // Companies can be pinned too.
        migrator.registerMigration("v5 company pins") { db in
            try db.create(table: "newPin") { t in
                t.column("kind", .text).notNull().check { ["franchise", "series", "theme", "company"].contains($0) }
                t.column("name", .text).notNull()
                t.primaryKey(["kind", "name"])
            }
            try db.execute(sql: "INSERT INTO newPin SELECT kind, name FROM pin; DROP TABLE pin; ALTER TABLE newPin RENAME TO pin")
        }
        // Game Boy Color ROMs filed under Game Boy were looked up in Game Boy first, and some took a
        // Game Boy game's box: look them up again at the next Import.
        migrator.registerMigration("v6 relook up colour ROMs") { db in
            try db.execute(
                sql: """
                    UPDATE rom SET libretroLookedUp = 0
                    WHERE systemId = 'openemu.system.gb' AND (fileName LIKE '%.gbc' OR fileName LIKE '%[C]%')
                    """)
        }
        // Activity is gone (ADR 0007).
        migrator.registerMigration("v7 no activity") { db in
            try db.drop(table: "activitySnapshot")
        }
        migrator.registerMigration("v8 emulator settings") { db in
            try db.alter(table: "game") { t in t.add(column: "runAheadFrames", .integer) }
        }
        // Every Playthrough has a start date: the column becomes NOT NULL, which SQLite does by rebuilding the table.
        migrator.registerMigration("v9 playthrough start required") { db in
            try db.create(table: "newPlaythrough") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("gameId", .integer).notNull().indexed().references("game", onDelete: .cascade)
                t.column("start", .text).notNull().check(sql: partialDateCheck("start"))
                t.column("end", .text).check(sql: partialDateCheck("end"))
                t.column("outcome", .text).check { ["finished", "dropped"].contains($0) }
                t.column("notes", .text)
                t.column("version", .text)
                t.column("playedVia", .text)
            }
            try db.execute(
                sql: """
                    INSERT INTO newPlaythrough SELECT id, gameId, start, end, outcome, notes, version, playedVia FROM playthrough;
                    DROP TABLE playthrough;
                    ALTER TABLE newPlaythrough RENAME TO playthrough;
                    """)
        }
        // Ratings are no longer imported from OpenEmu stars: imported entries go, with the flag and held stars.
        migrator.registerMigration("v10 no imported ratings") { db in
            try db.create(table: "newRatingEntry") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("gameId", .integer).notNull().indexed().references("game", onDelete: .cascade)
                t.column("day", .text).notNull()
                t.column("rating", .integer).check { $0 >= 0 && $0 <= 100 }  // tenths; NULL = cleared
                t.uniqueKey(["gameId", "day"])
            }
            try db.execute(
                sql: """
                    INSERT INTO newRatingEntry SELECT id, gameId, day, rating FROM ratingEntry WHERE NOT imported;
                    DROP TABLE ratingEntry;
                    ALTER TABLE newRatingEntry RENAME TO ratingEntry;
                    """)
            try db.alter(table: "heldOpenEmuData") { t in t.drop(column: "stars") }
        }
        migrator.registerMigration("v11 game boy model") { db in
            try db.alter(table: "game") { t in t.add(column: "gameBoyModel", .text) }
        }
        // ROM folders: a ROM is OpenEmu's (Z_PK and MD5) or a ROM folder's (its name), and a folder
        // ROM can be archived. Loosening NOT NULL is a table rebuild in SQLite.
        migrator.registerMigration("v12 rom folders") { db in
            try db.create(table: "newRom") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("openEmuPk", .integer).unique()
                t.column("md5", .text)
                t.column("folderName", .text)
                t.column("archived", .boolean).notNull().defaults(to: false)
                t.column("fileName", .text).notNull()
                t.column("name", .text)
                t.column("systemId", .text).notNull()
                t.column("missing", .boolean).notNull().defaults(to: false)
                t.column("version", .text)
                t.column("discNumber", .integer)
                t.column("discLabel", .text)
                t.column("gameId", .integer).references("game", onDelete: .cascade)
                t.column("matchKind", .text).check { ["automatic", "confirmed", "manual"].contains($0) }
                t.column("matchedAt", .datetime)
                t.column("suggestedIgdbGameId", .integer)
                t.column("suggestionKind", .text).check { ["checksum", "name"].contains($0) }
                t.column("checksumIgdbGameId", .integer)
                t.column("namesAgree", .boolean)
                t.column("libretroLookedUp", .boolean).notNull().defaults(to: false)
                t.column("libretroBoxart", .text)
                t.column("libretroSnap", .text)
                t.column("libretroTitle", .text)
                t.column("openEmuBoxArt", .text)
                t.uniqueKey(["systemId", "folderName"])
                t.check(sql: "(gameId IS NULL) = (matchKind IS NULL) AND (gameId IS NULL) = (matchedAt IS NULL)")
                t.check(sql: "(openEmuPk IS NULL) = (md5 IS NULL) AND (openEmuPk IS NULL) <> (folderName IS NULL)")
                t.check(sql: "NOT archived OR folderName IS NOT NULL")
            }
            let columns = """
                id, openEmuPk, md5, fileName, name, systemId, missing, version, discNumber, discLabel, gameId, matchKind,
                matchedAt, suggestedIgdbGameId, suggestionKind, checksumIgdbGameId, namesAgree, libretroLookedUp,
                libretroBoxart, libretroSnap, libretroTitle, openEmuBoxArt
                """
            try db.execute(
                sql: """
                    INSERT INTO newRom (\(columns)) SELECT \(columns) FROM rom;
                    DROP TABLE rom;
                    ALTER TABLE newRom RENAME TO rom;
                    CREATE INDEX rom_on_gameId ON rom(gameId);
                    """)
        }
        migrator.registerMigration("v13 players") { db in
            try db.create(table: "player") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("firstName", .text).notNull()
                t.column("lastName", .text).notNull()
                t.column("colour", .text).notNull()
            }
            try db.execute(sql: "CREATE UNIQUE INDEX player_on_name ON player(firstName COLLATE NOCASE, lastName COLLATE NOCASE)")
            try db.create(table: "playthroughPlayer") { t in
                t.column("playthroughId", .integer).notNull().references("playthrough", onDelete: .cascade)
                t.column("playerId", .integer).notNull().indexed().references("player", onDelete: .cascade)
                t.primaryKey(["playthroughId", "playerId"])
            }
        }
        // ROMs are keyed by Platform (ADR 0009): one ROM folder per IGDB Platform, a ROM known by its name in it.
        // `systemId` goes; a ROM folder's ROM (PS2's) keeps its folder's Platform, and an OpenEmu ROM takes its Game's
        // Platform, else its OpenEmu system's most likely one.
        // md5 stays, optional on any ROM. An OpenEmu ROM keeps `openEmuPk` (and no folder name) until
        // `migrate-openemu` moves its file into its Platform's ROM folder.
        migrator.registerMigration("v14 roms keyed by platform") { db in
            // Frozen here, so later changes to the app's tables can't change what this migration did.
            let systemDefaults: [String: Int] = [
                "openemu.system.gb": 33, "openemu.system.snes": 19, "openemu.system.nes": 18, "openemu.system.psx": 7,
                "openemu.system.sg": 29, "openemu.system.gba": 24, "openemu.system.nds": 20, "openemu.system.psp": 38,
                "openemu.system.n64": 4, "openemu.system.gc": 21, "openemu.system.sms": 64, "openemu.system.scd": 78,
                "openemu.system.saturn": 32, "openemu.system.gg": 35, "openemu.system.pcecd": 150, "ludeum.folder.ps2": 8,
            ]
            let names: [Int: String] = [
                33: "Game Boy", 19: "Super Nintendo Entertainment System", 18: "Nintendo Entertainment System", 7: "PlayStation",
                29: "Sega Mega Drive/Genesis", 24: "Game Boy Advance", 20: "Nintendo DS", 38: "PlayStation Portable",
                4: "Nintendo 64", 21: "Nintendo GameCube", 64: "Sega Master System/Mark III", 78: "Sega CD", 32: "Sega Saturn",
                35: "Sega Game Gear", 150: "Turbografx-16/PC Engine CD", 8: "PlayStation 2",
            ]
            // An unmatched ROM needs its system's Platform: one this table doesn't know stops the migration by name.
            let unknown = try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT systemId FROM rom WHERE gameId IS NULL
                    AND systemId NOT IN (\(databaseQuestionMarks(count: systemDefaults.count))) ORDER BY systemId
                    """, arguments: StatementArguments(Array(systemDefaults.keys)))
            if !unknown.isEmpty { throw UnknownOpenEmuSystems(systems: unknown) }
            // An unmatched ROM's Platform, and a ROM folder's, recorded if the journal doesn't know it yet.
            for (system, id) in systemDefaults {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO platform (id, name)
                        SELECT ?, ? WHERE EXISTS (SELECT 1 FROM rom WHERE systemId = ? AND (gameId IS NULL OR folderName IS NOT NULL))
                        """, arguments: [id, names[id], system])
            }
            try db.create(table: "newRom") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("platformId", .integer).notNull().references("platform")
                t.column("folderName", .text)
                t.column("openEmuPk", .integer).unique()
                t.column("md5", .text)
                t.column("archived", .boolean).notNull().defaults(to: false)
                t.column("fileName", .text).notNull()
                t.column("name", .text)
                t.column("missing", .boolean).notNull().defaults(to: false)
                t.column("version", .text)
                t.column("discNumber", .integer)
                t.column("discLabel", .text)
                t.column("gameId", .integer).references("game", onDelete: .cascade)
                t.column("matchKind", .text).check { ["automatic", "confirmed", "manual"].contains($0) }
                t.column("matchedAt", .datetime)
                t.column("suggestedIgdbGameId", .integer)
                t.column("suggestionKind", .text).check { ["checksum", "name"].contains($0) }
                t.column("checksumIgdbGameId", .integer)
                t.column("namesAgree", .boolean)
                t.column("libretroLookedUp", .boolean).notNull().defaults(to: false)
                t.column("libretroBoxart", .text)
                t.column("libretroSnap", .text)
                t.column("libretroTitle", .text)
                t.column("openEmuBoxArt", .text)
                t.uniqueKey(["platformId", "folderName"])
                t.check(sql: "(gameId IS NULL) = (matchKind IS NULL) AND (gameId IS NULL) = (matchedAt IS NULL)")
                t.check(sql: "(openEmuPk IS NULL) <> (folderName IS NULL)")
                t.check(sql: "NOT archived OR folderName IS NOT NULL")
            }
            let systemDefault =
                "CASE r.systemId "
                + systemDefaults.map { "WHEN '\($0.key)' THEN \($0.value)" }.joined(separator: " ") + " END"
            let columns = [
                "id", "folderName", "openEmuPk", "md5", "archived", "fileName", "name", "missing", "version", "discNumber",
                "discLabel", "gameId", "matchKind", "matchedAt", "suggestedIgdbGameId", "suggestionKind", "checksumIgdbGameId",
                "namesAgree", "libretroLookedUp", "libretroBoxart", "libretroSnap", "libretroTitle", "openEmuBoxArt",
            ]
            try db.execute(
                sql: """
                    INSERT INTO newRom (platformId, \(columns.joined(separator: ", ")))
                    SELECT COALESCE(CASE WHEN r.folderName IS NOT NULL THEN \(systemDefault) END, g.platformId, \(systemDefault)),
                        \(columns.map { "r.\($0)" }.joined(separator: ", "))
                    FROM rom r LEFT JOIN game g ON g.id = r.gameId;
                    DROP TABLE rom;
                    ALTER TABLE newRom RENAME TO rom;
                    CREATE INDEX rom_on_gameId ON rom(gameId);
                    """)
        }
        // Covers no longer fall back to OpenEmu's Box art: upload, then libretro, then IGDB.
        migrator.registerMigration("v15 no openemu box art") { db in
            try db.alter(table: "rom") { t in t.drop(column: "openEmuBoxArt") }
        }
        // OpenEmu is gone (ADR 0009): every ROM is a ROM folder's, known by its name, so `openEmuPk` goes and
        // `folderName` is required; Sync's tables go too. Only once no ROM is OpenEmu's: `LudeumStore` holds a
        // journal at `lastWithOpenEmu` until `migrate-openemu` has run, and this refuses rather than lose a ROM.
        // Migrations after this one wait with it.
        migrator.registerMigration(withoutOpenEmu) { db in
            if try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM rom WHERE openEmuPk IS NOT NULL)")! {
                throw OpenEmuROMsRemain()
            }
            for table in ["syncedCollection", "syncedCover", "openEmuLibrary"] { try db.execute(sql: "DROP TABLE IF EXISTS \(table)") }
            try db.create(table: "newRom") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("platformId", .integer).notNull().references("platform")
                t.column("folderName", .text).notNull()
                t.column("md5", .text)
                t.column("archived", .boolean).notNull().defaults(to: false)
                t.column("fileName", .text).notNull()
                t.column("name", .text)
                t.column("missing", .boolean).notNull().defaults(to: false)
                t.column("version", .text)
                t.column("discNumber", .integer)
                t.column("discLabel", .text)
                t.column("gameId", .integer).references("game", onDelete: .cascade)
                t.column("matchKind", .text).check { ["automatic", "confirmed", "manual"].contains($0) }
                t.column("matchedAt", .datetime)
                t.column("suggestedIgdbGameId", .integer)
                t.column("suggestionKind", .text).check { ["checksum", "name"].contains($0) }
                t.column("checksumIgdbGameId", .integer)
                t.column("namesAgree", .boolean)
                t.column("libretroLookedUp", .boolean).notNull().defaults(to: false)
                t.column("libretroBoxart", .text)
                t.column("libretroSnap", .text)
                t.column("libretroTitle", .text)
                t.uniqueKey(["platformId", "folderName"])
                t.check(sql: "(gameId IS NULL) = (matchKind IS NULL) AND (gameId IS NULL) = (matchedAt IS NULL)")
            }
            let columns = [
                "id", "platformId", "folderName", "md5", "archived", "fileName", "name", "missing", "version", "discNumber",
                "discLabel", "gameId", "matchKind", "matchedAt", "suggestedIgdbGameId", "suggestionKind", "checksumIgdbGameId",
                "namesAgree", "libretroLookedUp", "libretroBoxart", "libretroSnap", "libretroTitle",
            ].joined(separator: ", ")
            try db.execute(
                sql: """
                    INSERT INTO newRom (\(columns)) SELECT \(columns) FROM rom;
                    DROP TABLE rom;
                    ALTER TABLE newRom RENAME TO rom;
                    CREATE INDEX rom_on_gameId ON rom(gameId);
                    """)
        }
        // A ROM whose subfolder holds its Discs but no playlist, for the Review queue. The next Import sets it.
        migrator.registerMigration("v17 rom needs playlist") { db in
            try db.alter(table: "rom") { t in t.add(column: "needsPlaylist", .boolean).notNull().defaults(to: false) }
        }
        migrator.registerMigration("v18 rom in both forms") { db in
            try db.alter(table: "rom") { t in t.add(column: "inBothForms", .boolean).notNull().defaults(to: false) }
        }
        // An archived ROM's checksum: the CRC32 its archive's index gives its dump, where a loose one has an MD5.
        migrator.registerMigration("v19 rom crc") { db in
            try db.alter(table: "rom") { t in t.add(column: "crc", .text) }
        }
        return migrator
    }
}
