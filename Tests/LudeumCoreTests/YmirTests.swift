import CryptoKit
import Foundation
import Testing

@testable import LudeumCore

/// A Saturn disc's header, as House of the Dead (USA)'s is, with `product` and `peripherals` in place of its own.
private func saturnHeader(product: String = "MK-81802", peripherals: String = "JEG") -> Data {
    func field(_ text: String, _ count: Int) -> Data { Data(text.utf8) + Data(repeating: 0x20, count: count - text.utf8.count) }
    return field("SEGA SEGASATURN", 16) + field("SEGA ENTERPRISES", 16) + field(product, 10) + field("V1.000", 6) + field("19980311", 8)
        + field("CD-1/1", 8) + field("U", 16) + field(peripherals, 16) + field("THE HOUSE OF THE DEAD", 112) + Data(repeating: 0, count: 48)
}

/// The header in a raw 2352-byte sector of Mode `mode`.
private func rawSector(mode: UInt8 = 1, header: Data = saturnHeader()) -> Data {
    let top = Data([0] + [UInt8](repeating: 0xFF, count: 10) + [0, 0, 2, 0, mode])
    let padded = top + Data(repeating: 0, count: mode == 1 ? 0 : 8) + header
    return padded + Data(repeating: 0, count: 2352 - padded.count)
}

@Suite struct SaturnDiscTests {
    func header(_ image: Data) throws -> SaturnDisc.Header? {
        try SaturnDisc.header { range in image.subdata(in: range.clamped(to: 0..<image.count)) }
    }

    @Test func aDiscsHeaderSaysItsProductNumberAndPeripherals() throws {
        let found = try header(rawSector())
        #expect(found == SaturnDisc.Header(productNumber: "MK-81802", peripherals: "JEG"))
        #expect(found?.takesVirtuaGun == true)
    }

    @Test func itsReadFromEachFormOfFirstSector() throws {
        let expected = SaturnDisc.Header(productNumber: "MK-81802", peripherals: "JEG")
        #expect(try header(rawSector(mode: 2)) == expected)
        #expect(try header(saturnHeader() + Data(repeating: 0, count: 2048 - 256)) == expected)
    }

    @Test func aDiscWithoutAGunInItsPeripheralsDoesntTakeOne() throws {
        #expect(try header(rawSector(header: saturnHeader(peripherals: "JT")))?.takesVirtuaGun == false)
    }

    @Test func anImageThatIsntASaturnDiscHasNoHeader() throws {
        #expect(try header(Data(repeating: 0, count: 4096)) == nil)
        #expect(try header(Data(repeating: 0, count: 8)) == nil)
    }

    @Test func aDiscWithNoProductNumberHasNoSerial() throws {
        let image = rawSector(header: saturnHeader(product: ""))
        let serial = try SaturnDisc.serial { range in image.subdata(in: range.clamped(to: 0..<image.count)) }
        #expect(serial == nil)
    }
}

@Suite struct YmirSettingsTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ymir \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var settings: YmirSettings { YmirSettings(ludeum: ludeum) }
    var dataPath: String { ludeum.data.path(percentEncoded: false) }

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    func standing(_ toml: String = "", virtuaGun: Bool? = nil) -> String {
        YmirSettings.standing(in: toml, ludeum: ludeum, virtuaGun: virtuaGun)
    }

    @Test func aNewFileSaysItsVersionFirstAndKeepsWhatMattersInTheDataFolder() {
        let toml = standing()

        #expect(toml.hasPrefix("ConfigVersion = 6\n"))
        #expect(Ini.value("SaveStates", in: "General.PathOverrides", of: toml) == "'\(dataPath)Emulators/Ymir/Save States'")
        #expect(Ini.value("BackupMemory", in: "General.PathOverrides", of: toml) == "'\(dataPath)Emulators/Ymir/Backup Memory'")
        #expect(Ini.value("IPLROMImages", in: "General.PathOverrides", of: toml) == "'\(dataPath)Emulators/Ymir/BIOS'")
        #expect(Ini.value("ROMCartImages", in: "General.PathOverrides", of: toml) == "'\(dataPath)Emulators/Ymir/Cartridge ROMs'")
        #expect(Ini.value("ExportedBackups", in: "General.PathOverrides", of: toml) == "'\(dataPath)Emulators/Ymir/Exported Saves'")
        #expect(Ini.value("Screenshots", in: "General.PathOverrides", of: toml) == "'\(dataPath)Emulators/Ymir/Screenshots'")
        #expect(Ini.value("CheckForUpdates", in: "General", of: toml) == "false")
        #expect(Ini.value("InternalBackupRAMPerGame", in: "System", of: toml) == "true")
    }

    /// As Ymir writes its file: its own version, tables indented under their parents, and everything else there.
    static let written = """
        ConfigVersion = 6

        [General]
        CheckForUpdates = true
        PauseWhenUnfocused = false

            [General.PathOverrides]
            BackupMemory = ''
            SaveStates = '../somewhere'

        [Input.Port1]
        PeripheralType = 'ControlPad'

            [Input.Port1.VirtuaGun.Binds]
            Trigger = [ 'J', 'GamepadA@0' ]

        [System]
        InternalBackupRAMPerGame = false
        VideoStandard = 'NTSC'

        """

    @Test func aFileYmirWroteKeepsEverythingButLudeumsKeys() {
        let toml = standing(Self.written)

        #expect(toml.hasPrefix("ConfigVersion = 6\n\n[General]\n"))
        #expect(toml.components(separatedBy: "ConfigVersion").count == 2)
        #expect(toml.components(separatedBy: "[General.PathOverrides]").count == 2)
        #expect(Ini.value("SaveStates", in: "General.PathOverrides", of: toml) == "'\(dataPath)Emulators/Ymir/Save States'")
        #expect(Ini.value("CheckForUpdates", in: "General", of: toml) == "false")
        #expect(Ini.value("PauseWhenUnfocused", in: "General", of: toml) == "false")
        #expect(Ini.value("InternalBackupRAMPerGame", in: "System", of: toml) == "true")
        #expect(Ini.value("VideoStandard", in: "System", of: toml) == "'NTSC'")
        #expect(Ini.value("Trigger", in: "Input.Port1.VirtuaGun.Binds", of: toml) == "[ 'J', 'GamepadA@0' ]")
    }

    @Test func writingItTwiceChangesNothing() {
        #expect(standing(standing()) == standing())
        #expect(standing(standing(Self.written)) == standing(Self.written))
    }

    @Test func aDiscThatTakesTheVirtuaGunGetsItAndOneThatDoesntGoesBackToThePad() {
        let gun = standing(Self.written, virtuaGun: true)
        #expect(Ini.value("PeripheralType", in: "Input.Port1", of: gun) == "'VirtuaGun'")
        #expect(Ini.value("PeripheralType", in: "Input.Port1", of: standing(gun, virtuaGun: false)) == "'ControlPad'")
    }

    @Test func aPeripheralChosenInYmirStaysForADiscWithoutAGun() {
        let wheel = Self.written.replacing("'ControlPad'", with: "'ArcadeRacer'")
        #expect(Ini.value("PeripheralType", in: "Input.Port1", of: standing(wheel, virtuaGun: false)) == "'ArcadeRacer'")
    }

    @Test func aDiscThatCantBeReadLeavesThePortAsItIs() {
        let gun = standing(Self.written, virtuaGun: true)
        #expect(Ini.value("PeripheralType", in: "Input.Port1", of: standing(gun, virtuaGun: nil)) == "'VirtuaGun'")
    }

    @Test func aPathWithASingleQuoteIsWrittenInDoubleQuotes() {
        #expect(TOML.string("/Daniel's/Data") == #""/Daniel's/Data""#)
        #expect(TOML.string(#"/a"b\'c"#) == #""/a\"b\\'c""#)
        #expect(TOML.string("/plain path") == "'/plain path'")
    }

    @Test func writingMakesItsFoldersAndAnswersTheUpdateQuestion() throws {
        try FileManager.default.createDirectory(at: ludeum.ymirFolder, withIntermediateDirectories: true)

        try settings.writeStanding()

        for folder in YmirFolder.allCases {
            var isFolder: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: ludeum.ymir(folder).path(percentEncoded: false), isDirectory: &isFolder))
            #expect(isFolder.boolValue)
        }
        #expect(try Data(contentsOf: settings.onboardedMarker).isEmpty)
        #expect(try String(contentsOf: settings.settingsFile, encoding: .utf8).hasPrefix("ConfigVersion = 6"))
    }

    @Test func nothingsWrittenWhileTheDataFolderIsMissing() {
        let elsewhere = LudeumFolder(url: root.appending(path: "Nowhere", directoryHint: .isDirectory))

        #expect(throws: DataFolderMissing.self) { try YmirSettings(ludeum: elsewhere).writeStanding() }
        #expect(!FileManager.default.fileExists(atPath: elsewhere.ymirFolder.path(percentEncoded: false)))
    }

    @Test func aFileThatCantBeReadIsntWrittenOver() throws {
        try FileManager.default.createDirectory(at: ludeum.ymirFolder, withIntermediateDirectories: true)
        let bytes = Data([0xFF, 0xFE, 0x00, 0xC3])
        try bytes.write(to: settings.settingsFile)

        #expect(throws: (any Error).self) { try settings.writeStanding() }
        #expect(try Data(contentsOf: settings.settingsFile) == bytes)
    }

    @Test func onlyAFileOfABIOSsSizeIsABIOS() throws {
        #expect(!settings.hasBIOS)
        let folder = ludeum.ymir(.bios)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 1024).write(to: folder.appending(path: "readme.txt"))
        try Data(repeating: 0, count: 512 << 10).write(to: folder.appending(path: ".hidden.bin"))
        #expect(!settings.hasBIOS)
        try Data(repeating: 0, count: 512 << 10).write(to: folder.appending(path: "mpr-17933.bin"))
        #expect(settings.hasBIOS)
    }

    /// A ROM's subfolder with a cue sheet and its first track, whose header is `header`.
    func disc(header: Data, name: String = "House of the Dead, The (USA)") throws -> URL {
        let folder = root.appending(path: "ROMs/Saturn/\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let track = "\(name) (Track 01).bin"
        try rawSector(header: header).write(to: folder.appending(path: track))
        let cue = folder.appending(path: "\(name).cue")
        try "FILE \"\(track)\" BINARY\n  TRACK 01 MODE1/2352\n    INDEX 01 00:00:00\n".write(to: cue, atomically: true, encoding: .utf8)
        return cue
    }

    @Test func aPlayGivesItsProfileAndDiscAndSetsThePortFromTheDisc() throws {
        let cue = try disc(header: saturnHeader())

        let arguments = try settings.arguments(rom: cue)

        #expect(
            arguments == ["-p", String(ludeum.ymirFolder.path(percentEncoded: false).dropLast()), "-d", cue.path(percentEncoded: false)])
        #expect(
            Ini.value("PeripheralType", in: "Input.Port1", of: try String(contentsOf: settings.settingsFile, encoding: .utf8))
                == "'VirtuaGun'")
    }

    @Test func thePlayOfAnotherGameTakesTheGunBackOff() throws {
        _ = try settings.arguments(rom: try disc(header: saturnHeader()))

        _ = try settings.arguments(
            rom: try disc(header: saturnHeader(product: "T-14304H", peripherals: "JT"), name: "Saturn Bomberman (Europe)"))

        #expect(
            Ini.value("PeripheralType", in: "Input.Port1", of: try String(contentsOf: settings.settingsFile, encoding: .utf8))
                == "'ControlPad'")
    }

    @Test func playIsRefusedUntilYmirIsInstalledClosedAndHasABIOS() throws {
        let saturn = try FakeROMFolder(in: root.appending(path: "Fake", directoryHint: .isDirectory), platform: 32)
        try saturn.add("Game (USA)/Game (USA).cue")
        let rom = LudeumROM(
            id: 1, folderName: "Game (USA)", platformId: 32, fileName: "Game (USA)/Game (USA).cue", name: "Game (USA)", version: "",
            disc: nil,
            missing: false, archived: false)
        let play = Play(platformId: 32, platformName: "Sega Saturn", roms: [rom], settings: .init())
        let locator = ROMLocator(romFolders: [saturn.folder])

        #expect(play.prepare(locator: locator, version: .ok, app: { _ in nil }, ymir: settings).refusal == .notInstalled(.ymir))

        let executable = ludeum.ymirApp.appending(path: "Contents/MacOS/ymir-sdl3")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
        #expect(
            play.prepare(locator: locator, version: .ok, app: { _ in nil }, ymir: settings, running: { _ in true }).refusal
                == .running(.ymir))
        let bios = ludeum.ymir(.bios)
        let refusal = play.prepare(locator: locator, version: .ok, app: { _ in nil }, ymir: settings).refusal
        #expect(refusal == .noBIOS(platform: "Saturn", folder: bios.path(percentEncoded: false)))
        #expect(refusal?.message == "No Saturn BIOS. Put one in \(bios.path(percentEncoded: false)), then Play.")

        try FileManager.default.createDirectory(at: bios, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 512 << 10).write(to: bios.appending(path: "mpr-17933.bin"))
        let outcome = play.prepare(locator: locator, version: .ok, app: { _ in nil }, ymir: settings)
        #expect(outcome.refusal == nil)
        #expect(outcome.arguments?.prefix(1) == ["-p"])
        #expect(outcome.arguments?.last == saturn.url.appending(path: "Game (USA)/Game (USA).cue").path(percentEncoded: false))
    }

    @Test func aMultiDiscROMOpensDisc1sCueSheetAndAPlaylistOrABareBinIsntAROM() throws {
        let saturn = try FakeROMFolder(in: root.appending(path: "Fake", directoryHint: .isDirectory), platform: 32)
        let game = "Panzer Dragoon Saga (USA)"
        try saturn.add("\(game)/\(game) (Disc 2).cue")
        let disc1 = try saturn.add("\(game)/\(game) (Disc 1).cue")
        try saturn.add("\(game)/\(game).m3u", "\(game) (Disc 1).cue\n\(game) (Disc 2).cue\n")
        try saturn.add("Loose (USA).bin")

        let found = try saturn.folder.scan()

        #expect(found.map(\.name) == [game])
        #expect(found.first?.ready == disc1)
        #expect(found.first?.needsPlaylist == false)
    }

    @Test func aSaturnROMsSerialIsReadOffItsFirstTrack() async throws {
        let cue = try disc(header: saturnHeader())
        let folder = try #require(ROMFolder.platform(ROMPlatform.saturn, root.appending(path: "ROMs/Saturn", directoryHint: .isDirectory)))
        let rom = try #require(try folder.rom(named: "House of the Dead, The (USA)"))
        #expect(rom.ready == cue)

        #expect(await ROMSerials.read(rom, in: folder, sevenZip: nil) == ["MK-81802"])
    }
}

@Suite struct YmirInstallTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ymir install \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    /// A fake release zip, as GitHub serves it: `ymir-sdl3.app`, whose app says `appVersion`, with its controller database
    /// beside it, and the release that names it.
    func release(
        appVersion: String = YmirRelease.pinned.version, version: String = YmirRelease.pinned.version, database: String = "mappings"
    ) throws -> (
        zip: Data, release: YmirRelease
    ) {
        let staging = root.appending(path: "staging \(UUID().uuidString)", directoryHint: .isDirectory)
        let top = staging.appending(path: "zipped", directoryHint: .isDirectory)
        let app = top.appending(path: "ymir-sdl3.app", directoryHint: .isDirectory)
        let macOS = app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleShortVersionString": appVersion, "CFBundleExecutable": "ymir-sdl3"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(
            to: app.appending(path: "Contents/Info.plist"))
        let executable = macOS.appending(path: "ymir-sdl3")
        try "#!/bin/sh\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
        try database.write(to: top.appending(path: "gamecontrollerdb.txt"), atomically: true, encoding: .utf8)
        let zipFile = staging.appending(path: "ymir.zip")
        let ditto = Process()
        ditto.executableURL = URL(filePath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--norsrc", top.path(percentEncoded: false), zipFile.path(percentEncoded: false)]
        try ditto.run()
        ditto.waitUntilExit()
        let data = try Data(contentsOf: zipFile)
        return (data, YmirRelease(version: version, sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()))
    }

    func installer(_ release: YmirRelease, _ zip: Data?) -> YmirInstaller {
        YmirInstaller(ludeum: ludeum, release: release, transport: FakeReleases(zip.map { [release.url: $0] } ?? [:]))
    }

    @Test func thePinnedReleaseIsItsAppleSiliconZip() {
        #expect(
            YmirRelease.pinned.url.absoluteString
                == "https://github.com/ymir-emu/Ymir/releases/download/v0.4.1/ymir-macos-arm64-v0.4.1.zip")
    }

    @Test func installPutsTheAppInItsProfileWithTheControllerDatabaseAndStandingSettings() async throws {
        let (zip, release) = try release()
        let installer = installer(release, zip)

        try await installer.install()

        let settings = YmirSettings(ludeum: ludeum)
        #expect(settings.isInstalled)
        #expect(try String(contentsOf: ludeum.ymirFolder.appending(path: "gamecontrollerdb.txt"), encoding: .utf8) == "mappings")
        #expect(
            Ini.value("InternalBackupRAMPerGame", in: "System", of: try String(contentsOf: settings.settingsFile, encoding: .utf8))
                == "true")
        #expect(!FileManager.default.fileExists(atPath: installer.work.path(percentEncoded: false)))
    }

    @Test func aDownloadThatIsntTheReleaseIsRefused() async throws {
        let (zip, right) = try release()
        let wrong = YmirRelease(version: right.version, sha256: String(repeating: "0", count: 64))

        await #expect(throws: YmirInstallError.badChecksum(expected: wrong.sha256, found: right.sha256)) {
            try await installer(wrong, zip).install()
        }
        #expect(!FileManager.default.fileExists(atPath: ludeum.ymirApp.path(percentEncoded: false)))
    }

    @Test func aReleaseThatIsntOnGitHubIsRefused() async throws {
        await #expect(throws: YmirInstallError.notFound(version: YmirRelease.pinned.version, status: 404)) {
            try await installer(.pinned, nil).install()
        }
    }

    @Test func anAppThatIsntThePinnedVersionIsRefused() async throws {
        let (zip, release) = try release(appVersion: "0.3.3")

        await #expect(throws: YmirInstallError.wrongBuild(found: "0.3.3")) { try await installer(release, zip).install() }
        #expect(!FileManager.default.fileExists(atPath: ludeum.ymirApp.path(percentEncoded: false)))
    }

    @Test func aReinstallReplacesTheAppAndKeepsWhatYmirKeptBesideIt() async throws {
        let (first, release) = try release()
        try await installer(release, first).install()
        let settings = YmirSettings(ludeum: ludeum)
        let toml = try String(contentsOf: settings.settingsFile, encoding: .utf8)
        try Ini.setting("Mute", to: "true", in: "Audio", of: TOML.setting("Mute", to: "false", in: "Audio", of: toml))
            .write(to: settings.settingsFile, atomically: true, encoding: .utf8)
        try "mine".write(to: ludeum.ymirApp.appending(path: "Contents/mine.txt"), atomically: true, encoding: .utf8)
        let (second, again) = try self.release(database: "newer mappings")

        try await installer(again, second).install()

        #expect(settings.isInstalled)
        #expect(!FileManager.default.fileExists(atPath: ludeum.ymirApp.appending(path: "Contents/mine.txt").path(percentEncoded: false)))
        #expect(
            !FileManager.default.fileExists(atPath: ludeum.ymirFolder.appending(path: "Ymir (replaced).app").path(percentEncoded: false)))
        #expect(Ini.value("Mute", in: "Audio", of: try String(contentsOf: settings.settingsFile, encoding: .utf8)) == "true")
        #expect(try String(contentsOf: ludeum.ymirFolder.appending(path: "gamecontrollerdb.txt"), encoding: .utf8) == "newer mappings")
    }
}

@Suite struct YmirSavesTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ymir saves \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var saves: YmirSaves { YmirSaves(ludeum: ludeum) }
    var games: URL { ludeum.ymir(.backupMemory).appending(path: "games", directoryHint: .isDirectory) }

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: games, withIntermediateDirectories: true)
    }

    /// A disc's folder of Save states, its `meta.txt` as Ymir writes it, with these files in it.
    @discardableResult func folder(hash: String, product: String?, files: [String]) throws -> URL {
        let folder = ludeum.ymir(.saveStates).appending(path: hash, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let product {
            try
                "IPL ROM hash: 00\nTitle: THE HOUSE OF THE DEAD\nProduct Number: \(product)\nVersion: V1.000\nDisc: CD-1/1\nCompatible area codes: U\n"
                .write(to: folder.appending(path: "meta.txt"), atomically: true, encoding: .utf8)
        }
        for file in files { try Data().write(to: folder.appending(path: file)) }
        return folder
    }

    @Test func aGamesStatesAreFoundByItsSerialAndNumberedAsYmirShowsThem() throws {
        try folder(hash: "aa", product: "MK-81802", files: ["0.savestate", "0-1.savestate", "9.savestate", "2.savestate"])
        try folder(hash: "bb", product: "MK-81043", files: ["0.savestate"])
        try folder(hash: "cc", product: nil, files: ["0.savestate"])

        let found = saves.states(of: ["MK-81802"])

        #expect(found.map(\.title) == ["Slot 1", "Slot 3", "Slot 10"])
        #expect(found.map(\.fileName) == ["0.savestate", "2.savestate", "9.savestate"])
        #expect(found.allSatisfy { $0.serial == "MK-81802" && !$0.previous })
    }

    @Test func everyRevisionOfASerialIsFoundAndDiscsComeInOrder() throws {
        try folder(hash: "aa", product: "DISC-2", files: ["0.savestate"])
        try folder(hash: "bb", product: "DISC-1", files: ["1.savestate"])
        try folder(hash: "cc", product: "DISC-1", files: ["0.savestate"])

        let found = saves.states(of: ["DISC-1", "DISC-2"])

        #expect(found.map(\.serial) == ["DISC-1", "DISC-1", "DISC-2"])
        #expect(found.map(\.title) == ["Slot 1", "Slot 2", "Slot 1"])
    }

    @Test func noStatesWhereThereAreNone() {
        #expect(saves.states(of: ["MK-81802"]).isEmpty)
        #expect(saves.backupImages(of: ["MK-81802"]).isEmpty)
    }

    @Test func deletingAStateTrashesItAndTheOneItReplaced() throws {
        let folder = try folder(hash: "aa", product: "MK-81802", files: ["0.savestate", "0-1.savestate", "1.savestate"])
        var trashed: [String] = []

        try saves.delete(try #require(saves.states(of: ["MK-81802"]).first)) { trashed.append($0.lastPathComponent) }
        #expect(trashed == ["0.savestate", "0-1.savestate"])

        trashed = []
        try saves.delete(
            SaveState(serial: "MK-81802", slot: .numbered(2), previous: false, saved: .now, file: folder.appending(path: "1.savestate"))
        ) {
            trashed.append($0.lastPathComponent)
        }
        #expect(trashed == ["1.savestate"])
    }

    @Test func eachSlotSaysTheKeysThatLoadIt() {
        #expect(YmirSaves.loadKey(slot: 1) == "Ctrl+1")
        #expect(YmirSaves.loadKey(slot: 9) == "Ctrl+9")
        #expect(YmirSaves.loadKey(slot: 10) == "Ctrl+0")
    }

    /// An image of `size` in `blockSize` blocks, with `HOUSEOFDEAD` saved at block 2.
    func image(size: Int = 32 << 10, blockSize: Int = 64, saved: Bool = true) -> Data {
        var bytes = [UInt8](repeating: 0, count: size)
        let header = Array("BackUpRam Format".utf8)
        for i in 0..<blockSize { bytes[i] = header[i % header.count] }
        guard saved else { return Data(bytes) }
        let start = blockSize * 2
        bytes[start] = 0x80
        bytes.replaceSubrange((start + 0x04)..<(start + 0x04 + 11), with: Array("HOUSEOFDEAD".utf8))
        bytes.replaceSubrange((start + 0x10)..<(start + 0x10 + 9), with: Array("HOTD Data".utf8))
        let minutes = UInt32(Self.minutes(2023, 8, 22, 9, 58))
        bytes.replaceSubrange((start + 0x1A)..<(start + 0x1E), with: withUnsafeBytes(of: minutes.bigEndian) { Array($0) })
        bytes.replaceSubrange((start + 0x1E)..<(start + 0x22), with: withUnsafeBytes(of: UInt32(1168).bigEndian) { Array($0) })
        return Data(bytes)
    }

    static func minutes(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 1980, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        return calendar.dateComponents([.minute], from: start, to: end).minute!
    }

    @Test func anImagesSavesAreReadFromItsBlocks() throws {
        let found = try #require(SaturnBackupMemory.saves(in: image()))

        #expect(found.map(\.name) == ["HOUSEOFDEAD"])
        #expect(found.first?.comment == "HOTD Data")
        #expect(found.first?.size == 1168)
        let calendar = Calendar(identifier: .gregorian)
        #expect(found.first?.written == calendar.date(from: DateComponents(year: 2023, month: 8, day: 22, hour: 9, minute: 58)))
    }

    @Test func aFormattedImageHasNoSaves() {
        #expect(SaturnBackupMemory.saves(in: image(saved: false)) == [])
    }

    @Test func aCartridgesLargerBlocksAreRead() {
        #expect(SaturnBackupMemory.saves(in: image(size: 512 << 10, blockSize: 512))?.map(\.name) == ["HOUSEOFDEAD"])
        #expect(SaturnBackupMemory.saves(in: image(size: 4 << 20, blockSize: 1024))?.map(\.name) == ["HOUSEOFDEAD"])
    }

    @Test func anInterleavedImageIsRead() {
        let interleaved = Data(image().flatMap { [0xFF, $0] })
        #expect(SaturnBackupMemory.saves(in: interleaved)?.map(\.name) == ["HOUSEOFDEAD"])
    }

    @Test func whatIsntAnImageHasNoSavesToRead() {
        #expect(SaturnBackupMemory.saves(in: Data(repeating: 0, count: 32 << 10)) == nil)
        #expect(SaturnBackupMemory.saves(in: Data(repeating: 0, count: 100)) == nil)
    }

    @Test func aGamesImagesAreFoundByTheSerialInTheirNames() throws {
        try image().write(to: games.appending(path: "bup-int-THE HOUSE OF THE DEAD [MK-81802].bin"))
        try image(size: 4 << 20, blockSize: 1024, saved: false).write(
            to: games.appending(path: "bup-ext-32M-THE HOUSE OF THE DEAD [MK-81802].bin"))
        try image().write(to: games.appending(path: "bup-int-VIRTUA COP [MK-81043].bin"))
        try Data(repeating: 1, count: 16).write(to: games.appending(path: "bup-int-BROKEN [T-1].bin"))

        let found = saves.backupImages(of: ["MK-81802"])
        #expect(
            found.map(\.fileName) == ["bup-ext-32M-THE HOUSE OF THE DEAD [MK-81802].bin", "bup-int-THE HOUSE OF THE DEAD [MK-81802].bin"])
        #expect(found.last?.saves?.map(\.name) == ["HOUSEOFDEAD"])
        #expect(saves.backupImages(of: ["T-1"]).first?.saves == nil)
    }

    @Test func aSerialIsFoundUnderTheNameYmirGivesIt() throws {
        #expect(YmirSaves.fileName("T/1:2") == "T_1_2")
        try image().write(to: games.appending(path: "bup-int-GAME [T_1_2].bin"))
        #expect(saves.backupImages(of: ["T/1:2"]).count == 1)
    }
}
