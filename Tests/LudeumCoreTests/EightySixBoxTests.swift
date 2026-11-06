import CryptoKit
import Foundation
import Testing

@testable import LudeumCore

/// A VHD footer of this kind and geometry, written twice as a dynamic VHD has it: enough for what Ludeum reads of one.
private func vhd(type: UInt8, cylinders: Int = 65016, heads: UInt8 = 16, sectors: UInt8 = 63) -> Data {
    var footer = [UInt8](repeating: 0, count: 512)
    footer.replaceSubrange(0..<8, with: Array("conectix".utf8))
    footer[56] = UInt8(cylinders >> 8)
    footer[57] = UInt8(cylinders & 0xFF)
    footer[58] = heads
    footer[59] = sectors
    footer[63] = type
    return Data(footer + footer)
}

private func put(_ data: Data, at file: URL) throws {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: file)
}

/// Ludeum's Windows platform and how its ROMs read (ADR 0041).
@Suite struct WindowsROMTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "windows rom \(UUID().uuidString)", directoryHint: .isDirectory)

    @Test func windowsIsPlayedIn86Box() {
        #expect(Emulator.of(platformId: ROMPlatform.windows) == .eightySixBox)
        #expect(Emulator.eightySixBox.isLudeums)
        // DOS is DOSBox's, in time (#53).
        #expect(Emulator.of(platformId: 13) == nil)
    }

    @Test func aDiscInItsSubfolderIsAROM() throws {
        let windows = try FakeROMFolder(in: directory, platform: ROMPlatform.windows)
        let image = try windows.add("Red Alert 2 (USA)/Red Alert 2.iso")

        let rom = try #require(try windows.folder.scan().first)
        #expect(rom.name == "Red Alert 2 (USA)")
        #expect(rom.ready == image)
    }

    @Test func aCueSheetIsOpenedRatherThanItsTracks() throws {
        let windows = try FakeROMFolder(in: directory, platform: ROMPlatform.windows)
        let cue = try windows.add("Age of Empires (USA)/AOE.cue")
        try windows.add("Age of Empires (USA)/AOE.bin")

        #expect(try windows.folder.scan().first?.ready == cue)
    }

    @Test func aLoneCueSheetIsntPresumedToBeWindowss() async throws {
        let picked = directory.appending(path: "Picked", directoryHint: .isDirectory)
        try put(Data(), at: picked.appending(path: "Sonic CD (USA).cue"))
        let source = ROMSource([picked.appending(path: "Sonic CD (USA).cue")])

        let platforms = try await source.platforms(sevenZip: nil)

        #expect(platforms.contains(ROMPlatform.windows))
        #expect(source.likeliestPlatform(of: platforms) != ROMPlatform.windows)
    }

    @Test func noChecksumIsTakenAsNoDATCoversThem() async throws {
        let windows = try FakeROMFolder(in: directory, platform: ROMPlatform.windows)
        try windows.add("Age of Empires (USA)/AOE.iso")
        let rom = try #require(try windows.folder.scan().first)

        let reading = await ROMChecksum.read(rom, platformId: ROMPlatform.windows, sevenZip: nil, isOnDisk: { _ in true })

        #expect(reading == .noDump)
    }
}

/// The one machine 86Box is given (ADR 0041).
@Suite struct EightySixBoxConfigurationTests {
    let disk = URL(filePath: "/Data/Emulators/86Box/Game Disks/Age of Empires (USA).vhd")
    let base = URL(filePath: "/Data/Emulators/86Box/Game Disks/ludeum-win98se-base.vhd")
    let disc = URL(filePath: "/Data/ROMs/Windows/Age of Empires (USA)/AOE.cue")

    func lines(
        parent: URL? = nil, others: [URL] = [], cpu: EightySixBoxCPU = .of(setting: nil),
        window: String = EightySixBoxSettings.defaultWindow
    ) -> [String] {
        EightySixBoxSettings.configuration(disk: disk, parent: parent, disc: disc, otherDiscs: others, cpu: cpu, window: window)
            .components(separatedBy: "\n")
    }

    @Test func itIsTheMachineTheBaseWasPreparedOn() {
        let config = lines()

        for line in [
            "machine = p3bf", "cpu_family = pentium2_deschutes", "mem_size = 262144", "gfxcard = voodoo3_3500_agp",
            "bios = voodoo3_3500_agp_ntsc", "render_threads = 4", "sndcard = sb16_pnp", "cdrom_01_type = 86dvd",
            "hdd_01_parameters = 63, 16, 65016, 0, ide",
        ] {
            #expect(config.contains(line), "\(line)")
        }
    }

    @Test func aGameDiskYetToBeMadeNamesItsParent() {
        let config = lines(parent: base)

        #expect(config.contains("hdd_01_fn = /Data/Emulators/86Box/Game Disks/Age of Empires (USA).vhd"))
        #expect(config.contains("hdd_01_vhd_parent = /Data/Emulators/86Box/Game Disks/ludeum-win98se-base.vhd"))
    }

    @Test func oneAlreadyMadeNamesNoParent() {
        #expect(!lines().contains { $0.hasPrefix("hdd_01_vhd_parent") })
    }

    @Test func itsFirstDiscIsInTheDriveWithTheOthersOffered() {
        let second = URL(filePath: "/Data/ROMs/Windows/Age of Empires (USA)/AOE 2.cue")
        let config = lines(others: [second])

        #expect(config.contains("cdrom_01_image_path = /Data/ROMs/Windows/Age of Empires (USA)/AOE.cue"))
        #expect(config.contains("cdrom_01_image_history_01 = /Data/ROMs/Windows/Age of Empires (USA)/AOE 2.cue"))
    }

    @Test func aPictureFillsTheScreenAt4To3() {
        #expect(lines().contains("vid_resize = 1"))
        #expect(lines().contains("force_43 = 1"))
    }

    @Test func everySpeedIsAPairInEightySixBoxsTable() {
        #expect(EightySixBoxCPU.of(setting: nil).megahertz == 450)
        #expect(lines().contains("cpu_speed = 450000000"))
        #expect(lines().contains("cpu_multi = 4.5"))

        let slower = lines(cpu: .of(setting: 350))
        #expect(slower.contains("cpu_speed = 350000000"))
        #expect(slower.contains("cpu_multi = 3.5"))
    }

    @Test func aSpeedNoLongerOfferedIsTheFastest() {
        #expect(EightySixBoxCPU.of(setting: 999).megahertz == 450)
    }

    @Test func theWindowItLastRememberedIsKept() {
        let written = lines(window: "81, 58, 2560, 1385").joined(separator: "\n")

        #expect(EightySixBoxSettings.rememberedWindow(in: written) == "81, 58, 2560, 1385")
        #expect(EightySixBoxSettings.rememberedWindow(in: "[General]\nconfirm_exit = 0\n") == nil)
    }
}

/// A press of Play on a Windows ROM (ADR 0041).
@Suite struct EightySixBoxPlayTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "86box play \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: directory.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var box: EightySixBoxSettings { EightySixBoxSettings(ludeum: ludeum) }
    let name = "Age of Empires (USA)"

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    func install() throws {
        let executable = ludeum.eightySixBoxApp.appending(path: "Contents/MacOS/86Box")
        try put(Data(), at: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
        try FileManager.default.createDirectory(
            at: ludeum.eightySixBoxROMSet.appending(path: "machines/p3bf", directoryHint: .isDirectory), withIntermediateDirectories: true)
    }

    func chooseBase() throws {
        try put(vhd(type: 3), at: ludeum.windowsBase)
        try put(Data("nvr".utf8), at: ludeum.windowsBaseBIOS.appending(path: "p3bf.nvr"))
    }

    func press(
        _ windows: FakeROMFolder, fileName: String = "Age of Empires (USA)/AOE.iso", settings: EmulatorSettings = .init(),
        running: Bool = false
    )
        -> Play.Outcome
    {
        let rom = LudeumROM(
            id: 1, folderName: name, platformId: ROMPlatform.windows, fileName: fileName, name: name, version: "", disc: nil,
            missing: false,
            archived: false)
        return Play(platformId: ROMPlatform.windows, platformName: "PC", roms: [rom], settings: settings)
            .prepare(
                locator: ROMLocator(romFolders: [windows.folder]), version: .ok, app: { _ in URL(filePath: "/Applications/Wrong.app") },
                eightySixBox: box, running: { _ in running })
    }

    func windows() throws -> FakeROMFolder {
        let windows = try FakeROMFolder(in: directory, platform: ROMPlatform.windows)
        try windows.add("Age of Empires (USA)/AOE.iso")
        return windows
    }

    func configuration() throws -> String {
        try String(contentsOf: ludeum.eightySixBoxMachine(ofROM: name).appending(path: "86box.cfg"), encoding: .utf8)
    }

    @Test func itsRefusedUntil86BoxIsInstalled() throws {
        #expect(press(try windows()).refusal == .notInstalled(.eightySixBox))
    }

    @Test func itsRefusedUntilThereIsABase() throws {
        try install()

        let outcome = press(try windows())

        #expect(outcome.refusal == .noWindowsBase)
        #expect(outcome.refusal?.message.contains("Emulators…") == true)
    }

    @Test func itsRefusedWhile86BoxIsOpen() throws {
        try install()
        try chooseBase()

        #expect(press(try windows(), running: true).refusal == .running(.eightySixBox))
    }

    @Test func theFirstPlayGivesTheBaseAsParentAndLeavesTheDiskFor86BoxToMake() throws {
        try install()
        try chooseBase()

        let outcome = press(try windows())

        guard case .open(let app, let arguments, _, _, _) = outcome else {
            Issue.record("\(outcome)")
            return
        }
        #expect(app == ludeum.eightySixBoxApp)
        let machine = ludeum.eightySixBoxMachine(ofROM: name)
        #expect(arguments.first == "-P")
        #expect(arguments.contains(String(machine.path(percentEncoded: false).dropLast())))
        #expect(arguments.contains("-N"))
        #expect(arguments.contains(String(ludeum.eightySixBoxROMSet.path(percentEncoded: false).dropLast())))
        let config = try configuration()
        #expect(config.contains("hdd_01_vhd_parent = \(ludeum.windowsBase.path(percentEncoded: false))"))
        #expect(config.contains("hdd_01_fn = \(ludeum.gameDisk(ofROM: name).path(percentEncoded: false))"))
        #expect(!FileManager.default.fileExists(atPath: ludeum.gameDisk(ofROM: name).path(percentEncoded: false)))
    }

    @Test func theMachineStartsWithTheBasesBIOSSettingsAndKeepsItsOwn() throws {
        try install()
        try chooseBase()
        let windows = try windows()
        let nvr = ludeum.eightySixBoxMachine(ofROM: name).appending(path: "nvr/p3bf.nvr")

        _ = press(windows)
        #expect(try Data(contentsOf: nvr) == Data("nvr".utf8))

        try Data("changed".utf8).write(to: nvr)
        _ = press(windows)
        #expect(try Data(contentsOf: nvr) == Data("changed".utf8))
    }

    @Test func aLaterPlayOpensTheDiskItMadeAtTheGamesSpeed() throws {
        try install()
        try chooseBase()
        try put(vhd(type: 4), at: ludeum.gameDisk(ofROM: name))

        let outcome = press(try windows(), settings: EmulatorSettings(cpuMegahertz: 400))

        #expect(outcome.refusal == nil)
        let config = try configuration()
        #expect(!config.contains("hdd_01_vhd_parent"))
        #expect(config.contains("cpu_speed = 400000000"))
    }

    @Test func aDiskWithNothingBeneathItIsRefused() throws {
        try install()
        try chooseBase()
        // What 86Box silently makes if a parent is missing.
        try put(vhd(type: 3), at: ludeum.gameDisk(ofROM: name))

        let outcome = press(try windows())

        guard case .refused(.couldntWriteSettings(.eightySixBox, let why)) = outcome else {
            Issue.record("\(outcome)")
            return
        }
        #expect(why.contains("differencing"))
    }

    @Test func aROMsOtherDiscsAreOfferedInTheMediaMenu() throws {
        try install()
        try chooseBase()
        let windows = try FakeROMFolder(in: directory, platform: ROMPlatform.windows)
        let one = try windows.add("Age of Empires (USA)/Disc 1.iso")
        try windows.add("Age of Empires (USA)/Disc 2.iso")

        #expect(EightySixBoxSettings.otherDiscs(than: one, romName: name).map(\.lastPathComponent) == ["Disc 2.iso"])
    }

    @Test func aCueSheetDoesntHideAnImageBesideIt() throws {
        let windows = try FakeROMFolder(in: directory, platform: ROMPlatform.windows)
        let one = try windows.add("Age of Empires (USA)/Disc 1.cue")
        try windows.add("Age of Empires (USA)/Disc 2.iso")

        #expect(EightySixBoxSettings.otherDiscs(than: one, romName: name).map(\.lastPathComponent) == ["Disc 2.iso"])
    }

    @Test func aLooseDiscHasNoOthers() throws {
        let windows = try FakeROMFolder(in: directory, platform: ROMPlatform.windows)
        let one = try windows.add("A.iso")
        try windows.add("B.iso")

        #expect(EightySixBoxSettings.otherDiscs(than: one, romName: "A").isEmpty)
    }
}

/// Choosing the Windows base and bringing it under Ludeum's control (ADR 0041).
@Suite(.enabled(if: SevenZip.find() != nil, "needs 7-Zip's 7zz"))
struct WindowsBaseTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "windows base \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var base: WindowsBase { WindowsBase(ludeum: ludeum, sevenZip: SevenZip.find()) }

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    /// An archive as `docs/agents/windows-base.md` makes one.
    func archive(disk: Data? = vhd(type: 3), bios: Bool = true) async throws -> URL {
        let staging = root.appending(path: "staging \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        var names: [String] = ["86box.cfg"]
        try Data("cfg".utf8).write(to: staging.appending(path: "86box.cfg"))
        if let disk {
            try disk.write(to: staging.appending(path: WindowsBase.fileName))
            names.append(WindowsBase.fileName)
        }
        if bios {
            try put(Data("nvr".utf8), at: staging.appending(path: "nvr/p3bf.nvr"))
            names.append("nvr")
        }
        let archive = root.appending(path: "base \(UUID().uuidString).7z")
        try await SevenZip.find()!.create(archive, files: names, in: staging) { _ in }
        return archive
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    @Test func itIsCopiedBesideTheGameDisksReadOnly() async throws {
        #expect(!base.isChosen)

        try await base.choose(try await archive())

        #expect(base.isChosen)
        #expect(base.file == ludeum.data.appending(path: "Emulators/86Box/Game Disks/ludeum-win98se-base.vhd"))
        let attributes = try FileManager.default.attributesOfItem(atPath: base.file.path(percentEncoded: false))
        #expect(attributes[.posixPermissions] as? Int == 0o444)
        #expect(exists(ludeum.windowsBaseBIOS.appending(path: "p3bf.nvr")))
        #expect(!exists(ludeum.emulators.appending(path: ".choosing Windows base")))
    }

    @Test func aBaseOfTheWrongShapeIsRefusedWithNothingChanged() async throws {
        let cases: [(Data?, Bool, String)] = [
            (nil, true, "no ludeum-win98se-base.vhd"),
            (Data("not a disk".utf8), true, "isn't a VHD"),
            (vhd(type: 4), true, "isn't a dynamic VHD"),
            (vhd(type: 3, cylinders: 16257), true, "geometry"),
            (vhd(type: 3), false, "BIOS settings"),
        ]
        for (disk, bios, why) in cases {
            do {
                try await base.choose(try await archive(disk: disk, bios: bios))
                Issue.record("Expected a refusal for \(why)")
            } catch let error as WindowsBaseError {
                #expect(error.localizedDescription.contains(why), "\(error.localizedDescription)")
            }
            #expect(!base.isChosen)
        }
    }

    @Test func aFileThatIsntAnArchiveIsRefused() async throws {
        let notArchive = root.appending(path: "not.7z")
        try Data("nope".utf8).write(to: notArchive)

        await #expect(throws: WindowsBaseError.notABase("it couldn't be read as an archive")) { try await base.choose(notArchive) }
    }

    @Test func anotherCanTakeItsPlaceWhileNothingStandsOnIt() async throws {
        try await base.choose(try await archive())
        let first = try Data(contentsOf: base.file)

        try await base.choose(try await archive(disk: vhd(type: 3) + Data(count: 512) + vhd(type: 3)))

        #expect(try Data(contentsOf: base.file) != first)
    }

    @Test func itCantBeReplacedOnceAGameDiskStandsOnIt() async throws {
        try await base.choose(try await archive())
        let first = try Data(contentsOf: base.file)
        try put(vhd(type: 4), at: ludeum.gameDisk(ofROM: "Z (Europe)"))

        await #expect(throws: WindowsBaseError.gameDisksStandOnIt) { try await base.choose(try await archive()) }

        #expect(try Data(contentsOf: base.file) == first)
        #expect(base.gameDisks.map(\.lastPathComponent) == ["Z (Europe).vhd"])
    }

    @Test func aGameDiskMadeDuringTheUnpackStopsTheSwap() async throws {
        try await base.choose(try await archive())
        let first = try Data(contentsOf: base.file)
        let disk = ludeum.gameDisk(ofROM: "Z (Europe)")

        // A Play on the base there, while the new one was being unpacked.
        await #expect(throws: WindowsBaseError.gameDisksStandOnIt) {
            try await base.choose(try await archive(disk: vhd(type: 3) + Data(count: 512) + vhd(type: 3))) { done in
                if done >= 0.9 { try? put(vhd(type: 4), at: disk) }
            }
        }

        #expect(try Data(contentsOf: base.file) == first)
    }

    @Test func machinesStartAgainFromANewBasesBIOSSettings() async throws {
        try await base.choose(try await archive())
        let machine = ludeum.eightySixBoxMachine(ofROM: "Z (Europe)").appending(path: "nvr/p3bf.nvr")
        try put(Data("the old base's".utf8), at: machine)

        try await base.choose(try await archive())

        #expect(!exists(machine))
    }

    @Test func itNeeds7Zip() async throws {
        await #expect(throws: WindowsBaseError.noSevenZip) {
            try await WindowsBase(ludeum: ludeum, sevenZip: nil).choose(root.appending(path: "base.7z"))
        }
    }
}

/// A Windows ROM's Rename (ADR 0041).
@Suite struct EightySixBoxRenameTests {
    let h: LudeumHarness
    let game: GameID
    let directory = FileManager.default.temporaryDirectory.appending(path: "86box rename \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: directory.appending(path: "Ludeum", directoryHint: .isDirectory)) }

    init() throws {
        h = try LudeumHarness()
        try h.journal.addPlatform(id: ROMPlatform.windows, name: "PC")
        game = try h.journal.addGame(platformId: ROMPlatform.windows, name: "Z")
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    func recorded(in folder: FakeROMFolder) throws -> LudeumROM {
        try folder.add("Z.iso")
        try h.journal.recordROM(game: game, fileName: "Z.iso", missing: false)
        let rom = try #require(try h.journal.roms(of: game).first)
        try h.journal.checkROMAgain(rom.id, in: folder.folder)
        return try #require(try h.journal.rom(rom.id))
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    @Test func itsGameDiskAndMachineFollowItsName() throws {
        let windows = try FakeROMFolder(in: directory, platform: ROMPlatform.windows)
        let rom = try recorded(in: windows)
        try put(vhd(type: 4), at: ludeum.gameDisk(ofROM: "Z"))
        try put(Data("cfg".utf8), at: ludeum.eightySixBoxMachine(ofROM: "Z").appending(path: "86box.cfg"))

        try h.journal.renameEightySixBoxROM(rom.id, from: "Z", to: "Z (Europe)", in: windows.folder, ludeum: ludeum)

        #expect(exists(ludeum.gameDisk(ofROM: "Z (Europe)")))
        #expect(!exists(ludeum.gameDisk(ofROM: "Z")))
        #expect(exists(ludeum.eightySixBoxMachine(ofROM: "Z (Europe)").appending(path: "86box.cfg")))
        #expect(!exists(ludeum.eightySixBoxMachine(ofROM: "Z")))
    }

    @Test func aROMNeverPlayedHasNothingToMove() throws {
        let windows = try FakeROMFolder(in: directory, platform: ROMPlatform.windows)
        let rom = try recorded(in: windows)

        try h.journal.renameEightySixBoxROM(rom.id, from: "Z", to: "Z (Europe)", in: windows.folder, ludeum: ludeum)

        #expect(try h.journal.rom(rom.id)?.folderName == "Z (Europe)")
    }

    @Test func aRenameThatFailsLeavesItsGameDiskWhereItWas() throws {
        let windows = try FakeROMFolder(in: directory, platform: ROMPlatform.windows)
        let rom = try recorded(in: windows)
        try put(vhd(type: 4), at: ludeum.gameDisk(ofROM: "Z"))
        try FileManager.default.removeItem(at: windows.url.appending(path: "Z.iso"))

        #expect(throws: (any Error).self) {
            try h.journal.renameEightySixBoxROM(rom.id, from: "Z", to: "Z (Europe)", in: windows.folder, ludeum: ludeum)
        }

        #expect(exists(ludeum.gameDisk(ofROM: "Z")))
        #expect(!exists(ludeum.gameDisk(ofROM: "Z (Europe)")))
    }

    @Test func itsRefusedWithAGameDiskUnderTheNewName() throws {
        let windows = try FakeROMFolder(in: directory, platform: ROMPlatform.windows)
        let rom = try recorded(in: windows)
        try put(vhd(type: 4), at: ludeum.gameDisk(ofROM: "Z (Europe)"))

        #expect(throws: EightySixBoxRenameError.gameDiskInTheWay("Z (Europe)")) {
            try h.journal.renameEightySixBoxROM(rom.id, from: "Z", to: "Z (Europe)", in: windows.folder, ludeum: ludeum)
        }
        #expect(try h.journal.rom(rom.id)?.folderName == "Z")
    }
}

/// A Game's own CPU speed (ADR 0041).
@Suite struct EightySixBoxSettingTests {
    @Test func aGameKeepsItsSpeed() throws {
        let h = try LudeumHarness()
        try h.journal.addPlatform(id: ROMPlatform.windows, name: "PC")
        let game = try h.journal.addGame(platformId: ROMPlatform.windows, name: "Renegade")

        #expect(try h.journal.emulatorSettings(game).cpuMegahertz == nil)

        try h.journal.setEmulatorSettings(game, EmulatorSettings(cpuMegahertz: 350))
        #expect(try h.journal.emulatorSettings(game).cpuMegahertz == 350)

        #expect(throws: LudeumError.cpuSpeedNotOffered) {
            try h.journal.setEmulatorSettings(game, EmulatorSettings(cpuMegahertz: 500))
        }
    }
}

/// Installing the 86Box Ludeum keeps (ADR 0041), from a real zip and tarball.
@Suite struct EightySixBoxInstallTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "86box install \(UUID().uuidString)", directoryHint: .isDirectory)
    var ludeum: LudeumFolder { LudeumFolder(url: root.appending(path: "Ludeum", directoryHint: .isDirectory)) }
    var settings: EightySixBoxSettings { EightySixBoxSettings(ludeum: ludeum) }

    init() throws {
        try FileManager.default.createDirectory(at: ludeum.data, withIntermediateDirectories: true)
    }

    /// Where the fake 86Box notes it was run: Install has no need to run it, which would open a machine.
    var ran: URL { root.appending(path: "86Box ran") }

    func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
    }

    func zip(appVersion: String = "6.0", noApp: Bool = false) throws -> Data {
        let staging = root.appending(path: "app \(UUID().uuidString)", directoryHint: .isDirectory)
        let app = staging.appending(path: noApp ? "Other.app" : "86Box.app", directoryHint: .isDirectory)
        let plist: [String: Any] = [
            "CFBundleShortVersionString": appVersion, "CFBundleExecutable": "86Box", "CFBundleIdentifier": "fake.86Box",
        ]
        try put(
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
            at: app.appending(path: "Contents/Info.plist"))
        let executable = app.appending(path: "Contents/MacOS/86Box")
        try put(Data("#!/bin/sh\ntouch '\(ran.path(percentEncoded: false))'\n".utf8), at: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
        let file = root.appending(path: "app \(UUID().uuidString).zip")
        try run("/usr/bin/ditto", ["-c", "-k", staging.path(percentEncoded: false), file.path(percentEncoded: false)])
        return try Data(contentsOf: file)
    }

    func tarball(board: String = "p3bf") throws -> Data {
        let staging = root.appending(path: "roms \(UUID().uuidString)", directoryHint: .isDirectory)
        try put(Data("bios".utf8), at: staging.appending(path: "roms-6.0/machines/\(board)/1008f.004"))
        let file = root.appending(path: "roms \(UUID().uuidString).tar.gz")
        try run("/usr/bin/tar", ["-czf", file.path(percentEncoded: false), "-C", staging.path(percentEncoded: false), "roms-6.0"])
        return try Data(contentsOf: file)
    }

    func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func installer(zip: Data, tarball: Data, version: String = "6.0") -> EightySixBoxInstaller {
        let release = EightySixBoxRelease(version: version, build: 9001, sha256: digest(zip), romSetSHA256: digest(tarball))
        return EightySixBoxInstaller(
            ludeum: ludeum, release: release, transport: FakeReleases([release.url: zip, release.romSetURL: tarball]))
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    @Test func theReleaseIsPinned() {
        let pinned = EightySixBoxRelease.pinned
        #expect(pinned.url.absoluteString == "https://github.com/86Box/86Box/releases/download/v6.0/86Box-macOS-x86_64%2Barm64-b9001.zip")
        #expect(pinned.romSetURL.absoluteString == "https://github.com/86Box/roms/archive/refs/tags/v6.0.tar.gz")
        #expect(Emulator.eightySixBox.expectedVersion == "6.0")
    }

    @Test func installingPutsTheAppAndROMSetInTheLudeumFolderWithoutRunningIt() async throws {
        try await installer(zip: try zip(), tarball: try tarball()).install()

        #expect(settings.isInstalled)
        #expect(exists(ludeum.eightySixBoxROMSet.appending(path: "machines/p3bf/1008f.004")))
        #expect(EmulatorVersions.check(.eightySixBox, app: settings.app)?.check == .ok)
        #expect(!exists(ludeum.emulators.appending(path: ".installing 86Box")))
        #expect(!exists(ran))
    }

    @Test func aBadDownloadReplacesNothing() async throws {
        try await installer(zip: try zip(), tarball: try tarball()).install()
        let release = EightySixBoxRelease(version: "6.0", build: 9001, sha256: "00", romSetSHA256: "00")
        let bad = EightySixBoxInstaller(ludeum: ludeum, release: release, transport: FakeReleases([release.url: try zip()]))

        await #expect(throws: EightySixBoxInstallError.self) { try await bad.install() }

        #expect(settings.isInstalled)
    }

    @Test func aROMSetWithoutTheMachineIsRefused() async throws {
        await #expect(throws: EightySixBoxInstallError.noMachine) {
            try await installer(zip: try zip(), tarball: try tarball(board: "other")).install()
        }
        #expect(!settings.isInstalled)
    }

    @Test func aZipWithoutTheAppIsRefused() async throws {
        await #expect(throws: EightySixBoxInstallError.noApp) {
            try await installer(zip: try zip(noApp: true), tarball: try tarball()).install()
        }
    }

    @Test func anAppOfAnotherVersionIsRefused() async throws {
        await #expect(throws: EightySixBoxInstallError.wrongBuild(found: "5.3")) {
            try await installer(zip: try zip(appVersion: "5.3"), tarball: try tarball()).install()
        }
    }

    @Test func anAppWithoutItsROMSetIsntInstalled() throws {
        let executable = ludeum.eightySixBoxApp.appending(path: "Contents/MacOS/86Box")
        try put(Data(), at: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))

        #expect(!settings.isInstalled)
    }
}
