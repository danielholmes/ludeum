import Foundation
import GRDB

/// What triggered a backup. Its raw value is the end of the backup's file name.
public enum BackupOperation: String, Sendable, CaseIterable {
    case daily
    case manual
    case beforeImport = "before-import"
    case beforeSync = "before-sync"
    case beforeDelete = "before-delete"
    case beforeRestore = "before-restore"
}

/// One backup file of the journal database.
public struct Backup: Sendable, Hashable {
    public let url: URL
    public let date: Date
    public let operation: BackupOperation
}

/// Backup file names: the local date and time to the minute, then the operation,
/// e.g. `2026-10-02T1430-before-sync.sqlite`. A second backup in the same minute gets `-2`.
public enum BackupName {
    public static func make(date: Date, operation: BackupOperation, timeZone: TimeZone, copy: Int = 1) -> String {
        "\(formatter(timeZone).string(from: date))-\(operation.rawValue)\(copy > 1 ? "-\(copy)" : "").sqlite"
    }

    /// Nil for anything that isn't a backup, including half-written temporary files.
    public static func parse(_ name: String, timeZone: TimeZone) -> (date: Date, operation: BackupOperation)? {
        guard let m = name.wholeMatch(of: /(\d{4}-\d{2}-\d{2}T\d{4})-([a-z-]+?)(-\d+)?\.sqlite/),
            let date = formatter(timeZone).date(from: String(m.1)), let operation = BackupOperation(rawValue: String(m.2))
        else { return nil }
        return (date, operation)
    }

    private static func formatter(_ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd'T'HHmm"
        return f
    }
}

/// The backups to delete: every backup from the last 7 days is kept, then the newest of each
/// day up to 30 days old, then the newest of each month forever.
public func backupsToPrune(_ backups: [Backup], now: Date, calendar: Calendar) -> [Backup] {
    var keep = Set<URL>()
    var newestPerPeriod: [String: Backup] = [:]
    for backup in backups {
        let age = now.timeIntervalSince(backup.date)
        if age < 7 * 86_400 {
            keep.insert(backup.url)
            continue
        }
        let c = calendar.dateComponents([.year, .month, .day], from: backup.date)
        let period = age < 30 * 86_400 ? "day \(c.year!)-\(c.month!)-\(c.day!)" : "month \(c.year!)-\(c.month!)"
        if let current = newestPerPeriod[period], current.date >= backup.date { continue }
        newestPerPeriod[period] = backup
    }
    keep.formUnion(newestPerPeriod.values.map(\.url))
    return backups.filter { !keep.contains($0.url) }
}

/// Journal backups, taken with SQLite's backup API into the backup folder (normally in Dropbox),
/// or into a local fallback folder when that isn't there. The cache is never backed up.
public struct Backups: Sendable {
    /// Read on each use, so changing it in Settings takes effect straight away.
    let currentFolder: @Sendable () -> URL
    public let fallback: URL
    public var folder: URL { currentFolder() }
    let clock: TimeSource
    let calendar: Calendar

    public init(folder: URL, fallback: URL, clock: TimeSource = SystemTimeSource(), timeZone: TimeZone = .current) {
        self.init(folder: { folder }, fallback: fallback, clock: clock, timeZone: timeZone)
    }

    public init(
        folder: @escaping @Sendable () -> URL, fallback: URL, clock: TimeSource = SystemTimeSource(), timeZone: TimeZone = .current
    ) {
        currentFolder = folder
        self.fallback = fallback
        self.clock = clock
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// The backup folder isn't there, so backups go to the fallback: the app shows a warning.
    public var isUsingFallback: Bool {
        var isDirectory: ObjCBool = false
        return !FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isDirectory)
            || !isDirectory.boolValue
    }

    var destination: URL { isUsingFallback ? fallback : folder }

    /// Every backup, in the backup folder and the fallback, newest first. Restore lists them all.
    public func all() throws -> [Backup] {
        let folders = Set([folder, fallback].map(\.standardizedFileURL))
        return try folders.flatMap(backups(in:)).sorted { ($0.date, $0.url.lastPathComponent) > ($1.date, $1.url.lastPathComponent) }
    }

    private func backups(in dir: URL) throws -> [Backup] {
        guard FileManager.default.fileExists(atPath: dir.path(percentEncoded: false)) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).compactMap { url in
            BackupName.parse(url.lastPathComponent, timeZone: calendar.timeZone).map {
                Backup(url: url, date: $0.date, operation: $0.operation)
            }
        }
    }

    /// Writes a backup under a temporary name, renames it so Dropbox never syncs a half-written
    /// file, then prunes older backups.
    @discardableResult
    public func backUp(_ journal: LudeumStore, operation: BackupOperation) throws -> Backup {
        let dir = destination
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = clock.now()
        var copy = 1
        var url: URL
        repeat {
            url = dir.appending(path: BackupName.make(date: now, operation: operation, timeZone: calendar.timeZone, copy: copy))
            copy += 1
        } while FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        let temporary = dir.appending(path: ".\(url.lastPathComponent).tmp")
        try? FileManager.default.removeItem(at: temporary)
        do {
            let target = try DatabaseQueue(path: temporary.path(percentEncoded: false))
            try journal.db.backup(to: target)
            try target.close()
            try FileManager.default.moveItem(at: temporary, to: url)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        // Best effort: a backup Dropbox is holding on to mustn't fail the backup or the step it guards.
        for old in backupsToPrune((try? backups(in: dir)) ?? [], now: now, calendar: calendar) {
            try? FileManager.default.removeItem(at: old.url)
        }
        return Backup(url: url, date: now, operation: operation)
    }

    /// The daily backup, unless one (of any kind) was already taken today. Nil if none was due.
    @discardableResult
    public func backUpIfDailyDue(_ journal: LudeumStore) throws -> Backup? {
        let now = clock.now()
        if try all().contains(where: { calendar.isDate($0.date, inSameDayAs: now) }) { return nil }
        return try backUp(journal, operation: .daily)
    }

    /// Backs up the current journal, then replaces its contents with the backup's. The app
    /// relaunches afterwards so nothing holds on to the old state.
    public func restore(_ backup: Backup, into journal: LudeumStore) throws {
        try backUp(journal, operation: .beforeRestore)
        try Self.copy(from: backup.url, into: journal)
    }

    /// Replaces a journal's contents with a backup file's, through SQLite's backup API.
    static func copy(from file: URL, into journal: LudeumStore) throws {
        var config = Configuration()
        config.readonly = true
        let source = try DatabaseQueue(path: file.path(percentEncoded: false), configuration: config)
        try source.backup(to: journal.db)
    }
}
