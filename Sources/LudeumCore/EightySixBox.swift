import Foundation
import GRDB

extension LudeumFolder {
    /// The 86Box Ludeum installs (ADR 0041).
    public var eightySixBoxApp: URL { emulators.appending(path: "86Box.app", directoryHint: .isDirectory) }

    /// The ROM set it can't start without, its machines' and cards' own BIOS chips. Nothing to do with a Game's ROMs.
    public var eightySixBoxROMSet: URL { emulators.appending(path: "86Box ROMs", directoryHint: .isDirectory) }

    /// Every ROM's machine.
    var eightySixBoxMachines: URL { emulators.appending(path: "86Box Machines", directoryHint: .isDirectory) }

    /// The folder 86Box is pointed at for the ROM `name`'s Play: its `86box.cfg` and BIOS settings, rewritten as needed, so
    /// not in the Data folder.
    public func eightySixBoxMachine(ofROM name: String) -> URL {
        eightySixBoxMachines.appending(path: name, directoryHint: .isDirectory)
    }

    /// What 86Box keeps that has to survive: `Emulators/86Box/` in the Data folder.
    var eightySixBoxData: URL { data.appending(path: "Emulators/86Box", directoryHint: .isDirectory) }

    /// The Windows base and every game disk on it. They must stay in one folder: a game disk finds its parent by a full path
    /// or by a file name beside it, and 86Box refuses one that finds neither.
    public var eightySixBoxGameDisks: URL { eightySixBoxData.appending(path: "Game Disks", directoryHint: .isDirectory) }

    /// The read-only Windows every game disk stands on. Game disks know it by this name, so it can't change.
    public var windowsBase: URL { eightySixBoxGameDisks.appending(path: WindowsBase.fileName, directoryHint: .notDirectory) }

    /// The machine's BIOS settings as the base was prepared on, copied for each ROM's machine so a new game doesn't stop at a
    /// CMOS prompt.
    var windowsBaseBIOS: URL { eightySixBoxData.appending(path: "Base BIOS", directoryHint: .isDirectory) }

    /// The ROM `name`'s game disk: the installed game and all it has written, and its Game save.
    public func gameDisk(ofROM name: String) -> URL {
        eightySixBoxGameDisks.appending(path: "\(name).vhd", directoryHint: .notDirectory)
    }
}

/// A CPU speed 86Box's Pentium II (Deschutes) offers. 86Box names one by its speed and multiplier together, so they're kept
/// as its table has them. The bus is 100 MHz at 350 and up, 66 MHz below.
public struct EightySixBoxCPU: Sendable, Equatable {
    public let megahertz: Int
    let hertz: Int
    let multiplier: Double

    /// Fastest first. 450 MHz is the fastest Pentium II 86Box has, and the machine's default.
    public static let offered: [EightySixBoxCPU] = [
        .init(megahertz: 450, hertz: 450_000_000, multiplier: 4.5),
        .init(megahertz: 400, hertz: 400_000_000, multiplier: 4.0),
        .init(megahertz: 350, hertz: 350_000_000, multiplier: 3.5),
        .init(megahertz: 333, hertz: 333_333_333, multiplier: 5.0),
        .init(megahertz: 300, hertz: 300_000_000, multiplier: 4.5),
        .init(megahertz: 266, hertz: 266_666_666, multiplier: 4.0),
        .init(megahertz: 233, hertz: 233_333_333, multiplier: 3.5),
    ]

    /// The speed a Game's Emulator setting names, or the default where it names none or one that isn't offered.
    public static func of(setting megahertz: Int?) -> EightySixBoxCPU {
        offered.first { $0.megahertz == megahertz } ?? offered[0]
    }
}

/// What a VHD says about itself in the footer at its end.
struct VHDFooter: Equatable {
    enum Kind: UInt32 {
        case fixed = 2
        case dynamic = 3
        case differencing = 4
    }

    let kind: Kind
    let cylinders: Int
    let heads: Int
    let sectors: Int

    /// Nil for a file that isn't a VHD, or one of a kind 86Box doesn't read.
    init?(of file: URL) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size >= 512, (try? handle.seek(toOffset: size - 512)) != nil,
            let bytes = try? handle.read(upToCount: 512), bytes.count == 512, bytes.starts(with: Data("conectix".utf8))
        else { return nil }
        let footer = [UInt8](bytes)
        let type = footer[60..<64].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard let kind = Kind(rawValue: type) else { return nil }
        self.kind = kind
        cylinders = Int(footer[56]) << 8 | Int(footer[57])
        heads = Int(footer[58])
        sectors = Int(footer[59])
    }
}

/// Why a Windows base wasn't brought in, with nothing changed.
public enum WindowsBaseError: LocalizedError, Equatable {
    case noSevenZip
    /// Game disks stand on the base there, and wouldn't read true over another.
    case gameDisksStandOnIt
    /// What was chosen isn't a prepared base, with what's wrong with it.
    case notABase(String)

    public var errorDescription: String? {
        switch self {
        case .noSevenZip: "7-Zip is needed to read a Windows base. Install it with `brew install sevenzip`."
        case .gameDisksStandOnIt:
            "Game disks stand on the Windows base there, and would no longer read true over another. Delete them first."
        case .notABase(let why): "That isn't a prepared Windows base: \(why)."
        }
    }
}

/// The Windows every game stands on (ADR 0041): prepared by hand once, outside Ludeum, as it can't be shipped and its Setup
/// needs a person (`docs/agents/windows-base.md`), then chosen and kept read-only beside the game disks in the Data folder.
public struct WindowsBase: Sendable {
    /// The last year whose games are expected to play well. A guess from the few tried: Age of Empires (1997) and Red Alert 2
    /// (2000) played well, and Renegade (2002), in 3D, lagged with the emulated CPU flat out.
    static let lastYearExpectedToPlayWell = 2000

    /// What to warn of before Adding a ROM of a game released in `releaseYear` on the Platform: nil for any other Platform,
    /// an old enough game, or a game whose year isn't known.
    public static func warning(platformId: Int64, releaseYear: Int?) -> String? {
        guard platformId == ROMPlatform.windows, let releaseYear, releaseYear > lastYearExpectedToPlayWell else { return nil }
        return
            "Windows Games play on Windows 98 SE on an emulated Pentium II, which suits games from about 1995 to \(lastYearExpectedToPlayWell). One from \(releaseYear) may run slowly or not at all, 3D games most of all."
    }

    /// What a base is called, inside its archive and in the Data folder.
    public static let fileName = "ludeum-win98se-base.vhd"
    /// The machine's board's name, which 86Box names its BIOS settings for.
    static let board = "p3bf"
    /// The disk's geometry, as the machine's BIOS was set up against.
    static let cylinders = 65016
    static let heads = 16
    static let sectors = 63

    let ludeum: LudeumFolder
    let sevenZip: SevenZip?

    public init(ludeum: LudeumFolder = .standard, sevenZip: SevenZip? = SevenZip.find()) {
        self.ludeum = ludeum
        self.sevenZip = sevenZip
    }

    /// The base, in the Data folder.
    public var file: URL { ludeum.windowsBase }

    /// A base has been chosen and is there.
    public var isChosen: Bool { FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) }

    /// The game disks standing on it.
    public var gameDisks: [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: ludeum.eightySixBoxGameDisks, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "vhd" && $0.lastPathComponent != Self.fileName }
    }

    /// Brings a prepared base's archive under Ludeum's control: unpacked and checked to one side, then moved into the Data
    /// folder and made read-only. Refused with anything standing on a base already, looked for again just before the swap as a
    /// Play during the unpack would make a game disk. Nothing changes until it checks out, and a base it's replacing comes
    /// back if the new one won't go in. Each machine's BIOS settings started as the old base's, so they go with it.
    public func choose(_ archive: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        try ludeum.checkData()
        guard let sevenZip else { throw WindowsBaseError.noSevenZip }
        guard gameDisks.isEmpty else { throw WindowsBaseError.gameDisksStandOnIt }
        let files = FileManager.default
        let work = ludeum.emulators.appending(path: ".choosing Windows base", directoryHint: .isDirectory)
        try? files.removeItem(at: work)
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: work) }

        do {
            try await sevenZip.extract(archive, paths: [], to: work) { progress($0 * 0.9) }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WindowsBaseError.notABase("it couldn't be read as an archive")
        }
        let vhd = work.appending(path: Self.fileName, directoryHint: .notDirectory)
        guard files.fileExists(atPath: vhd.path(percentEncoded: false)) else {
            throw WindowsBaseError.notABase("it has no \(Self.fileName)")
        }
        guard let footer = VHDFooter(of: vhd) else { throw WindowsBaseError.notABase("its disk isn't a VHD") }
        guard footer.kind == .dynamic else { throw WindowsBaseError.notABase("its disk isn't a dynamic VHD") }
        guard footer.cylinders == Self.cylinders, footer.heads == Self.heads, footer.sectors == Self.sectors else {
            throw WindowsBaseError.notABase(
                "its disk's geometry is \(footer.cylinders)/\(footer.heads)/\(footer.sectors), not the machine's "
                    + "\(Self.cylinders)/\(Self.heads)/\(Self.sectors)")
        }
        let bios = work.appending(path: "nvr", directoryHint: .isDirectory)
        guard files.fileExists(atPath: bios.appending(path: "\(Self.board).nvr").path(percentEncoded: false)) else {
            throw WindowsBaseError.notABase("it has no BIOS settings for the machine")
        }
        try Task.checkCancellation()
        progress(0.9)
        guard gameDisks.isEmpty else { throw WindowsBaseError.gameDisksStandOnIt }

        try files.createDirectory(at: ludeum.eightySixBoxGameDisks, withIntermediateDirectories: true)
        let oldBase = work.appending(path: "old base", directoryHint: .notDirectory)
        let oldBIOS = work.appending(path: "old BIOS", directoryHint: .isDirectory)
        let hadBase = isChosen
        let hadBIOS = files.fileExists(atPath: ludeum.windowsBaseBIOS.path(percentEncoded: false))
        if hadBase { try files.moveItem(at: file, to: oldBase) }
        do {
            if hadBIOS { try files.moveItem(at: ludeum.windowsBaseBIOS, to: oldBIOS) }
            try files.moveItem(at: bios, to: ludeum.windowsBaseBIOS)
            try files.moveItem(at: vhd, to: file)
            try files.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path(percentEncoded: false))
        } catch {
            try? files.removeItem(at: file)
            if hadBase { try? files.moveItem(at: oldBase, to: file) }
            if hadBIOS {
                try? files.removeItem(at: ludeum.windowsBaseBIOS)
                try? files.moveItem(at: oldBIOS, to: ludeum.windowsBaseBIOS)
            }
            throw error
        }
        try? files.removeItem(at: ludeum.eightySixBoxMachines)
        progress(1)
    }
}

/// Why a Play in 86Box couldn't start.
public enum EightySixBoxPlayError: LocalizedError, Equatable {
    /// 86Box silently makes an ordinary disk when a game disk's parent is missing, and one of those has nothing beneath it.
    case notADifferencingDisk(String)

    public var errorDescription: String? {
        switch self {
        case .notADifferencingDisk(let name):
            "\(name) isn't a differencing disk over the Windows base, so it can't be Played."
        }
    }
}

/// The 86Box Ludeum installs and keeps (ADR 0041): `Emulators/86Box.app` with its ROM set in the Ludeum folder.
///
/// There's one machine, written out before each Play as its Standing settings, as Windows has installed drivers for it. A ROM
/// is its disc and is never written to. What's written goes in its game disk, a file of differences over the Windows base, made
/// by 86Box at the first Play: the installed game and its Game saves together.
public struct EightySixBoxSettings: Sendable {
    /// The 86Box.app Ludeum installs.
    public let app: URL
    /// The Ludeum folder, whose Data folder holds the base and the game disks.
    let ludeum: LudeumFolder

    public init(ludeum: LudeumFolder = .standard) {
        self.app = ludeum.eightySixBoxApp
        self.ludeum = ludeum
    }

    /// The app's executable and the ROM set it can't start without are there.
    public var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/86Box").path(percentEncoded: false))
            && FileManager.default.fileExists(
                atPath: ludeum.eightySixBoxROMSet.appending(path: "machines/\(WindowsBase.board)").path(percentEncoded: false))
    }

    /// A Windows base has been chosen.
    public var hasBase: Bool { WindowsBase(ludeum: ludeum, sevenZip: nil).isChosen }

    /// The window 86Box opens at until it has remembered one of its own.
    static let defaultWindow = "100, 60, 1024, 848"

    /// A path without a trailing `/`.
    private static func withoutSlash(_ folder: URL) -> String {
        let path = folder.path(percentEncoded: false)
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// The other Discs in a ROM's subfolder, for 86Box's Media menu to offer, up to the four it remembers. None for a ROM that
    /// isn't in a subfolder of its own.
    static func otherDiscs(than disc: URL, romName: String) -> [URL] {
        let folder = disc.deletingLastPathComponent()
        guard folder.lastPathComponent == romName else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { ["cue", "iso"].contains($0.pathExtension.lowercased()) }
            .filter { $0.lastPathComponent != disc.lastPathComponent }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(4).map { $0 }
    }

    /// The machine's `86box.cfg`. `parent` is the base when the game disk has yet to be made, which 86Box does itself on
    /// finding a parent and no file. 86Box's own fullscreen leaves a fixed window's picture small in the middle, so the window
    /// resizes and keeps to 4:3, and the Mac's full screen fills it.
    static func configuration(disk: URL, parent: URL?, disc: URL, otherDiscs: [URL], cpu: EightySixBoxCPU, window: String) -> String {
        var hardDisk = ["hdd_01_fn = \(disk.path(percentEncoded: false))"]
        if let parent { hardDisk.append("hdd_01_vhd_parent = \(parent.path(percentEncoded: false))") }
        let history = otherDiscs.enumerated().map { index, other in
            "cdrom_01_image_history_\(String(format: "%02d", index + 1)) = \(other.path(percentEncoded: false))"
        }
        return
            ([
                "[General]",
                "confirm_exit = 0",
                "confirm_reset = 0",
                "confirm_save = 0",
                "force_43 = 1",
                "vid_renderer = qt_opengl3",
                "vid_resize = 1",
                "window_remember = 1",
                "",
                "[Machine]",
                "cpu_family = pentium2_deschutes",
                "cpu_multi = \(cpu.multiplier)",
                "cpu_speed = \(cpu.hertz)",
                "cpu_use_dynarec = 1",
                "fpu_type = internal",
                "machine = \(WindowsBase.board)",
                "mem_size = 262144",
                "",
                "[Video]",
                "gfxcard = voodoo3_3500_agp",
                "video_fullscreen_scale_maximized = 1",
                "",
                "[Input devices]",
                "keyboard_type = keyboard_ps2",
                "mouse_type = ps2",
                "",
                "[Sound]",
                "sndcard = sb16_pnp",
                "",
                "[Hard disks]",
            ] + hardDisk + [
                "hdd_01_ide_channel = 0:0",
                "hdd_01_parameters = \(WindowsBase.sectors), \(WindowsBase.heads), \(WindowsBase.cylinders), 0, ide",
                "hdd_01_speed = 1997_5400rpm",
                "",
                "[Floppy and CD-ROM drives]",
                "cdrom_01_ide_channel = 1:0",
                "cdrom_01_image_path = \(disc.path(percentEncoded: false))",
            ] + history + [
                "cdrom_01_parameters = 1, atapi",
                "cdrom_01_speed = 24",
                // A CD-only drive refuses an image larger than a CD.
                "cdrom_01_type = 86dvd",
                "fdd_01_type = 35_2hd",
                "fdd_host_buffering = 1",
                "",
                "[Monitor #1]",
                "window_coordinates = \(window)",
                "",
                "[3dfx Voodoo3 3500 AGP]",
                "bios = voodoo3_3500_agp_ntsc",
                "render_threads = 4",
                "",
            ]).joined(separator: "\n")
    }

    /// The window 86Box last remembered in a machine's `86box.cfg`, so a Play opens where the last one was.
    static func rememberedWindow(in configuration: String) -> String? {
        let lines = configuration.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let monitor = lines.firstIndex(of: "[Monitor #1]") else { return nil }
        for line in lines[(monitor + 1)...] {
            if line.hasPrefix("[") { return nil }
            if line.hasPrefix("window_coordinates = ") { return String(line.dropFirst("window_coordinates = ".count)) }
        }
        return nil
    }

    /// Writes the ROM's machine and gives the command line: Disc 1 in the drive, any other Discs in the Media menu, and its
    /// game disk, which 86Box makes at its first Play. Each ROM has BIOS settings of its own, starting as the base's.
    func arguments(rom: URL, romName: String, settings: EmulatorSettings) throws -> [String] {
        try ludeum.checkData()
        let files = FileManager.default
        let machine = ludeum.eightySixBoxMachine(ofROM: romName)
        let bios = machine.appending(path: "nvr", directoryHint: .isDirectory)
        try files.createDirectory(at: machine, withIntermediateDirectories: true)
        if !files.fileExists(atPath: bios.path(percentEncoded: false)) { try files.copyItem(at: ludeum.windowsBaseBIOS, to: bios) }

        let disk = ludeum.gameDisk(ofROM: romName)
        let diskExists = files.fileExists(atPath: disk.path(percentEncoded: false))
        if diskExists, VHDFooter(of: disk)?.kind != .differencing {
            throw EightySixBoxPlayError.notADifferencingDisk(disk.lastPathComponent)
        }

        let configurationFile = machine.appending(path: "86box.cfg", directoryHint: .notDirectory)
        let window = (try? String(contentsOf: configurationFile, encoding: .utf8)).flatMap(Self.rememberedWindow) ?? Self.defaultWindow
        let configuration = Self.configuration(
            disk: disk, parent: diskExists ? nil : ludeum.windowsBase, disc: rom, otherDiscs: Self.otherDiscs(than: rom, romName: romName),
            cpu: .of(setting: settings.cpuMegahertz), window: window)
        try Data(configuration.utf8).write(to: configurationFile, options: .atomic)

        return [
            "-P", Self.withoutSlash(machine),
            "-R", Self.withoutSlash(ludeum.eightySixBoxROMSet),
            "-O", machine.appending(path: "86box_global.cfg").path(percentEncoded: false),
            // No asking on quitting.
            "-N",
        ]
    }
}

/// Why a Windows ROM's Rename was refused, with nothing renamed.
public enum EightySixBoxRenameError: LocalizedError, Equatable {
    /// There's a game disk under the new name.
    case gameDiskInTheWay(String)

    public var errorDescription: String? {
        switch self {
        case .gameDiskInTheWay(let name): "There's already a game disk for \(name), so nothing was renamed."
        }
    }
}

extension LudeumStore {
    /// Renames a Windows ROM as `renameROM(_:to:in:)` does, with its game disk and machine. Its game disk finds the base by
    /// the base's name, not its own. Refused, with nothing renamed, when there's a game disk of the new name. The disk moves
    /// first and comes back if the ROM can't be renamed, as a ROM whose disk stayed behind would start a new install.
    public func renameEightySixBoxROM(
        _ rom: Int64, from oldName: String, to name: String, in folder: ROMFolder, ludeum: LudeumFolder = .standard
    ) throws {
        let files = FileManager.default
        let oldDisk = ludeum.gameDisk(ofROM: oldName)
        let newDisk = ludeum.gameDisk(ofROM: name)
        // Differing only in case, they're the one file.
        let sameDisk = oldName.caseInsensitiveCompare(name) == .orderedSame
        if !sameDisk, files.fileExists(atPath: newDisk.path(percentEncoded: false)) { throw EightySixBoxRenameError.gameDiskInTheWay(name) }
        let hadDisk = files.fileExists(atPath: oldDisk.path(percentEncoded: false))
        if hadDisk { try files.moveItem(at: oldDisk, to: newDisk) }
        do {
            try renameROM(rom, to: name, in: folder)
        } catch {
            if hadDisk { try? files.moveItem(at: newDisk, to: oldDisk) }
            throw error
        }
        let oldMachine = ludeum.eightySixBoxMachine(ofROM: oldName)
        let newMachine = ludeum.eightySixBoxMachine(ofROM: name)
        if files.fileExists(atPath: oldMachine.path(percentEncoded: false)) {
            if !sameDisk { try? files.removeItem(at: newMachine) }
            try? files.moveItem(at: oldMachine, to: newMachine)
        }
    }
}
