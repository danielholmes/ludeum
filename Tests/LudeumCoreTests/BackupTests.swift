import Foundation
import GRDB
import Testing

@testable import LudeumCore

@Suite struct BackupNameTests {
    let sydney = TimeZone(identifier: "Australia/Sydney")!

    @Test func namesAreTheLocalDateAndTimeThenTheOperation() {
        let date = ISO8601DateFormatter().date(from: "2026-10-02T03:30:00Z")!  // 13:30 in Sydney
        #expect(BackupName.make(date: date, operation: .beforeSync, timeZone: sydney) == "2026-10-02T1330-before-sync.sqlite")
        #expect(BackupName.make(date: date, operation: .daily, timeZone: sydney) == "2026-10-02T1330-daily.sqlite")
    }

    @Test func namesParseBack() {
        let parsed = BackupName.parse("2026-10-02T1330-before-delete.sqlite", timeZone: sydney)
        #expect(parsed?.operation == .beforeDelete)
        #expect(parsed?.date == ISO8601DateFormatter().date(from: "2026-10-02T03:30:00Z"))
    }

    @Test func otherFilesAreNotBackups() {
        #expect(BackupName.parse(".2026-10-02T1330-daily.sqlite.tmp", timeZone: sydney) == nil)
        #expect(BackupName.parse("notes.txt", timeZone: sydney) == nil)
        #expect(BackupName.parse("2026-10-02T1330-unknown.sqlite", timeZone: sydney) == nil)
    }
}

@Suite struct BackupPruningTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Sydney")!
        return c
    }
    let now = ISO8601DateFormatter().date(from: "2026-10-02T02:00:00Z")!  // noon in Sydney

    func backup(daysAgo: Double, hours: Double = 0) -> Backup {
        let date = now.addingTimeInterval(-(daysAgo * 86_400 + hours * 3_600))
        return Backup(url: URL(filePath: "/b/\(daysAgo)-\(hours)"), date: date, operation: .daily)
    }

    func kept(_ backups: [Backup]) -> Set<URL> {
        Set(backups.map(\.url)).subtracting(backupsToPrune(backups, now: now, calendar: calendar).map(\.url))
    }

    @Test func everyBackupFromTheLastSevenDaysIsKept() {
        let recent = [backup(daysAgo: 0), backup(daysAgo: 0, hours: 1), backup(daysAgo: 6), backup(daysAgo: 6, hours: 2)]
        #expect(kept(recent) == Set(recent.map(\.url)))
    }

    @Test func thenTheNewestOfEachDayForThirtyDays() {
        let newer = backup(daysAgo: 10)
        let older = backup(daysAgo: 10, hours: 2)
        let otherDay = backup(daysAgo: 20)
        #expect(kept([newer, older, otherDay]) == [newer.url, otherDay.url])
    }

    @Test func thenTheNewestOfEachMonthForever() {
        // 2026-06-02 noon Sydney is 122 days earlier; 2026-06-20 is in the same month.
        let june2 = backup(daysAgo: 122)
        let june20 = backup(daysAgo: 104)
        let may = backup(daysAgo: 150)
        let longAgo = backup(daysAgo: 2_000)
        #expect(kept([june2, june20, may, longAgo]) == [june20.url, may.url, longAgo.url])
    }

    @Test func aMonthsNewestIsChosenOnlyAmongBackupsOlderThanThirtyDays() {
        // A September backup inside the daily tier doesn't stand in for an older September one.
        let sept25 = backup(daysAgo: 7, hours: 1)
        let sept1 = backup(daysAgo: 31)
        let sept1Earlier = backup(daysAgo: 31, hours: 3)
        #expect(kept([sept25, sept1, sept1Earlier]) == [sept25.url, sept1.url])
    }
}

@Suite struct BackupsTests {
    let h: LudeumHarness
    let root: URL
    let dropbox: URL
    let fallback: URL

    init() throws {
        h = try LudeumHarness()
        root = h.directory.appending(path: "backups root", directoryHint: .isDirectory)
        dropbox = root.appending(path: "Dropbox/Ludeum Backups", directoryHint: .isDirectory)
        fallback = root.appending(path: "Backups", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dropbox, withIntermediateDirectories: true)
    }

    func backups() -> Backups { Backups(folder: dropbox, fallback: fallback, clock: h.clock, timeZone: h.timeZone) }

    /// The harness clock starts at 2027-01-15 19:00 in Sydney.
    let stamp = "2027-01-15T1900"

    func names(_ journal: LudeumStore) throws -> [String] {
        try journal.db.read { try String.fetchAll($0, sql: "SELECT name FROM game ORDER BY id") }
    }

    func files(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
    }

    @Test func aBackupIsACompleteCopyNamedByDateAndOperation() throws {
        _ = try h.addGame("Super Metroid")

        let backup = try backups().backUp(h.journal, operation: .beforeSync)

        #expect(try files(dropbox) == ["\(stamp)-before-sync.sqlite"])
        let copy = try LudeumStore(directory: h.directory.appending(path: "copy"), clock: h.clock, timeZone: h.timeZone)
        try Backups.copy(from: backup.url, into: copy)
        #expect(try names(copy) == ["Super Metroid"])
    }

    @Test func twoBackupsInOneMinuteDontOverwriteEachOther() throws {
        _ = try backups().backUp(h.journal, operation: .daily)
        _ = try backups().backUp(h.journal, operation: .daily)

        #expect(try files(dropbox) == ["\(stamp)-daily-2.sqlite", "\(stamp)-daily.sqlite"])
        #expect(try backups().all().count == 2)
    }

    @Test func withoutTheFolderBackupsGoToTheFallbackWithAWarning() throws {
        try FileManager.default.removeItem(at: dropbox)

        _ = try backups().backUp(h.journal, operation: .manual)

        #expect(backups().isUsingFallback)
        #expect(try files(fallback) == ["\(stamp)-manual.sqlite"])
    }

    @Test func aDailyBackupIsDueOncePerLocalDay() throws {
        #expect(try backups().backUpIfDailyDue(h.journal) != nil)
        h.clock.advance(seconds: 3_600)
        #expect(try backups().backUpIfDailyDue(h.journal) == nil)
        h.clock.advance(days: 1)
        #expect(try backups().backUpIfDailyDue(h.journal) != nil)
    }

    @Test func backingUpPrunesOldBackups() throws {
        _ = try backups().backUp(h.journal, operation: .daily)
        h.clock.advance(seconds: 3_600)
        _ = try backups().backUp(h.journal, operation: .daily)
        h.clock.advance(days: 40)

        _ = try backups().backUp(h.journal, operation: .daily)

        #expect(try backups().all().count == 2)  // today's, and the newer of the two from 40 days ago
    }

    @Test func theBeforeMigrationBackupAndWhatsBesideItAreNeverPruned() throws {
        let migration = try backups().backUp(h.journal, operation: .beforeMigration)
        let stem = migration.url.deletingPathExtension()
        try FileManager.default.createDirectory(at: stem.appendingPathExtension("openemu-battery-saves"), withIntermediateDirectories: true)
        try Data("a\tb\n".utf8).write(to: stem.appendingPathExtension("moves.log"))
        h.clock.advance(seconds: 3_600)
        _ = try backups().backUp(h.journal, operation: .daily)
        h.clock.advance(days: 400)

        _ = try backups().backUp(h.journal, operation: .daily)

        #expect(try backups().all().map(\.operation).contains(.beforeMigration))
        #expect(
            try files(dropbox).filter { $0.hasPrefix("\(stamp)-before-migration") } == [
                "\(stamp)-before-migration.moves.log", "\(stamp)-before-migration.openemu-battery-saves",
                "\(stamp)-before-migration.sqlite",
            ])
    }

    @Test func deletingAGameBacksUpFirst() throws {
        let journal = try LudeumStore(directory: h.directory, clock: h.clock, timeZone: h.timeZone, backups: backups())
        try journal.addPlatform(id: 19, name: "SNES")
        let game = try journal.addGame(platformId: 19, name: "Super Metroid")

        try journal.deleteGame(game)

        let backup = try #require(try backups().all().first)
        #expect(backup.operation == .beforeDelete)
        let copy = try LudeumStore(directory: h.directory.appending(path: "copy"), clock: h.clock, timeZone: h.timeZone)
        try Backups.copy(from: backup.url, into: copy)
        #expect(try names(copy).count == 1)
    }

    @Test func aRefusedDeletionLeavesNoBackup() throws {
        let journal = try LudeumStore(directory: h.directory, clock: h.clock, timeZone: h.timeZone, backups: backups())
        try journal.addPlatform(id: 19, name: "SNES")
        let game = try journal.addGame(platformId: 19, name: "Super Metroid")
        try journal.recordROM(game: game, fileName: "sm.sfc", missing: false)

        #expect(throws: LudeumError.gameHasPresentROMs) { try journal.deleteGame(game) }
        #expect(try backups().all().isEmpty)
    }

    @Test func restoreListsBackupsInTheFallbackToo() throws {
        try FileManager.default.removeItem(at: dropbox)
        _ = try backups().backUp(h.journal, operation: .manual)
        try FileManager.default.createDirectory(at: dropbox, withIntermediateDirectories: true)
        h.clock.advance(seconds: 60)
        _ = try backups().backUp(h.journal, operation: .manual)

        #expect(try backups().all().count == 2)
    }

    @Test func restoreBacksUpFirstThenReplacesTheJournal() throws {
        _ = try h.addGame("Super Metroid")
        let before = try backups().backUp(h.journal, operation: .manual)
        _ = try h.addGame("Earthbound")
        h.clock.advance(seconds: 60)

        try backups().restore(before, into: h.journal)

        #expect(try names(h.journal) == ["Super Metroid"])
        let safety = try #require(try backups().all().first { $0.operation == .beforeRestore })
        let copy = try LudeumStore(directory: h.directory.appending(path: "copy"), clock: h.clock, timeZone: h.timeZone)
        try Backups.copy(from: safety.url, into: copy)
        #expect(Set(try names(copy)) == ["Super Metroid", "Earthbound"])
    }
}

/// Opening a journal whose schema is behind this build's.
@Suite struct SchemaMigrationBackupTests {
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "schema backup \(UUID().uuidString)", directoryHint: .isDirectory)
    var journalFolder: URL { directory.appending(path: "journal", directoryHint: .isDirectory) }
    var backupFolder: URL { directory.appending(path: "Backups", directoryHint: .isDirectory) }
    let clock = TestClock()

    func backups() -> Backups { Backups(folder: backupFolder, fallback: backupFolder, clock: clock) }

    func open() throws -> LudeumStore { try LudeumStore(directory: journalFolder, clock: clock, backups: backups()) }

    /// A journal left at `migration` with one Game on it.
    func oldJournal(at migration: String) throws {
        try FileManager.default.createDirectory(at: journalFolder, withIntermediateDirectories: true)
        let db = try DatabaseQueue(path: journalFolder.appending(path: "journal.sqlite").path(percentEncoded: false))
        try LudeumSchema.migrator.migrate(db, upTo: migration)
        try db.write {
            try $0.execute(
                sql: "INSERT INTO platform VALUES (19, 'SNES'); INSERT INTO game (platformId, name) VALUES (19, 'Super Metroid')")
        }
        try db.close()
    }

    @Test func anOldJournalIsBackedUpAsItWasBeforeItsMigrationsRun() throws {
        try oldJournal(at: "v13 players")

        _ = try open()

        let backup = try #require(try backups().all().first)
        #expect(try backups().all().map(\.operation) == [.beforeSchemaMigration])
        let copy = try DatabaseQueue(path: backup.url.path(percentEncoded: false))
        #expect(try copy.read { try LudeumSchema.migrator.appliedIdentifiers($0).contains("v14 roms keyed by platform") } == false)
        #expect(try copy.read { try String.fetchOne($0, sql: "SELECT name FROM game") } == "Super Metroid")
    }

    @Test func aNewJournalOrOneAlreadyUpToDateIsntBackedUp() throws {
        _ = try open()
        _ = try open()

        #expect(try backups().all().isEmpty)
    }

    @Test func oneWaitingForMigrateOpenEmuIsntBackedUpAgainEachLaunch() throws {
        try oldJournal(at: LudeumSchema.lastWithOpenEmu)
        let db = try DatabaseQueue(path: journalFolder.appending(path: "journal.sqlite").path(percentEncoded: false))
        try db.write {
            try $0.execute(sql: "INSERT INTO rom (openEmuPk, md5, fileName, platformId) VALUES (10, 'aa', 'Super Metroid.sfc', 19)")
        }
        try db.close()

        _ = try open()

        #expect(try backups().all().isEmpty)
    }
}
