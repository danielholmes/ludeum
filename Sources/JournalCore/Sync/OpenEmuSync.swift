import Foundation
import GRDB
import ImageIO

/// Why Sync won't run.
public enum SyncGuard: String, Sendable, Hashable, CaseIterable {
    /// OpenEmu (`org.openemu.OpenEmu`) is running.
    case openEmuRunning
    /// A Dropbox "conflicted copy" sits next to the store.
    case conflictedCopy
    /// The store's UUID isn't the one the journal Imported.
    case differentLibrary
    /// `PRAGMA integrity_check` failed.
    case integrityFailed
}

public enum SyncError: Error, Equatable {
    case guardsFailed([SyncGuard])
    /// The store failed its integrity check after the write. Restore OpenEmu's backup.
    case integrityFailedAfterWrite(backupName: String)
}

/// What a Sync will do, for the Sync page's preview.
public struct SyncPreview: Sendable {
    public struct StarChange: Sendable, Equatable {
        public let gameName: String
        public let stars: Int
        /// The OpenEmu game rows that change, with their stars now.
        public let current: [Int]
    }

    public struct CollectionChange: Sendable, Equatable {
        public let name: String
        /// The name it has in OpenEmu now, when it's renamed.
        public let renamedFrom: String?
        public let isNew: Bool
        public let added: Int
        public let removed: Int
    }

    /// A regular OpenEmu collection the journal doesn't own: deleted only when ticked.
    public struct OtherCollection: Sendable, Equatable, Identifiable {
        public let pk: Int64
        public let name: String
        public let gameCount: Int
        public var id: Int64 { pk }
    }

    public struct CoverChange: Sendable, Equatable {
        public let gameName: String
    }

    public struct SkippedCover: Sendable, Equatable {
        public enum Reason: String, Sendable {
            /// OpenEmu has its own box art, which Sync never touches.
            case hasBoxArt
            /// The game is waiting for its OpenVGDB lookup, which can replace its box art.
            case awaitingOpenVGDB
            /// IGDB's cover couldn't be downloaded this time.
            case downloadFailed
            /// The Cover isn't an image ImageIO can read, so its size is unknown.
            case unreadable
        }

        public let gameName: String
        public let reason: Reason
    }

    public let failedGuards: [SyncGuard]
    public let starChanges: [StarChange]
    public let collectionChanges: [CollectionChange]
    /// Collections of deleted Lists, deleted without asking.
    public let deletedListCollections: [String]
    public let otherCollections: [OtherCollection]
    public let coversAdded: [CoverChange]
    public let coversReplaced: [CoverChange]
    public let coversSkipped: [SkippedCover]
    /// Games with unresolved Duplicate Versions, which aren't synced.
    public let notSynced: [Game]
}

public struct SyncResult: Sendable {
    public let preview: SyncPreview
    /// OpenEmu's database backup, in the backup folder.
    public let backupName: String
}

/// One-way Sync of the journal into OpenEmu's Core Data store, written the way Core Data would.
public final class OpenEmuSync: Sendable {
    let journal: JournalStore
    let covers: Covers?
    let backupFolder: URL
    let isOpenEmuRunning: @Sendable () -> Bool
    let clock: TimeSource

    public init(
        journal: JournalStore, covers: Covers?, backupFolder: URL, clock: TimeSource = SystemTimeSource(),
        isOpenEmuRunning: @escaping @Sendable () -> Bool
    ) {
        self.journal = journal
        self.covers = covers
        self.backupFolder = backupFolder
        self.clock = clock
        self.isOpenEmuRunning = isOpenEmuRunning
    }

    /// The Rating ÷ 2, rounded half up; below 1.0 (and unrated) is no stars.
    public static func stars(for rating: Rating?) -> Int {
        guard let rating else { return 0 }
        return min(5, (rating.tenths + 10) / 20)
    }

    public func preview(library: URL) async throws -> SyncPreview {
        let failed = try guards(library: library)
        if failed.contains(.differentLibrary) || failed.contains(.integrityFailed) {
            return SyncPreview(
                failedGuards: failed, starChanges: [], collectionChanges: [], deletedListCollections: [], otherCollections: [],
                coversAdded: [], coversReplaced: [], coversSkipped: [], notSynced: [])
        }
        return try await plan(library: library).preview(failedGuards: failed)
    }

    /// Syncs, deleting the ticked other collections. Refused while a guard fails.
    public func sync(library: URL, deleting: Set<Int64>) async throws -> SyncResult {
        let failed = try guards(library: library)
        guard failed.isEmpty else { throw SyncError.guardsFailed(failed) }
        var plan = try await plan(library: library)
        plan.deleting = plan.others.filter { deleting.contains($0.pk) }
        // Planning downloads covers, which takes a while: check again right before writing.
        let stillFailing = try guards(library: library)
        guard stillFailing.isEmpty else { throw SyncError.guardsFailed(stillFailing) }
        let backupName = try backUpOpenEmu(library: library)
        try plan.write(library: library)
        // Record what was written before anything else can fail, so the journal matches OpenEmu.
        try plan.recordInJournal(journal)
        guard try integrityOK(library: library) else { throw SyncError.integrityFailedAfterWrite(backupName: backupName) }
        plan.deleteReplacedFiles(library: library)
        return SyncResult(preview: plan.preview(failedGuards: []), backupName: backupName)
    }

    // MARK: Guards

    public func guards(library: URL) throws -> [SyncGuard] {
        var failed: [SyncGuard] = []
        if isOpenEmuRunning() { failed.append(.openEmuRunning) }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: library.path(percentEncoded: false))) ?? []
        if files.contains(where: { $0.hasPrefix("Library") && $0.localizedCaseInsensitiveContains("conflicted copy") }) {
            failed.append(.conflictedCopy)
        }
        let uuid = try readOnly(library) { try String.fetchOne($0, sql: "SELECT Z_UUID FROM Z_METADATA") }
        if uuid != (try journal.openEmuStoreUUID()) { failed.append(.differentLibrary) }
        if try !integrityOK(library: library) { failed.append(.integrityFailed) }
        return failed
    }

    private func integrityOK(library: URL) throws -> Bool {
        try readOnly(library) { try String.fetchOne($0, sql: "PRAGMA integrity_check") == "ok" }
    }

    private func readOnly<T>(_ library: URL, _ read: (Database) throws -> T) throws -> T {
        let db = try OpenEmuLibrary.openForReading(OpenEmuLibrary.databaseFile(in: library))
        defer { try? db.close() }
        return try db.read(read)
    }

    /// SQLite's backup API, while OpenEmu is closed: the store is WAL, so copying the file alone can lose data.
    private func backUpOpenEmu(library: URL) throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss"
        let name = "OpenEmu Library.storedata \(formatter.string(from: clock.now())) before-sync.sqlite"
        try OpenEmuLibrary.snapshot(library: library, to: backupFolder.appending(path: name))
        return name
    }

    // MARK: Planning

    private func plan(library: URL) async throws -> SyncPlan {
        let store = try readOnly(library) { try OpenEmuStore.read($0) }
        var plan = try journal.syncPlan(store: store)
        // Covers: IGDB's (downloaded on demand) or the journal's own, per OpenEmu game row.
        for game in plan.games {
            var source: CoverSource = .placeholder
            var failedDownload = false
            if let covers {
                do { source = try await covers.cover(for: game.id) } catch { failedDownload = true }
            }
            plan.planCovers(for: game, source: source, downloadFailed: failedDownload)
        }
        return plan
    }
}

/// What the Sync reads from OpenEmu's store.
struct OpenEmuStore {
    struct GameRow {
        let pk: Int64
        let stars: Int
        let status: Int
        let boxImage: Int64?
    }

    struct Collection {
        let pk: Int64
        let name: String
        var members: Set<Int64>
    }

    let collectionEntity: Int
    let collectionRoot: Int
    let imageEntity: Int
    let imageRoot: Int
    let joinTable: String
    let joinCollection: String
    let joinGame: String
    /// `ZROM.Z_PK` → `ZGAME.Z_PK`, looked up fresh each Sync.
    let gameOfROM: [Int64: Int64]
    let games: [Int64: GameRow]
    /// Regular collections only (not smart collections or folders), by `Z_PK`.
    let collections: [Int64: Collection]

    static func read(_ db: Database) throws -> OpenEmuStore {
        let entities = try Row.fetchAll(db, sql: "SELECT Z_ENT, Z_NAME, Z_SUPER FROM Z_PRIMARYKEY")
        func entity(_ name: String) throws -> Int {
            guard let row = entities.first(where: { $0["Z_NAME"] as String == name }) else {
                throw DatabaseError(message: "OpenEmu's library has no \(name) entity")
            }
            return row["Z_ENT"]
        }
        func root(_ ent: Int) -> Int {
            var current = ent
            while let row = entities.first(where: { $0["Z_ENT"] as Int == current }), let parent = row["Z_SUPER"] as Int?, parent != 0 {
                current = parent
            }
            return current
        }
        let collection = try entity("Collection")
        let game = try entity("Game")
        let image = try entity("Image")
        let joinTable = "Z_\(collection)GAMES"
        let joinCollection = "Z_\(collection)COLLECTIONS"
        let joinGame = "Z_\(game)GAMES"
        var collections: [Int64: Collection] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT Z_PK, ZNAME FROM ZABSTRACTCOLLECTION WHERE Z_ENT = ?", arguments: [collection]) {
            collections[row["Z_PK"]] = Collection(pk: row["Z_PK"], name: row["ZNAME"] ?? "", members: [])
        }
        for row in try Row.fetchAll(db, sql: "SELECT \(joinCollection) AS c, \(joinGame) AS g FROM \(joinTable)") {
            collections[row["c"]]?.members.insert(row["g"])
        }
        var gameOfROM: [Int64: Int64] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT Z_PK, ZGAME FROM ZROM WHERE ZGAME IS NOT NULL") {
            gameOfROM[row["Z_PK"]] = row["ZGAME"]
        }
        var games: [Int64: GameRow] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT Z_PK, ZRATING, ZSTATUS, ZBOXIMAGE FROM ZGAME") {
            games[row["Z_PK"]] = GameRow(
                pk: row["Z_PK"], stars: row["ZRATING"] ?? 0, status: row["ZSTATUS"] ?? 0, boxImage: row["ZBOXIMAGE"])
        }
        return OpenEmuStore(
            collectionEntity: collection, collectionRoot: root(collection), imageEntity: image, imageRoot: root(image),
            joinTable: joinTable,
            joinCollection: joinCollection, joinGame: joinGame, gameOfROM: gameOfROM, games: games, collections: collections)
    }
}
