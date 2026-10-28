import Foundation
import GRDB
import Testing

@testable import LudeumCore

/// `ludeum-import checksums`: every present ROM's stored checksum becomes what `ROMChecksum` gives today.
@Suite(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
struct ChecksumMigrationTests {
    let h: Harness
    let j: LudeumHarness
    let gameBoy: FakeROMFolder
    let ps1: FakeROMFolder

    static let helloMD5 = "5d41402abc4b2a76b9719d911017c592"
    static let helloCRC = "3610a686"

    init() throws {
        h = try Harness()
        j = try LudeumHarness()
        gameBoy = try FakeROMFolder(in: h.directory, platform: 33)
        ps1 = try FakeROMFolder(in: h.directory, platform: ROMPlatform.ps1)
    }

    /// Puts the folders' files in the journal as an Import does, with the checksums it reads.
    func importNow() async throws {
        _ = try await Import(igdb: h.igdb, hasheous: h.hasheous, journal: j.journal, backups: nil, sevenZip: SevenZip.find())
            .run(addingEveryFileIn: [gameBoy.folder, ps1.folder])
    }

    /// As OpenEmu's migration left it: its MD5, and Regions already looked up.
    func asOpenEmuLeftIt(_ name: String, md5: String? = "0penemu", crc: String? = nil) async throws {
        try await j.journal.db.write {
            try $0.execute(
                sql: "UPDATE rom SET md5 = ?, crc = ?, regionsLookedUp = 1 WHERE folderName = ?", arguments: [md5, crc, name])
        }
    }

    func migration(onlineOnly: Set<String> = []) -> ChecksumMigration {
        ChecksumMigration(
            journal: j.journal, romFolders: [gameBoy.folder, ps1.folder], sevenZip: SevenZip.find()!, backups: nil,
            isOnDisk: { !onlineOnly.contains($0.lastPathComponent) })
    }

    struct Stored: Equatable {
        let md5: String?
        let crc: String?
        let regionsLookedUp: Bool
    }

    func stored(_ name: String) throws -> Stored? {
        try j.journal.db.read { db in
            try Row.fetchOne(db, sql: "SELECT md5, crc, regionsLookedUp FROM rom WHERE folderName = ?", arguments: [name]).map {
                Stored(md5: $0["md5"], crc: $0["crc"], regionsLookedUp: $0["regionsLookedUp"])
            }
        }
    }

    @Test func aChangedChecksumReplacesBothOldValuesAndHasRegionsGivenAgainOnlyWhereItHasNone() async throws {
        try gameBoy.add("Tetris.gb", "hello")
        try gameBoy.add("Tetris (USA).gb", "hello")
        try await gameBoy.addArchive("Dr. Mario (World)", holding: "Dr. Mario (World).gb", "hello")
        try await importNow()
        try await asOpenEmuLeftIt("Tetris")
        try await asOpenEmuLeftIt("Tetris (USA)", crc: "deadbeef")
        try await asOpenEmuLeftIt("Dr. Mario (World)")

        let plan = try await migration().plan()
        #expect(plan.lines == ["Game Boy: 3 of 3 change"])
        #expect(try stored("Tetris") == Stored(md5: "0penemu", crc: nil, regionsLookedUp: true))

        _ = try await migration().run()

        #expect(try stored("Tetris") == Stored(md5: Self.helloMD5, crc: nil, regionsLookedUp: false))
        #expect(try stored("Tetris (USA)") == Stored(md5: Self.helloMD5, crc: nil, regionsLookedUp: true))
        #expect(try stored("Dr. Mario (World)") == Stored(md5: nil, crc: Self.helloCRC, regionsLookedUp: true))
    }

    @Test func anUnchangedChecksumIsLeftAlone() async throws {
        try gameBoy.add("Tetris.gb", "hello")
        try await importNow()
        try await asOpenEmuLeftIt("Tetris", md5: Self.helloMD5)

        let plan = try await migration().run()

        #expect(plan.changes.isEmpty)
        #expect(try stored("Tetris") == Stored(md5: Self.helloMD5, crc: nil, regionsLookedUp: true))
    }

    @Test func aFormNoDATKnowsHasItsChecksumCleared() async throws {
        try ps1.add("Crash Bandicoot.chd", "compressed")
        try await importNow()
        try await asOpenEmuLeftIt("Crash Bandicoot")

        let plan = try await migration().run()

        #expect(plan.lines == ["PlayStation: 1 of 1 change (1 cleared)"])
        #expect(try stored("Crash Bandicoot") == Stored(md5: nil, crc: nil, regionsLookedUp: false))
    }

    @Test func anOnlineOnlyFileIsLeftAndListed() async throws {
        try ps1.addDisc("Crash Bandicoot", booting: "SCUS-94900", in: "Crash Bandicoot")
        try await importNow()
        try await asOpenEmuLeftIt("Crash Bandicoot")

        let plan = try await migration(onlineOnly: ["Crash Bandicoot.bin"]).run()

        #expect(plan.lines == ["PlayStation: 0 of 1 change", "left    PlayStation  Crash Bandicoot: Dropbox keeps it online only"])
        #expect(try stored("Crash Bandicoot") == Stored(md5: "0penemu", crc: nil, regionsLookedUp: true))
    }

    @Test func aDiscIsGivenItsDataTracksMD5() async throws {
        try ps1.addDisc("Crash Bandicoot", booting: "SCUS-94900", in: "Crash Bandicoot")
        try await importNow()
        let expected = try stored("Crash Bandicoot")?.md5
        try await asOpenEmuLeftIt("Crash Bandicoot")

        _ = try await migration().run()

        #expect(try stored("Crash Bandicoot")?.md5 == expected)
        #expect(expected != nil)
    }
}
