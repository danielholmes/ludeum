import Foundation
import GRDB
import Testing

@testable import LudeumCore

@Suite struct StorageStatsTests {
    let j: LudeumHarness
    let data: URL
    let cache: URL

    init() throws {
        j = try LudeumHarness()
        data = j.directory.appending(path: "Data", directoryHint: .isDirectory)
        cache = j.directory.appending(path: "Cache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
    }

    var folder: LudeumFolder { LudeumFolder(url: j.directory, data: data) }

    func romFolder(_ platform: Int64) throws -> FakeROMFolder {
        try FakeROMFolder(at: folder.romFolder(platform: platform)!, platform: platform)
    }

    /// A file of `bytes` bytes, so sizes are known.
    @discardableResult
    func add(_ fileName: String, bytes: Int, to rom: FakeROMFolder) throws -> URL {
        try rom.add(fileName, String(repeating: "x", count: bytes))
    }

    func measure() -> StorageStats { StorageStats.measure(folder, journal: j.journal, cache: cache) }

    @Test func aPlatformsROMsArePlayableOrArchivedWithTheirSizes() throws {
        let ps2 = try romFolder(ROMPlatform.ps2)
        try add("Sensible Soccer 2006 (Europe).iso", bytes: 10, to: ps2)
        try add("Okami (USA).7z", bytes: 5, to: ps2)

        let row = try #require(measure().platforms.first)
        #expect(row.id == ROMPlatform.ps2)
        #expect(row.total == 15)
        #expect(row.playable == .init(count: 1, bytes: 10))
        #expect(row.archived == .init(count: 1, bytes: 5))
        #expect(row.roms == 2)
    }

    @Test func filesNoROMIsMadeOfAreNotAROM() throws {
        let ps1 = try romFolder(7)
        try add("Final Fantasy VII (USA)/Final Fantasy VII (USA).m3u", bytes: 1, to: ps1)
        try add("Final Fantasy VII (USA)/Final Fantasy VII (USA) (Disc 1).chd", bytes: 20, to: ps1)
        try add("Final Fantasy VII (USA)/manual.pdf", bytes: 4, to: ps1)
        try ps1.add("Ridge Racer (USA).cue", #"FILE "Ridge Racer (USA).bin" BINARY"#)  // 35 bytes
        try add("Ridge Racer (USA).bin", bytes: 30, to: ps1)
        try add("readme.txt", bytes: 7, to: ps1)
        try write(7, to: folder.roms.appending(path: "readme.txt"))  // outside the ROM folder

        let row = try #require(measure().platforms.first)
        #expect(row.total == 97)
        #expect(row.playable == .init(count: 2, bytes: 90))
        #expect(row.notAROM == 7)
    }

    /// A ROM the journal knows, as an Import left it.
    func known(_ name: String, platform: Int64, missing: Bool) throws {
        try j.journal.addPlatform(id: platform, name: ROMPlatform.all[platform]!.name)
        try j.journal.db.write { db in
            try db.execute(
                sql: "INSERT INTO rom (platformId, folderName, fileName, missing) VALUES (?, ?, ?, ?)",
                arguments: [platform, name, "\(name).iso", missing])
        }
    }

    @Test func missingROMsAreCountedFromTheJournalButTakeNoRoom() throws {
        let ps2 = try romFolder(ROMPlatform.ps2)
        try add("Okami (USA).iso", bytes: 10, to: ps2)
        try known("Okami (USA)", platform: ROMPlatform.ps2, missing: false)
        try known("Ico (USA)", platform: ROMPlatform.ps2, missing: true)
        try known("Rez (USA)", platform: ROMPlatform.ps2, missing: true)
        try known("Kirby (USA)", platform: 33, missing: true)

        let row = try #require(measure().platforms.first)
        #expect(row.roms == 1)
        #expect(row.missing == 2)
        #expect(row.total == 10)
    }

    @Test func presentROMsNotYetCompactedAreCounted() throws {
        let snes = try romFolder(19)
        try add("Super Metroid (USA).7z", bytes: 3, to: snes)
        try add("Zelda (USA).sfc", bytes: 10, to: snes)
        let n64 = try romFolder(4)
        try add("Super Mario 64 (USA).zip", bytes: 5, to: n64)
        try add("Ocarina of Time (USA).z64", bytes: 20, to: n64)
        try add("GoldenEye 007 (USA).7z", bytes: 4, to: n64)
        try add("Wave Race 64 (USA).7z", bytes: 4, to: n64)

        let rows = measure().platforms
        let snesRow = try #require(rows.first { $0.id == 19 })
        let n64Row = try #require(rows.first { $0.id == 4 })
        #expect(snesRow.playable.count == 2)
        #expect(snesRow.notCompacted == 1)
        #expect(n64Row.archived.count == 2)
        #expect(n64Row.notCompacted == 3)
    }

    @Test func aPlatformThatCantBeCompactedHasNoneNotCompacted() throws {
        let ps2 = try romFolder(ROMPlatform.ps2)
        try add("Okami (USA).iso", bytes: 10, to: ps2)

        #expect(try #require(measure().platforms.first).notCompacted == 0)
    }

    @Test func aPlayableCopyBesideItsArchiveIsInBothFormsAndBothTakeRoom() throws {
        let ps2 = try romFolder(ROMPlatform.ps2)
        try add("Okami (USA)/Okami (USA).iso", bytes: 10, to: ps2)
        try add("Okami (USA).7z", bytes: 6, to: ps2)
        try add("Ico (USA).7z", bytes: 5, to: ps2)

        let row = try #require(measure().platforms.first)
        #expect(row.inBothForms == 1)
        #expect(row.playable == .init(count: 1, bytes: 16))
    }

    @Test func aLooseFileBesideItsCompactedCopyIsInBothForms() throws {
        let snes = try romFolder(19)
        try add("Zelda (USA).sfc", bytes: 10, to: snes)
        try add("Zelda (USA).7z", bytes: 4, to: snes)
        try add("Super Metroid (USA).7z", bytes: 3, to: snes)
        let n64 = try romFolder(4)
        try add("Super Mario 64 (USA).z64", bytes: 20, to: n64)
        try add("Super Mario 64 (USA).zip", bytes: 5, to: n64)

        let rows = measure().platforms
        let snesRow = try #require(rows.first { $0.id == 19 })
        let n64Row = try #require(rows.first { $0.id == 4 })
        #expect(snesRow.inBothForms == 1)
        #expect(n64Row.inBothForms == 1)
        #expect(n64Row.playable == .init(count: 1, bytes: 25))
        #expect(n64Row.notAROM == 0)
    }

    @Test func platformsShownAsOneShareARow() throws {
        let snes = try romFolder(19)
        try add("Zelda (USA).7z", bytes: 10, to: snes)
        let superFamicom = try romFolder(58)
        try add("Zelda no Densetsu (Japan).7z", bytes: 5, to: superFamicom)
        try add("Mother 2 (Japan).sfc", bytes: 8, to: superFamicom)
        try known("Fire Emblem (Japan)", platform: 58, missing: true)
        let gameBoy = try romFolder(33)
        try add("Tetris (World).7z", bytes: 2, to: gameBoy)

        let rows = measure().platforms
        #expect(rows.map(\.id) == [19, 33])
        #expect(rows.map(\.name) == ["Super Nintendo Entertainment System", "Game Boy"])
        #expect(rows[0].total == 23)
        #expect(rows[0].playable == .init(count: 3, bytes: 23))
        #expect(rows[0].notCompacted == 1)
        #expect(rows[0].missing == 1)
    }

    @Test func largestFirst() throws {
        try add("Tetris (World).7z", bytes: 2, to: romFolder(33))
        try add("Okami (USA).iso", bytes: 9, to: romFolder(ROMPlatform.ps2))
        try add("Sonic (USA).zip", bytes: 4, to: romFolder(29))

        #expect(measure().platforms.map(\.id) == [ROMPlatform.ps2, 29, 33])
    }

    @Test func aROMFolderThatsEmptyOrNotThereHasNoRow() throws {
        let gameBoy = try romFolder(33)
        try add(".DS_Store", bytes: 6, to: gameBoy)
        try known("Tetris (World)", platform: 33, missing: true)

        #expect(measure().platforms.isEmpty)
    }

    @Test func aROMFolderThatCantBeReadSaysSo() throws {
        let ps2 = try romFolder(ROMPlatform.ps2)
        try add("Okami (USA).iso", bytes: 10, to: ps2)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: ps2.url.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ps2.url.path(percentEncoded: false)) }

        let row = try #require(measure().platforms.first)
        #expect(row.id == ROMPlatform.ps2)
        #expect(row.unreadable)
        #expect(row.total == 0)
    }

    func write(_ bytes: Int, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try String(repeating: "x", count: bytes).write(to: file, atomically: true, encoding: .utf8)
    }

    @Test func theDataFolderJournalAndCacheAddUpToTheTotal() throws {
        let ludeum = LudeumFolder(url: j.directory.appending(path: "Ludeum", directoryHint: .isDirectory), data: data)
        try write(7, to: ludeum.url.appending(path: "journal.sqlite"))
        try write(3, to: ludeum.url.appending(path: "journal.sqlite-wal"))
        try write(100, to: ludeum.backups.appending(path: "2026-10-01 journal.sqlite"))
        try write(20, to: ludeum.batterySaveArchive.appending(path: "Mesen/Battery Saves/Zelda (USA).sav"))
        try write(40, to: cache.appending(path: "covers/1.jpg"))
        try write(9, to: cache.appending(path: "cache.sqlite"))
        try add("Okami (USA).iso", bytes: 1000, to: romFolder(ROMPlatform.ps2))

        let stats = StorageStats.measure(ludeum, journal: j.journal, cache: cache)
        #expect(stats.backups == 100)
        #expect(stats.batterySaves == 20)
        #expect(stats.dataFolder == 1120)
        #expect(stats.journal == 10)
        #expect(stats.cache == 49)
        #expect(stats.total == 1179)
    }

    @Test func aROMFolderLinkedElsewhereIsMeasuredThroughTheLink() throws {
        let elsewhere = try FakeROMFolder(in: j.directory.appending(path: "External"), platform: ROMPlatform.ps2)
        try add("Okami (USA).iso", bytes: 10, to: elsewhere)
        let link = folder.romFolder(platform: ROMPlatform.ps2)!
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: elsewhere.url)

        let row = try #require(measure().platforms.first)
        #expect(row.total == 10)
        #expect(row.playable == .init(count: 1, bytes: 10))
    }

    @Test func aFileTwoROMsAreMadeOfCountsOnce() throws {
        let ps1 = try romFolder(7)
        // 63 bytes
        try ps1.add("Parasite Eve (USA).m3u", "Parasite Eve (USA) (Disc 1).chd\nParasite Eve (USA) (Disc 2).chd")
        try add("Parasite Eve (USA) (Disc 1).chd", bytes: 20, to: ps1)
        try add("Parasite Eve (USA) (Disc 2).chd", bytes: 30, to: ps1)
        try ps1.add("Unrelated.m3u", "../readme.txt")  // 13 bytes
        try add("readme.txt", bytes: 7, to: ps1)

        let row = try #require(measure().platforms.first)
        #expect(row.total == 133)
        #expect(row.playable.bytes == 126)
        #expect(row.notAROM == 7)
    }

    @Test func hiddenFilesAreLeftOut() throws {
        let ps2 = try romFolder(ROMPlatform.ps2)
        try add("Okami (USA).iso", bytes: 10, to: ps2)
        try add(".DS_Store", bytes: 6, to: ps2)

        let row = try #require(measure().platforms.first)
        #expect(row.total == 10)
        #expect(row.notAROM == 0)
    }
}
