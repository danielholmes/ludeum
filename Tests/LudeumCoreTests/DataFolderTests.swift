import Foundation
import Testing

@testable import LudeumCore

/// The Ludeum folder and its Data folder (ADR 0010), always under a temporary root: never the real ~/Library or Dropbox.
@Suite struct DataFolderTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ludeum folder \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var data: URL { root.appending(path: "Ludeum/Data", directoryHint: .isDirectory) }

    init() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "Ludeum"), withIntermediateDirectories: true)
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    @Test func aMissingDataFolderIsRefusedWithHowToFixItAndIsNeverCreated() throws {
        let error = #expect(throws: DataFolderMissing.self) { try ludeum.checkData() }

        #expect(error?.remedy.contains(data.path(percentEncoded: false)) == true)
        #expect(error?.remedy.contains("Create") == true)
        #expect(error?.remedy.contains("ln -s ~/Dropbox/games/Ludeum") == true)
        #expect(!exists(data))
    }

    @Test func aDataFolderLinkedToSomewhereGoneIsRefusedNamingWhereItLinks() throws {
        let gone = root.appending(path: "Dropbox/games/Ludeum", directoryHint: .notDirectory)
        try FileManager.default.createSymbolicLink(at: data, withDestinationURL: gone)

        let error = #expect(throws: DataFolderMissing.self) { try ludeum.checkData() }

        #expect(error?.remedy.contains("links to \(gone.path(percentEncoded: false))") == true)
        #expect(!exists(gone))
    }

    @Test func aFileWhereTheDataFolderShouldBeIsRefused() throws {
        try Data().write(to: root.appending(path: "Ludeum/Data", directoryHint: .notDirectory))

        #expect(throws: DataFolderMissing.self) { try ludeum.checkData() }
    }

    @Test func aFoundDataFolderGetsItsROMsAndBackupsFoldersAndResolvesThroughItsLink() throws {
        let dropbox = root.appending(path: "Dropbox/games/Ludeum", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dropbox, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: data, withDestinationURL: dropbox)

        let resolved = try ludeum.checkData()

        #expect(resolved.standardizedFileURL.resolvingSymlinksInPath() == dropbox.standardizedFileURL.resolvingSymlinksInPath())
        #expect(exists(dropbox.appending(path: "ROMs")))
        #expect(exists(dropbox.appending(path: "Backups")))
        #expect(!exists(dropbox.appending(path: "ROMs/SNES")))
    }

    @Test func everyPlatformsROMFolderIsNamedForItUnderROMsPS2Included() {
        let folders = ludeum.romFolders
        let roms = data.appending(path: "ROMs").path(percentEncoded: false)

        #expect(folders.count == 20)
        #expect(folders.first { $0.platformId == 22 }?.url.path(percentEncoded: false) == "\(roms)/Game Boy Color/")
        #expect(folders.first { $0.platformId == 99 }?.url.path(percentEncoded: false) == "\(roms)/Famicom/")
        #expect(folders.first { $0.platformId == ROMPlatform.ps2 }?.url.path(percentEncoded: false) == "\(roms)/PS2/")
        #expect(ludeum.romFolder(platform: 6) == nil)
    }

    @Test func aDataFolderGivenForOneRunHoldsItsROMsBackupsAndArchive() {
        let rehearsal = root.appending(path: "rehearsal", directoryHint: .isDirectory)
        let folder = LudeumFolder(url: ludeum.url, data: rehearsal)

        #expect(folder.romFolder(platform: 19)?.path(percentEncoded: false) == rehearsal.path(percentEncoded: false) + "ROMs/SNES/")
        #expect(folder.backups.path(percentEncoded: false) == rehearsal.path(percentEncoded: false) + "Backups/")
        #expect(
            folder.batterySaveArchive.path(percentEncoded: false) == rehearsal.path(percentEncoded: false)
                + "OpenEmu Battery Saves archive/")
    }

    @Test func theStandardFoldersAreFixed() {
        #expect(LudeumFolder.standard.url.path(percentEncoded: false).hasSuffix("/Library/Application Support/Ludeum/"))
        #expect(LudeumFolder.standard.data.path(percentEncoded: false).hasSuffix("/Library/Application Support/Ludeum/Data/"))
        #expect(CacheStore.defaultDirectory.path(percentEncoded: false).hasSuffix("/Library/Caches/Ludeum/"))
    }
}
