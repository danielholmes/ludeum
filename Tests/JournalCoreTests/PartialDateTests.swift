import Testing

@testable import JournalCore

@Suite struct PartialDateTests {
    @Test func acceptsAYearAMonthOrADay() {
        #expect(PartialDate("1996")?.text == "1996")
        #expect(PartialDate("1996-03")?.text == "1996-03")
        #expect(PartialDate("1996-03-17")?.text == "1996-03-17")
    }

    @Test(arguments: ["", "96", "1996-3", "1996-13", "1996-02-30", "1996-03-17T10:00", "March 1996"])
    func refusesAnythingElse(_ text: String) {
        #expect(PartialDate(text) == nil)
    }

    @Test func aLessPreciseDateSortsBeforeTheDatesWithinIt() {
        let dates = ["2024-01-05", "2023-12", "2024", "2024-01"].compactMap(PartialDate.init)

        #expect(dates.sorted().map(\.text) == ["2023-12", "2024", "2024-01", "2024-01-05"])
    }

    @Test func containsTheMorePreciseDatesWithinIt() {
        let year = PartialDate("2024")!
        #expect(year.contains(PartialDate("2024-03")!))
        #expect(year.contains(PartialDate("2024-03-17")!))
        #expect(year.contains(year))
        #expect(!year.contains(PartialDate("2023-12")!))
        #expect(!PartialDate("2024-03")!.contains(year))
    }
}
