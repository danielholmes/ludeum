import Foundation
import GRDB
import ImageIO
import Synchronization
import Testing
import UniformTypeIdentifiers

@testable import LudeumCore

/// Whether "OpenEmu" is running, for the guard.
final class RunningFlag: @unchecked Sendable {
    private let value = Mutex(false)
    var isOn: Bool {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}

@Suite struct SyncTests {
    let h: Harness
    let j: LudeumHarness
    let oe: FakeOpenEmu
    let openEmuRunning = RunningFlag()
    let backups: URL

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        oe = try FakeOpenEmu(in: h.directory)
        backups = h.directory.appending(path: "openemu backups", directoryHint: .isDirectory)
        let snes: [String: Any] = ["id": 19, "name": "SNES"]
        h.internet.addPlatform(19, "SNES")
        h.internet.addGame(1103, "Super Metroid", fields: ["platforms": [snes], "cover": ["image_id": "co1"]])
        h.internet.addGame(1070, "Super Mario World", fields: ["platforms": [snes]])
        h.internet.addHash(md5: "aa", game: 1103, platform: 19)
        h.internet.addHash(md5: "bb", game: 1070, platform: 19)
    }

    var sync: OpenEmuSync {
        let running = openEmuRunning
        return OpenEmuSync(
            journal: j.journal, covers: h.covers(j.journal), backupFolder: backups,
            isOpenEmuRunning: { running.isOn })
    }

    func firstImport() async throws {
        let run = FirstImport(
            igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil, draftFolder: h.directory.appending(path: "draft"),
            libretro: h.libretro)
        let draft = try await run.start(library: oe.folder) { _, _ in }
        try await run.commit(draft)
    }

    func game(_ name: String) throws -> GameID {
        try #require(try j.journal.library(LibraryFilter(), sort: .name, ascending: true).first { $0.name == name }?.id)
    }

    // MARK: Stars

    @Test func ratingsBecomeStarsOnEveryOpenEmuGameOfTheGame() async throws {
        let usa = try oe.addROM("Super Metroid (USA) (Disc 1)", md5: "aa")
        h.internet.addHash(md5: "a2", game: 1103, platform: 19)
        let disc2 = try oe.addROM("Super Metroid (USA) (Disc 2)", md5: "a2")
        let mario = try oe.addROM("Super Mario World (USA)", md5: "bb", stars: 3)
        try await firstImport()
        try j.journal.setRating(try game("Super Metroid"), Rating(tenths: 70))  // 3.5 → 4
        try j.journal.setRating(try game("Super Mario World"), nil)

        let preview = try await sync.preview(library: oe.folder)
        #expect(preview.starChanges.count == 2)
        _ = try await sync.sync(library: oe.folder, deleting: [])

        #expect(try oe.stars(usa) == 4)
        #expect(try oe.stars(disc2) == 4)
        #expect(try oe.stars(mario) == 0)
    }

    @Test func starsRoundHalfUpAndBelowOneAreNone() {
        #expect(OpenEmuSync.stars(for: Rating(tenths: 9)) == 0)
        #expect(OpenEmuSync.stars(for: Rating(tenths: 10)) == 1)
        #expect(OpenEmuSync.stars(for: Rating(tenths: 89)) == 4)
        #expect(OpenEmuSync.stars(for: Rating(tenths: 90)) == 5)
        #expect(OpenEmuSync.stars(for: nil) == 0)
    }

    // MARK: Collections

    @Test func journalOwnedCollectionsAreAdoptedByNameAndOverwritten() async throws {
        let metroid = try oe.addROM("Super Metroid (USA)", md5: "aa", collections: ["_TODO", "Metroid"])
        let mario = try oe.addROM("Super Mario World (USA)", md5: "bb", collections: ["_Completed"])
        try await firstImport()
        _ = try await sync.sync(library: oe.folder, deleting: [])  // the first Sync adopts OpenEmu's collections by name
        let todoPK = try await oe.db.read { try Int64.fetchOne($0, sql: "SELECT Z_PK FROM ZABSTRACTCOLLECTION WHERE ZNAME = '_TODO'")! }
        try j.journal.setIntent(try game("Super Metroid"), nil)
        try j.journal.setIntent(try game("Super Mario World"), .upNext)
        let list = try j.journal.lists().first { $0.name == "Metroid" }!.id
        try j.journal.renameList(list, "Metroid series")
        try j.journal.addToList(list, try game("Super Mario World"))

        _ = try await sync.sync(library: oe.folder, deleting: [])

        let collections = try oe.collections()
        #expect(collections["_TODO"] == [])
        #expect(collections["_TODO Next"] == [mario])
        #expect(collections["_Completed"] == [mario])
        #expect(collections["_Current"] == [])
        #expect(collections["Metroid series"] == [metroid, mario])
        #expect(collections["Metroid"] == nil)
        let todoAfter = try await oe.db.read { try Int64.fetchOne($0, sql: "SELECT Z_PK FROM ZABSTRACTCOLLECTION WHERE ZNAME = '_TODO'")! }
        #expect(todoAfter == todoPK)  // updated in place
    }

    @Test func romsStillInTheReviewQueueKeepTheirCollections() async throws {
        let unknown = try oe.addROM("Unknown Homebrew", md5: "zz", collections: ["_TODO"])
        let metroid = try oe.addROM("Super Metroid (USA)", md5: "aa", collections: ["_TODO"])
        try await firstImport()
        try j.journal.setIntent(try game("Super Metroid"), nil)

        _ = try await sync.sync(library: oe.folder, deleting: [])

        #expect(try oe.collections()["_TODO"] == [unknown])
        #expect(metroid != unknown)
    }

    @Test func otherCollectionsAreDeletedOnlyWhenTicked() async throws {
        try oe.addROM("Super Metroid (USA)", md5: "aa")
        try await firstImport()
        let keep = try oe.addCollection("Made in OpenEmu")
        let drop = try oe.addCollection("Old stuff")

        let preview = try await sync.preview(library: oe.folder)
        #expect(Set(preview.otherCollections.map(\.name)) == ["Made in OpenEmu", "Old stuff"])
        _ = try await sync.sync(library: oe.folder, deleting: [drop])

        let collections = try oe.collections()
        #expect(collections["Made in OpenEmu"] != nil)
        #expect(collections["Old stuff"] == nil)
        #expect(keep != drop)
        let smart = try await oe.db.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM ZABSTRACTCOLLECTION WHERE ZNAME = 'Recently Added'")!
        }
        #expect(smart == 1)
    }

    @Test func aDeletedListsCollectionGoesWithoutAsking() async throws {
        try oe.addROM("Super Metroid (USA)", md5: "aa", collections: ["Metroid"])
        try await firstImport()
        _ = try await sync.sync(library: oe.folder, deleting: [])
        try j.journal.deleteList(try j.journal.lists().first { $0.name == "Metroid" }!.id)

        let preview = try await sync.preview(library: oe.folder)
        #expect(preview.otherCollections.isEmpty)
        _ = try await sync.sync(library: oe.folder, deleting: [])

        #expect(try oe.collections()["Metroid"] == nil)
    }

    @Test func insertedRowsTakeKeysFromTheRootEntityAndRaiseZMax() async throws {
        try oe.addROM("Super Metroid (USA)", md5: "aa")
        try await firstImport()
        let list = try j.journal.createList("New List")
        try j.journal.addToList(list, try game("Super Metroid"))
        let before = try await oe.db.read { try Int64.fetchOne($0, sql: "SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_ENT = 1")! }

        _ = try await sync.sync(library: oe.folder, deleting: [])

        let after = try await oe.db.read { try Int64.fetchOne($0, sql: "SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_ENT = 1")! }
        #expect(after > before)
        let ours = try await oe.db.read { try Int64.fetchOne($0, sql: "SELECT Z_PK FROM ZABSTRACTCOLLECTION WHERE ZNAME = 'New List'")! }
        #expect(ours > before && ours <= after)
        // OpenEmu's next insert takes a fresh key instead of overwriting ours.
        let openEmus = try oe.addCollection("Made after Sync")
        #expect(openEmus > ours)
        #expect(try oe.collections()["New List"] != nil)
        let entity = try await oe.db.read { try Int.fetchOne($0, sql: "SELECT Z_ENT FROM ZABSTRACTCOLLECTION WHERE ZNAME = 'New List'")! }
        #expect(entity == FakeOpenEmu.collection)
    }

    // MARK: Covers

    @Test func coversAreWrittenOnlyForGamesWithoutBoxArtAndNotAwaitingLookup() async throws {
        let metroid = try oe.addROM("Super Metroid (USA)", md5: "aa")
        h.internet.addHash(md5: "a3", game: 1103, platform: 19)
        let pending = try oe.addROM("Super Metroid (Japan)", md5: "a3", fileName: nil, status: 3)
        let mario = try oe.addROM("Super Mario World (USA)", md5: "bb", boxArt: testImage(width: 10, height: 10))
        try await firstImport()

        let preview = try await sync.preview(library: oe.folder)
        #expect(preview.coversAdded.count == 1)
        #expect(Set(preview.coversSkipped.map(\.reason)) == [.awaitingOpenVGDB, .hasBoxArt])
        _ = try await sync.sync(library: oe.folder, deleting: [])

        let rows = try oe.db.read { db in
            try Row.fetchAll(
                db,
                sql:
                    "SELECT g.Z_PK, g.ZBOXIMAGE, i.ZBOX, i.ZRELATIVEPATH, i.ZFORMAT FROM ZGAME g LEFT JOIN ZIMAGE i ON i.Z_PK = g.ZBOXIMAGE"
            )
        }
        let written = try #require(rows.first { $0["Z_PK"] as Int64 == metroid })
        #expect(written["ZBOX"] as Int64 == metroid)
        #expect(written["ZFORMAT"] as Int == 3)
        let file = oe.folder.appending(path: "Artwork").appending(path: written["ZRELATIVEPATH"] as String)
        #expect(try Data(contentsOf: file) == FakeInternet.coverJPEG)
        #expect(rows.first { $0["Z_PK"] as Int64 == pending }?["ZBOXIMAGE"] as Int64? == nil)
        #expect(rows.first { $0["Z_PK"] as Int64 == mario }?["ZRELATIVEPATH"] as String? == "ART-\(mario)")
    }

    @Test func aCoverSyncWroteIsReplacedWhenTheGamesCoverChanges() async throws {
        h.internet.addGame(5, "Hermano", fields: ["platforms": [["id": 19, "name": "SNES"]]])
        h.internet.addHash(md5: "hh", game: 5, platform: 19)
        let hermano = try oe.addROM("Hermano", md5: "hh")
        try await firstImport()
        let covers = h.covers(j.journal)
        try covers.upload(testImage(width: 100, height: 140), for: try game("Hermano"))
        _ = try await sync.sync(library: oe.folder, deleting: [])
        let first = try oe.db.read {
            try Row.fetchOne(
                $0, sql: "SELECT i.Z_PK, i.ZRELATIVEPATH FROM ZGAME g JOIN ZIMAGE i ON i.Z_PK = g.ZBOXIMAGE WHERE g.Z_PK = ?",
                arguments: [hermano])!
        }
        try covers.upload(testImage(width: 200, height: 280), for: try game("Hermano"))

        let preview = try await sync.preview(library: oe.folder)
        #expect(preview.coversReplaced.count == 1)
        _ = try await sync.sync(library: oe.folder, deleting: [])

        let second = try oe.db.read {
            try Row.fetchOne(
                $0, sql: "SELECT i.Z_PK, i.ZRELATIVEPATH, i.ZWIDTH FROM ZGAME g JOIN ZIMAGE i ON i.Z_PK = g.ZBOXIMAGE WHERE g.Z_PK = ?",
                arguments: [hermano])!
        }
        #expect(second["Z_PK"] as Int64 == first["Z_PK"] as Int64)  // in place
        #expect(second["ZRELATIVEPATH"] as String != first["ZRELATIVEPATH"] as String)
        #expect(second["ZWIDTH"] as Double == 200)
        #expect(
            !FileManager.default.fileExists(
                atPath: oe.folder.appending(path: "Artwork/\(first["ZRELATIVEPATH"] as String)").path(percentEncoded: false)))
    }

    @Test func boxArtChangedInOpenEmuIsLeftAlone() async throws {
        h.internet.addGame(5, "Hermano", fields: ["platforms": [["id": 19, "name": "SNES"]]])
        h.internet.addHash(md5: "hh", game: 5, platform: 19)
        let hermano = try oe.addROM("Hermano", md5: "hh")
        try await firstImport()
        let covers = h.covers(j.journal)
        try covers.upload(testImage(width: 100, height: 140), for: try game("Hermano"))
        _ = try await sync.sync(library: oe.folder, deleting: [])
        // I pick different box art in OpenEmu.
        try await oe.db.write { db in
            let image = try FakeOpenEmu.nextKey(db, root: FakeOpenEmu.image)
            try db.execute(sql: "INSERT INTO ZIMAGE VALUES (?, 10, 1, 3, ?, 1, 1, 'MINE', NULL)", arguments: [image, hermano])
            try db.execute(sql: "UPDATE ZGAME SET ZBOXIMAGE = ? WHERE Z_PK = ?", arguments: [image, hermano])
        }
        try covers.upload(testImage(width: 200, height: 280), for: try game("Hermano"))

        _ = try await sync.sync(library: oe.folder, deleting: [])

        let path = try await oe.db.read {
            try String.fetchOne(
                $0, sql: "SELECT i.ZRELATIVEPATH FROM ZGAME g JOIN ZIMAGE i ON i.Z_PK = g.ZBOXIMAGE WHERE g.Z_PK = ?", arguments: [hermano])
        }
        #expect(path == "MINE")
        let synced = try await j.journal.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM syncedCover")! }
        #expect(synced == 0)
    }

    func ongoingImport() async throws {
        _ = try await OngoingImport(
            igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil, snapshotFile: h.directory.appending(path: "s.sqlite"),
            libretro: h.libretro
        ).run(library: oe.folder)
    }

    func boxArt(_ game: Int64) throws -> Row? {
        try oe.db.read {
            try Row.fetchOne(
                $0, sql: "SELECT i.Z_PK, i.ZRELATIVEPATH, i.ZWIDTH FROM ZGAME g JOIN ZIMAGE i ON i.Z_PK = g.ZBOXIMAGE WHERE g.Z_PK = ?",
                arguments: [game])
        }
    }

    @Test func libretrosPNGIsWrittenAsJPEG() async throws {
        h.internet.addLibretro("Nintendo_-_Super_Nintendo_Entertainment_System", ["Super Metroid (USA)"])
        let metroid = try oe.addROM("Super Metroid (USA)", md5: "aa")
        try await firstImport()

        _ = try await sync.sync(library: oe.folder, deleting: [])

        let row = try #require(try boxArt(metroid))
        let file = oe.folder.appending(path: "Artwork").appending(path: row["ZRELATIVEPATH"] as String)
        let source = try #require(CGImageSourceCreateWithData(try Data(contentsOf: file) as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        #expect(row["ZWIDTH"] as Double == 12)
    }

    @Test func anIGDBCoverSyncWroteIsReplacedOnceLibretroHasBoxArt() async throws {
        let metroid = try oe.addROM("Super Metroid (USA)", md5: "aa")
        try await firstImport()
        _ = try await sync.sync(library: oe.folder, deleting: [])
        let igdb = try #require(try boxArt(metroid))
        // libretro gains the box scan; the ROM is looked up again at a later Import.
        h.internet.addLibretro("Nintendo_-_Super_Nintendo_Entertainment_System", ["Super Metroid (USA)"])
        try await j.journal.db.write { try $0.execute(sql: "UPDATE rom SET libretroLookedUp = 0") }
        try await ongoingImport()

        #expect(try await sync.preview(library: oe.folder).coversReplaced.count == 1)
        _ = try await sync.sync(library: oe.folder, deleting: [])

        let replaced = try #require(try boxArt(metroid))
        #expect(replaced["Z_PK"] as Int64 == igdb["Z_PK"] as Int64)
        #expect(replaced["ZWIDTH"] as Double == 12)
    }

    @Test func aCoverSyncWroteIsntTakenForOpenEmusOwnBoxArt() async throws {
        let metroid = try oe.addROM("Super Metroid (USA)", md5: "aa")
        try await firstImport()
        _ = try await sync.sync(library: oe.folder, deleting: [])

        try await ongoingImport()

        let path = try await j.journal.db.read { try String.fetchOne($0, sql: "SELECT openEmuBoxArt FROM rom") }
        #expect(path == nil)
        let preview = try await sync.preview(library: oe.folder)
        #expect(preview.coversReplaced.isEmpty && preview.coversAdded.isEmpty)
        #expect(try boxArt(metroid) != nil)
    }

    // MARK: Guards, backup and Duplicate Versions

    @Test func guardsRefuseWhileOpenEmuRunsWithAConflictedCopyOrAnotherLibrary() async throws {
        try oe.addROM("Super Metroid (USA)", md5: "aa")
        try await firstImport()

        openEmuRunning.isOn = true
        #expect(try await sync.preview(library: oe.folder).failedGuards == [.openEmuRunning])
        await #expect(throws: SyncError.guardsFailed([.openEmuRunning])) { try await sync.sync(library: oe.folder, deleting: []) }
        openEmuRunning.isOn = false

        let conflicted = oe.folder.appending(path: "Library (Daniel's conflicted copy 2026-10-01).storedata")
        try Data().write(to: conflicted)
        #expect(try await sync.preview(library: oe.folder).failedGuards == [.conflictedCopy])
        try FileManager.default.removeItem(at: conflicted)

        try oe.replaceStore(uuid: "OTHER")
        #expect(try await sync.preview(library: oe.folder).failedGuards == [.differentLibrary])
    }

    @Test func syncBacksUpOpenEmuFirstAndLeavesAnEmptyWAL() async throws {
        try oe.addROM("Super Metroid (USA)", md5: "aa")
        try await firstImport()
        try j.journal.setRating(try game("Super Metroid"), Rating(tenths: 100))

        let result = try await sync.sync(library: oe.folder, deleting: [])

        let backup = backups.appending(path: result.backupName)
        #expect(FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)))
        let wal = oe.folder.appending(path: "Library.storedata-wal")
        let size = (try? FileManager.default.attributesOfItem(atPath: wal.path(percentEncoded: false))[.size] as? Int) ?? 0
        #expect(size == 0)
        let opt = try await oe.db.read { try Int.fetchOne($0, sql: "SELECT Z_OPT FROM ZGAME WHERE Z_PK = 1")! }
        #expect(opt == 3)  // stars and the new Cover, each +1
    }

    @Test func aGameWithDuplicateVersionsIsntSynced() async throws {
        let japan = try oe.addROM("Super Metroid (Japan)", md5: "aa")
        try await firstImport()
        h.internet.addHash(md5: "a2", game: 1103, platform: 19)
        try oe.addROM("Super Metroid (USA)", md5: "a2")
        _ = try await OngoingImport(
            igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil, snapshotFile: h.directory.appending(path: "s.sqlite")
        ).run(library: oe.folder)
        try j.journal.setRating(try game("Super Metroid"), Rating(tenths: 100))

        let preview = try await sync.preview(library: oe.folder)
        #expect(preview.notSynced.map(\.name) == ["Super Metroid"])
        _ = try await sync.sync(library: oe.folder, deleting: [])

        #expect(try oe.stars(japan) == 0)
    }
}
