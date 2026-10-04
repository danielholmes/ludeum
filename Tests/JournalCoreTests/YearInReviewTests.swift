import Foundation
import GRDB
import Testing

@testable import JournalCore

@Suite struct YearInReviewTests {
    let h = try! JournalHarness()

    func date(_ text: String) -> PartialDate { PartialDate(text)! }

    /// A moment in the journal's time zone, e.g. "2025-12-31T10:00".
    func at(_ text: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = h.timeZone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f.date(from: text)!
    }

    func play(_ game: GameID, start: String? = nil, end: String? = nil, _ outcome: Outcome? = nil) throws {
        _ = try h.journal.addPlaythrough(game, PlaythroughDraft(start: start.map(date), end: end.map(date), outcome: outcome))
    }

    func review(_ year: Int, _ filter: LibraryFilter = LibraryFilter()) throws -> YearInReview {
        try h.journal.yearInReview(year, filter)
    }

    // MARK: Playthroughs

    @Test func aPlaythroughCountsFromItsStartYearToItsEndYear() throws {
        let game = try h.addGame("Chrono Trigger")
        try play(game, start: "2023-11", end: "2025-02-03", .finished)

        #expect(try review(2023).alsoPlayed.map(\.game.id) == [game])
        #expect(try review(2024).alsoPlayed.map(\.game.id) == [game])
        #expect(try review(2025).finished.map(\.game.id) == [game])
        #expect(try review(2025).alsoPlayed.isEmpty)
        #expect(try review(2022).alsoPlayed.isEmpty)
        #expect(try review(2026).finished.isEmpty)
    }

    @Test func anInProgressPlaythroughCountsToTheCurrentYear() throws {
        let game = try h.addGame()
        let now = h.journal.calendar.component(.year, from: h.clock.now())
        try play(game, start: "\(now - 1)-06")

        #expect(try review(now).alsoPlayed.map(\.game.id) == [game])
        #expect(try review(now).isCurrentYear)
        #expect(try !review(now - 1).isCurrentYear)
        #expect(try h.journal.yearsInReview(LibraryFilter()) == [now, now - 1])
    }

    @Test func droppedIsItsOwnSection() throws {
        let game = try h.addGame()
        try play(game, start: "2024", end: "2024-05", .dropped)

        let r = try review(2024)
        #expect(r.dropped.map(\.game.id) == [game])
        #expect(r.finished.isEmpty)
        #expect(r.summary.dropped == 1)
        #expect(r.summary.started == 1)
    }

    @Test func anEndedPlaythroughWithNoEndDateCountsInItsStartYearMarked() throws {
        let game = try h.addGame()
        try play(game, start: "2022-03", .finished)

        let r = try review(2022)
        #expect(r.finished.map(\.endDateUnknown) == [true])
        #expect(try review(2023).finished.isEmpty)
        #expect(try h.journal.yearsInReview(LibraryFilter()) == [2022])
    }

    @Test func aPlaythroughWithOnlyAnEndDateCountsOnlyInItsEndYear() throws {
        let game = try h.addGame()
        try play(game, end: "2021-07", .finished)

        #expect(try review(2021).finished.map(\.game.id) == [game])
        #expect(try review(2021).summary.started == 0)
        #expect(try h.journal.yearsInReview(LibraryFilter()) == [2021])
    }

    @Test func playthroughsWithNoDatesAreCountedForTheFooter() throws {
        let game = try h.addGame()
        try play(game, .finished)
        try play(game, .dropped)
        try play(game, start: "2020", .finished)

        #expect(try review(2020).undatedPlaythroughs == 2)
        #expect(try h.journal.yearsInReview(LibraryFilter()) == [2020])
        #expect(try h.journal.library(LibraryFilter(undatedPlaythroughs: true), sort: .name, ascending: true).map(\.id) == [game])
    }

    @Test func libraryFiltersApply() throws {
        let a = try h.addGame("A")
        let b = try h.addGame("B")
        try h.journal.setChildhood(b, true)
        try play(a, start: "2024", end: "2024", .finished)
        try play(b, start: "2024", end: "2024", .finished)

        #expect(try review(2024, LibraryFilter(childhood: true)).finished.map(\.game.id) == [b])
        #expect(try h.journal.yearsInReview(LibraryFilter(childhood: true)) == [2024])
    }

    @Test func summaryCountsAndAPerPlatformBreakdown() throws {
        try h.journal.addPlatform(id: 7, name: "PlayStation")
        let snes = try h.addGame("Super Metroid")
        let psx = try h.journal.addGame(platformId: 7, name: "Vagrant Story")
        try play(snes, start: "2024-01", end: "2024-02", .finished)
        try play(snes, start: "2024-06", end: "2024-07", .finished)
        try play(psx, start: "2023-12", end: "2024-03", .dropped)

        let r = try review(2024)
        #expect(r.summary.finished == 2)
        #expect(r.summary.dropped == 1)
        #expect(r.summary.started == 2)
        #expect(r.summary.platforms.map(\.name) == ["Super Nintendo Entertainment System", "PlayStation"])
        #expect(r.summary.platforms.map(\.playthroughs) == [2, 1])
    }

    // MARK: Play time

    func rom(_ game: GameID) throws -> Int64 {
        let romCount = try h.journal.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM rom")! } + 1
        try h.journal.recordROM(
            game: game, openEmuPk: Int64(romCount), md5: "\(romCount)", fileName: "rom \(romCount).sfc", systemId: "openemu.system.snes",
            missing: false)
        return try h.journal.db.read { try Int64.fetchOne($0, sql: "SELECT id FROM rom WHERE openEmuPk = ?", arguments: [romCount])! }
    }

    func imports(_ times: [String]) throws {
        try h.journal.db.write { db in
            for (i, t) in times.enumerated() {
                try db.execute(
                    sql: "INSERT INTO import (id, startedAt, isFirst) VALUES (?, ?, ?)", arguments: [i + 1, at(t), i == 0])
            }
        }
    }

    func snapshot(_ importId: Int, _ rom: Int64, hours: Double, lastPlayed: String? = nil) throws {
        try h.journal.db.write { db in
            try db.execute(
                sql: "INSERT INTO activitySnapshot (importId, romId, playCount, lastPlayedAt, playTimeSeconds) VALUES (?, ?, 1, ?, ?)",
                arguments: [importId, rom, lastPlayed.map(at), hours * 3600])
        }
    }

    func hours(_ year: Int) throws -> [Double] { try review(year).playTime.map { $0.seconds / 3600 } }

    @Test func playTimeAddedBetweenSnapshotsInOneYearIsCreditedToIt() throws {
        let game = try h.addGame()
        let r = try rom(game)
        try imports(["2025-01-10T10:00", "2025-03-01T10:00", "2025-09-01T10:00"])
        try snapshot(1, r, hours: 100)
        try snapshot(2, r, hours: 103)
        try snapshot(3, r, hours: 110)

        #expect(try hours(2025) == [10])
        #expect(try review(2025).summary.playTimeSeconds == 10 * 3600)
        #expect(try h.journal.playTimeBeforeTracking(game) == 100 * 3600)
    }

    @Test func aROMUnchangedForSeveralImportsComparesWithItsLastSnapshot() throws {
        let game = try h.addGame()
        let r = try rom(game)
        try imports(["2024-03-01T10:00", "2024-06-01T10:00", "2024-09-01T10:00", "2025-02-01T10:00"])
        try snapshot(1, r, hours: 1)
        try snapshot(2, r, hours: 2)
        try snapshot(4, r, hours: 5, lastPlayed: "2025-01-20T20:00")

        #expect(try hours(2024) == [1])
        #expect(try hours(2025) == [3])
    }

    @Test func straddlingNewYearGoesToTheLastPlayedYear() throws {
        let game = try h.addGame()
        let a = try rom(game)
        let b = try rom(game)
        try imports(["2024-12-01T10:00", "2025-01-15T10:00"])
        try snapshot(1, a, hours: 1)
        try snapshot(1, b, hours: 1)
        try snapshot(2, a, hours: 3, lastPlayed: "2024-12-20T20:00")
        try snapshot(2, b, hours: 5, lastPlayed: "2025-01-02T20:00")

        #expect(try hours(2024) == [2])
        #expect(try hours(2025) == [4])
    }

    @Test func aROMFirstSeenAfterTheFirstImportCountsFromZero() throws {
        let game = try h.addGame()
        try imports(["2025-01-10T10:00", "2025-06-01T10:00"])
        let r = try rom(game)
        try snapshot(2, r, hours: 7)

        #expect(try hours(2025) == [7])
        #expect(try h.journal.playTimeBeforeTracking(game) == 0)
    }

    @Test func playTimeGoingDownCreditsNothingAndResetsTheBaseline() throws {
        let game = try h.addGame()
        let r = try rom(game)
        try imports(["2025-01-10T10:00", "2025-03-01T10:00", "2025-05-01T10:00"])
        try snapshot(1, r, hours: 50)
        try snapshot(2, r, hours: 2)
        try snapshot(3, r, hours: 6)

        #expect(try hours(2025) == [4])
    }

    @Test func gamesAreListedByPlayTimeMostFirstAndYearsIncludeTrackedTime() throws {
        let a = try h.addGame("A")
        let b = try h.addGame("B")
        let ra = try rom(a)
        let rb = try rom(b)
        try imports(["2023-01-10T10:00", "2023-06-01T10:00"])
        try snapshot(1, ra, hours: 1)
        try snapshot(1, rb, hours: 1)
        try snapshot(2, ra, hours: 2)
        try snapshot(2, rb, hours: 4)

        #expect(try review(2023).playTime.map(\.game.id) == [b, a])
        #expect(try h.journal.yearsInReview(LibraryFilter()) == [2023])
    }
}
