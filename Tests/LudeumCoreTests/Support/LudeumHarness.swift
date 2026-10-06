import Foundation

@testable import LudeumCore

/// A real on-disk journal with a clock the test controls, in Sydney time
/// so "today" differs from the UTC date for part of each day.
/// Calling `reopen()` simulates quitting and relaunching the app.
final class LudeumHarness {
    let directory: URL
    let clock = TestClock()
    let timeZone = TimeZone(identifier: "Australia/Sydney")!
    private(set) var journal: LudeumStore

    /// `beforeOpenEmuMigration` opens it as a journal that still has OpenEmu ROMs, waiting for `migrate-openemu`.
    init(beforeOpenEmuMigration: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "journal tests (with spaces) \(UUID().uuidString)", directoryHint: .isDirectory)
        journal = try LudeumStore(directory: directory, clock: clock, timeZone: timeZone, beforeOpenEmuMigration: beforeOpenEmuMigration)
    }

    func reopen() throws {
        journal = try LudeumStore(directory: directory, clock: clock, timeZone: timeZone)
    }

    /// A Game on the Super Nintendo, made by hand.
    func addGame(_ name: String = "Super Metroid") throws -> GameID {
        try journal.addPlatform(id: 19, name: "Super Nintendo Entertainment System")
        return try journal.addGame(platformId: 19, name: name)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}
