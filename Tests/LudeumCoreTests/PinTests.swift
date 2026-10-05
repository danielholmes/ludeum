import Testing

@testable import LudeumCore

@Suite struct PinTests {
    @Test func pinsAreKeptByNameOnceEachAndCanBeUnpinned() throws {
        let j = try LudeumHarness()
        let looney = Pin(kind: .franchise, name: "Looney Tunes")
        let castlevania = Pin(kind: .series, name: "Castlevania")

        try j.journal.pin(looney)
        try j.journal.pin(castlevania)
        try j.journal.pin(looney)
        #expect(try j.journal.pins() == [castlevania, looney])

        try j.journal.unpin(looney)
        try j.reopen()
        #expect(try j.journal.pins() == [castlevania])
        #expect(castlevania.filter == LibraryFilter(series: "Castlevania"))

        let horror = Pin(kind: .theme, name: "Horror")
        try j.journal.pin(horror)
        #expect(try j.journal.pins().contains(horror))
        #expect(horror.filter == LibraryFilter(theme: "Horror"))
        let capcom = Pin(kind: .company, name: "Capcom")
        try j.journal.pin(capcom)
        #expect(try j.journal.pins().contains(capcom))
    }
}
