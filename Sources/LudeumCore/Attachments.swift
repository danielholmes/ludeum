import Foundation
import GRDB

/// A file about a Game that I keep with it, such as its Manual, a map or a guide, opened in whatever app the system uses.
public struct Attachment: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let game: GameID
    /// Its file's name in its Game's folder, extension and all.
    public let fileName: String
    public let isManual: Bool
    /// Its file wasn't in its Game's folder when last looked for.
    public let missing: Bool
    /// Where its file is, or should be.
    public let url: URL

    /// Its name without the extension, as Rename edits it.
    public var name: String { (fileName as NSString).deletingPathExtension }
}

/// An Attachment whose file is missing, waiting in the Review queue for me to Locate it or Delete it.
public struct MissingAttachment: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let fileName: String
    public let game: Game
}

public enum AttachmentError: Error, Equatable {
    /// Only single files can be Attachments: a folder of scans is zipped, or made a PDF, first.
    case notAFile(String)
    /// The file is already in `Attachments/`, so it's one of a Game's, or one I put there myself.
    case alreadyInAttachments(String)
    /// Another of the Game's Attachments, or another file in its folder, already has the name.
    case nameTaken
    case nameRequired
    case notFound
}

/// Attachments' files, in the Data folder's `Attachments/<Platform>/<Game name>/` (ADR 0014). The journal says which Game
/// each belongs to and remembers each Game's folder, so its files can't be orphaned by a rename: the folder follows the
/// Game's name when I ask (`follow`), and a Game sharing another's name on its Platform gets `<Game name> (2)`. Files I
/// didn't add in Ludeum are left alone.
public struct Attachments: Sendable {
    let journal: LudeumStore
    /// `Attachments/` in the Data folder.
    public let root: URL
    let moveToTrash: @Sendable (URL) throws -> Void

    public init(
        journal: LudeumStore, root: URL,
        moveToTrash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.journal = journal
        self.root = root
        self.moveToTrash = moveToTrash
    }

    private var files: FileManager { .default }

    /// Attachments with their Game's folder, which their file is in.
    private static let selectWithFolder = "SELECT a.*, g.attachmentFolder FROM attachment a JOIN game g ON g.id = a.gameId"

    // MARK: Reading

    /// The Game's Attachments: Manuals first, then by name.
    public func attachments(of game: GameID) throws -> [Attachment] {
        try journal.db.read { db in
            guard try db.tableExists("attachment") else { return [] }
            return try Row.fetchAll(
                db, sql: "\(Self.selectWithFolder) WHERE a.gameId = ? ORDER BY a.manual DESC, a.fileName COLLATE NOCASE, a.id",
                arguments: [game]
            )
            .map(attachment)
        }
    }

    public func manuals(of game: GameID) throws -> [Attachment] { try attachments(of: game).filter(\.isManual) }

    private func attachment(_ id: Int64) throws -> Attachment {
        let row = try journal.db.read { db in try Row.fetchOne(db, sql: "\(Self.selectWithFolder) WHERE a.id = ?", arguments: [id]) }
        guard let row else { throw AttachmentError.notFound }
        return attachment(row)
    }

    private func attachment(_ row: Row) -> Attachment {
        let fileName: String = row["fileName"]
        return Attachment(
            id: row["id"], game: row["gameId"], fileName: fileName, isManual: row["manual"], missing: row["missing"],
            url: url(row["attachmentFolder"]).appending(path: fileName, directoryHint: .notDirectory))
    }

    /// A folder in `Attachments/`, by its path there.
    private func url(_ folder: String) -> URL { root.appending(path: folder, directoryHint: .isDirectory) }

    private func path(_ url: URL) -> String { url.path(percentEncoded: false) }

    private func exists(_ url: URL) -> Bool { files.fileExists(atPath: path(url)) }

    /// The Game's folder's path in `Attachments/`; nil until it has one.
    private static func folder(_ db: Database, of game: GameID) throws -> String? {
        try String.fetchOne(db, sql: "SELECT attachmentFolder FROM game WHERE id = ?", arguments: [game])
    }

    // MARK: Adding

    /// Copies each file into the Game's folder under its own name (a name already there gets ` (2)`), as an Attachment, a
    /// Manual if `manual`. A moved file's original goes to the Trash once it's in. Refused, adding nothing, when one isn't
    /// a file, or is already in `Attachments/`.
    @discardableResult
    public func add(_ sources: [URL], to game: GameID, manual: Bool = false, moving: Bool = false) throws -> [Attachment] {
        for source in sources { try checkPickable(source) }
        let folder = try folder(of: game)
        var added: [Int64] = []
        for source in sources {
            // Copied inside the write, so a failed copy records nothing and a refused insert copies nothing.
            try journal.db.write { db in
                let fileName = try freeName(db, for: source.lastPathComponent, in: folder, of: game)
                try db.execute(
                    sql: "INSERT INTO attachment (gameId, fileName, manual) VALUES (?, ?, ?)", arguments: [game, fileName, manual])
                added.append(db.lastInsertedRowID)
                try files.copyItem(at: source, to: url(folder).appending(path: fileName, directoryHint: .notDirectory))
            }
            if moving { try moveToTrash(source) }
        }
        return try attachments(of: game).filter { added.contains($0.id) }
    }

    /// A file can be picked when it's a single file outside `Attachments/`.
    private func checkPickable(_ file: URL) throws {
        var isDirectory: ObjCBool = false
        guard files.fileExists(atPath: path(file), isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw AttachmentError.notAFile(file.lastPathComponent)
        }
        if Self.isWithin(file, root) { throw AttachmentError.alreadyInAttachments(file.lastPathComponent) }
    }

    private static func isWithin(_ file: URL, _ folder: URL) -> Bool {
        let file = file.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let folder = folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        return file.count > folder.count && zip(file, folder).allSatisfy { $0.lowercased() == $1.lowercased() }
    }

    /// The Game's folder, by its path in `Attachments/`: named and made the first time it's needed.
    private func folder(of game: GameID) throws -> String {
        let folder = try journal.db.write { db in
            if let folder = try Self.folder(db, of: game) { return folder }
            let folder = try freeFolder(db, base: try baseFolder(db, of: game), for: game)
            try db.execute(sql: "UPDATE game SET attachmentFolder = ? WHERE id = ?", arguments: [folder, game])
            return folder
        }
        try files.createDirectory(at: url(folder), withIntermediateDirectories: true)
        return folder
    }

    /// `<Platform>/<Game name>`: the Platform's ROM folder's name if it has one, else IGDB's, and the Game's display name.
    private func baseFolder(_ db: Database, of game: GameID) throws -> String {
        guard
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT g.platformId, p.name AS platformName, COALESCE(g.nameOverride, g.igdbName, g.name) AS name
                    FROM game g JOIN platform p ON p.id = g.platformId WHERE g.id = ?
                    """, arguments: [game])
        else { throw LudeumError.gameNotFound }
        let platform: String = ROMPlatform.all[row["platformId"]]?.folderName ?? row["platformName"]
        let name: String = row["name"]
        return "\(Self.fileSafe(platform))/\(Self.fileSafe(name))"
    }

    /// `base`, or `base (2)`, `base (3)`, …: the first that's neither another Game's folder nor already on disk.
    private func freeFolder(_ db: Database, base: String, for game: GameID) throws -> String {
        for candidate in Self.candidates(base) {
            let taken = try Bool.fetchOne(
                db, sql: "SELECT EXISTS (SELECT 1 FROM game WHERE attachmentFolder = ? COLLATE NOCASE AND id != ?)",
                arguments: [candidate, game])!
            if !taken, !exists(url(candidate)) { return candidate }
        }
        fatalError("unreachable")
    }

    /// `name`, or `name (2).ext`, …: the first that's neither another of the Game's Attachments nor already in its folder.
    private func freeName(_ db: Database, for name: String, in folder: String, of game: GameID) throws -> String {
        let ext = (name as NSString).pathExtension
        for candidate in Self.candidates((name as NSString).deletingPathExtension) {
            let fileName = Self.fileName(candidate, ext)
            if try !isTaken(db, fileName, in: folder, of: game) { return fileName }
        }
        fatalError("unreachable")
    }

    private func isTaken(_ db: Database, _ fileName: String, in folder: String, of game: GameID, except: Int64? = nil) throws -> Bool {
        let inJournal = try Bool.fetchOne(
            db, sql: "SELECT EXISTS (SELECT 1 FROM attachment WHERE gameId = ? AND fileName = ? AND id IS NOT ?)",
            arguments: [game, fileName, except])!
        return inJournal || exists(url(folder).appending(path: fileName))
    }

    private static func fileName(_ name: String, _ ext: String) -> String { ext.isEmpty ? name : "\(name).\(ext)" }

    private static func candidates(_ base: String) -> some Sequence<String> {
        (1...).lazy.map { $0 == 1 ? base : "\(base) (\($0))" }
    }

    /// Whether `name` is one of `base`'s `candidates`, in any case.
    private static func isNamed(_ name: String, _ base: String) -> Bool {
        let name = name.lowercased()
        let base = base.lowercased()
        guard name != base else { return true }
        guard name.hasPrefix(base + " ("), name.hasSuffix(")") else { return false }
        return Int(name.dropFirst(base.count + 2).dropLast()).map { $0 >= 2 } ?? false
    }

    /// A name that can be a file's or folder's: `Half-Life 2: Episode One` is `Half-Life 2 - Episode One`, as a Standard
    /// name writes it, and no other `/` or `:` is kept.
    static func fileSafe(_ name: String) -> String {
        var name = name.replacingOccurrences(of: ": ", with: " - ")
        for character in ["/", ":"] { name = name.replacingOccurrences(of: character, with: "-") }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        return name.isEmpty ? "Untitled" : name
    }

    // MARK: Changing

    /// Renames the Attachment's file, keeping its extension (typed again, it isn't doubled). Refused when another of the
    /// Game's Attachments, or another file in its folder, has the name; changing only its case is fine. A missing one's
    /// file is looked for by the new name.
    public func rename(_ id: Int64, to name: String) throws {
        let attachment = try self.attachment(id)
        let ext = (attachment.fileName as NSString).pathExtension
        var name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ext.isEmpty, (name as NSString).pathExtension.caseInsensitiveCompare(ext) == .orderedSame {
            name = (name as NSString).deletingPathExtension
        }
        guard !name.isEmpty else { throw AttachmentError.nameRequired }
        let fileName = Self.fileName(Self.fileSafe(name), ext)
        guard fileName != attachment.fileName else { return }
        let folder = attachment.url.deletingLastPathComponent()
        let caseOnly = fileName.caseInsensitiveCompare(attachment.fileName) == .orderedSame
        try journal.db.write { db in
            if !caseOnly, try isTaken(db, fileName, in: try Self.folder(db, of: attachment.game)!, of: attachment.game, except: id) {
                throw AttachmentError.nameTaken
            }
            try db.execute(sql: "UPDATE attachment SET fileName = ? WHERE id = ?", arguments: [fileName, id])
            guard exists(attachment.url) else { return }
            let renamed = folder.appending(path: fileName, directoryHint: .notDirectory)
            if caseOnly {
                // A case-insensitive volume sees the new name as the file itself, so it goes by way of another name.
                let between = folder.appending(path: ".\(UUID().uuidString)", directoryHint: .notDirectory)
                try files.moveItem(at: attachment.url, to: between)
                do {
                    try files.moveItem(at: between, to: renamed)
                } catch {
                    try? files.moveItem(at: between, to: attachment.url)
                    throw error
                }
            } else {
                try files.moveItem(at: attachment.url, to: renamed)
            }
        }
    }

    public func setManual(_ id: Int64, _ manual: Bool) throws {
        try journal.db.write { db in
            try db.execute(sql: "UPDATE attachment SET manual = ? WHERE id = ?", arguments: [manual, id])
        }
    }

    // MARK: Deleting

    /// Sends the Attachment's file to the Trash, if it's there, and drops it from the journal. The Game's last takes its
    /// folder with it, once nothing else is in it.
    public func delete(_ id: Int64) throws {
        let attachment = try self.attachment(id)
        try journal.backups?.backUp(journal, operation: .beforeDelete)
        if exists(attachment.url) { try moveToTrash(attachment.url) }
        try journal.db.write { db in try db.execute(sql: "DELETE FROM attachment WHERE id = ?", arguments: [id]) }
        try removeFolderIfUnused(attachment.game)
    }

    /// Deletes the Game, as `LudeumStore.deleteGame` does, its Attachments' files going to the Trash once the backup is
    /// taken; anything else in its folder stays. Refused, with nothing sent to the Trash, while it has any Copy.
    public func deleteGame(_ game: GameID) throws {
        let attachments = try attachments(of: game)
        try journal.deleteGame(game) {
            for attachment in attachments where exists(attachment.url) { try moveToTrash(attachment.url) }
        }
        if let folder = attachments.first?.url.deletingLastPathComponent() {
            removeIfEmpty(folder)
            removeIfEmpty(folder.deletingLastPathComponent())
        }
    }

    /// A Game with no Attachments left has no folder: an empty one is removed, with its Platform's if that's empty too.
    private func removeFolderIfUnused(_ game: GameID) throws {
        let folder = try journal.db.read { db in
            try String.fetchOne(
                db,
                sql: """
                    SELECT attachmentFolder FROM game
                    WHERE id = ? AND NOT EXISTS (SELECT 1 FROM attachment WHERE gameId = game.id)
                    """, arguments: [game])
        }
        guard let folder else { return }
        removeIfEmpty(url(folder))
        guard !exists(url(folder)) else { return }
        try journal.db.write { db in
            try db.execute(sql: "UPDATE game SET attachmentFolder = NULL WHERE id = ?", arguments: [game])
        }
        removeIfEmpty(url(folder).deletingLastPathComponent())
    }

    /// Removes the folder when nothing but Finder's `.DS_Store` is in it.
    private func removeIfEmpty(_ folder: URL) {
        guard let contents = try? files.contentsOfDirectory(atPath: path(folder)), contents.allSatisfy({ $0 == ".DS_Store" })
        else { return }
        try? files.removeItem(at: folder)
    }

    // MARK: Missing files

    /// Looks for each Attachment's file, of one Game or all: one that isn't there is missing, and waits in the Review
    /// queue until it comes back, I Locate it, or I Delete it. Whether any was found missing, or found again.
    @discardableResult
    public func checkFiles(_ game: GameID? = nil) throws -> Bool {
        let rows = try journal.db.read { db in
            guard try db.tableExists("attachment") else { return [Row]() }
            return try Row.fetchAll(db, sql: "\(Self.selectWithFolder) WHERE ? IS NULL OR a.gameId = ?", arguments: [game, game])
        }
        let changed = rows.map(attachment).filter { $0.missing == exists($0.url) }
        guard !changed.isEmpty else { return false }
        try journal.db.write { db in
            for attachment in changed {
                try db.execute(sql: "UPDATE attachment SET missing = ? WHERE id = ?", arguments: [!attachment.missing, attachment.id])
            }
        }
        return true
    }

    /// Puts a missing Attachment's file back from wherever it is now, under the Attachment's own name. A moved file's
    /// original goes to the Trash once it's in. A file already back where it belongs is just found again, and the picked
    /// one is left alone.
    public func locate(_ id: Int64, file: URL, moving: Bool) throws {
        let attachment = try self.attachment(id)
        if !exists(attachment.url) {
            try checkPickable(file)
            _ = try folder(of: attachment.game)
            try files.copyItem(at: file, to: attachment.url)
            if moving { try moveToTrash(file) }
        }
        try journal.db.write { db in try db.execute(sql: "UPDATE attachment SET missing = 0 WHERE id = ?", arguments: [id]) }
    }

    // MARK: Following the Game

    /// Moves the Game's folder to fit its name and Platform, after either changes. A folder whose name still fits, with or
    /// without a suffix and in any case, stays; one that isn't there (Dropbox still syncing it) is left to a later call.
    /// Whether it moved.
    @discardableResult
    public func follow(_ game: GameID) throws -> Bool {
        try journal.db.write { db in
            guard let current = try Self.folder(db, of: game) else { return false }
            let base = try baseFolder(db, of: game)
            guard !Self.isNamed(current, base), exists(url(current)) else { return false }
            let moved = try freeFolder(db, base: base, for: game)
            try db.execute(sql: "UPDATE game SET attachmentFolder = ? WHERE id = ?", arguments: [moved, game])
            // A rename within the Data folder, so it's quick: the journal waits for it, and forgets it if it fails.
            try files.createDirectory(at: url(moved).deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.moveItem(at: url(current), to: url(moved))
            removeIfEmpty(url(current).deletingLastPathComponent())
            return true
        }
    }

    /// `follow` for every Game with a folder. Whether any moved.
    @discardableResult
    public func followAll() throws -> Bool {
        let games = try journal.db.read { db in
            guard try db.columns(in: "game").contains(where: { $0.name == "attachmentFolder" }) else { return [GameID]() }
            return try GameID.fetchAll(db, sql: "SELECT id FROM game WHERE attachmentFolder IS NOT NULL ORDER BY id")
        }
        var moved = false
        for game in games where try follow(game) { moved = true }
        return moved
    }
}

extension LudeumStore {
    /// Attachments whose files are missing, by Game then name.
    func missingAttachments() throws -> [MissingAttachment] {
        let rows = try db.read { db in
            guard try db.tableExists("attachment") else { return [Row]() }
            return try Row.fetchAll(
                db,
                sql: """
                    SELECT a.id, a.fileName, a.gameId FROM attachment a JOIN game g ON g.id = a.gameId
                    WHERE a.missing ORDER BY COALESCE(g.nameOverride, g.igdbName, g.name) COLLATE NOCASE, a.fileName COLLATE NOCASE
                    """)
        }
        return try rows.map { MissingAttachment(id: $0["id"], fileName: $0["fileName"], game: try game($0["gameId"])) }
    }
}
