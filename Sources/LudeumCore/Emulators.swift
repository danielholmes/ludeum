import Foundation
import GRDB

/// The app a Platform's Games are played in.
public struct Emulator: Sendable, Hashable {
    public let name: String
    public let bundleIdentifier: String

    public static let mesenCE = Emulator(name: "MesenCE", bundleIdentifier: "ca.mesen")
    public static let duckStation = Emulator(name: "DuckStation", bundleIdentifier: "com.github.stenzek.duckstation")
    public static let dolphin = Emulator(name: "Dolphin", bundleIdentifier: "org.dolphin-emu.dolphin")
    public static let ares = Emulator(name: "ares", bundleIdentifier: "dev.ares.ares")
    public static let melonDS = Emulator(name: "melonDS", bundleIdentifier: "net.kuribo64.melonDS")
    public static let ymir = Emulator(name: "Ymir", bundleIdentifier: "io.github.strikerx3.ymir")
    public static let ppsspp = Emulator(name: "PPSSPP", bundleIdentifier: "org.ppsspp.ppsspp")
    public static let pcsx2 = Emulator(name: "PCSX2", bundleIdentifier: "net.pcsx2.pcsx2")
    public static let xemu = Emulator(name: "xemu", bundleIdentifier: "xemu.app.0")
    public static let amiberry = Emulator(name: "Amiberry", bundleIdentifier: "com.blitterstudio.Amiberry")
    public static let eightySixBox = Emulator(name: "86Box", bundleIdentifier: "net.86Box.86Box")
    public static let dosBoxStaging = Emulator(name: "DOSBox Staging", bundleIdentifier: "io.github.dosbox-staging")
    /// The app is Ludeum's own, made around KEmulator nnmod and a Java runtime at Install (ADR 0044), so the identifier is too.
    public static let kemulator = Emulator(name: "KEmulator", bundleIdentifier: "org.danielholmes.Ludeum.KEmulator")

    public static let all: [Emulator] = [
        .mesenCE, .duckStation, .dolphin, .ares, .melonDS, .ymir, .ppsspp, .pcsx2, .xemu, .amiberry, .eightySixBox, .dosBoxStaging,
        .kemulator,
    ]

    /// One of the Emulators Ludeum installs and keeps in the Ludeum folder: DuckStation (ADR 0024), MesenCE (ADR 0027),
    /// ares (ADR 0028), PCSX2 (ADR 0032), Amiberry (ADR 0035), Ymir (ADR 0036), 86Box (ADR 0041), DOSBox Staging (ADR 0042)
    /// and KEmulator (ADR 0044).
    public var isLudeums: Bool {
        self == .duckStation || self == .mesenCE || self == .ares || self == .pcsx2 || self == .amiberry || self == .ymir
            || self == .eightySixBox || self == .dosBoxStaging || self == .kemulator
    }

    /// The Emulator a Platform's Games are played in, if it has one.
    public static func of(platformId: Int64) -> Emulator? {
        switch platformId {
        // NES, Family Computer, SNES, Super Famicom, Game Boy, Game Boy Color, GBA, Master System, Game Gear, PC Engine, PC Engine CD
        case 18, 99, 19, 58, 33, 22, 24, 64, 35, 86, 150: .mesenCE
        case 7: .duckStation  // PlayStation
        case 21, 5: .dolphin  // GameCube, Wii
        case 4: .ares  // Nintendo 64
        case 29: .ares  // Mega Drive/Genesis
        case 78: .ares  // Sega CD
        case 20: .melonDS  // Nintendo DS
        case 32: .ymir  // Saturn
        case 38: .ppsspp  // PlayStation Portable
        case 8: .pcsx2  // PlayStation 2
        case 11: .xemu  // Xbox
        case 16: .amiberry  // Amiga
        case 6: .eightySixBox  // PC (Microsoft Windows)
        case 13: .dosBoxStaging  // DOS
        case 55: .kemulator  // Legacy Mobile Device: Java phone games
        default: nil
        }
    }

    /// The command line for a Play. It sets every Emulator setting, with the default where the Game
    /// has none (ADR 0008). DuckStation, PCSX2 and PPSSPP take settings only as a whole file, so their Plays write one
    /// first (`DuckStationSettings`, `PCSX2Settings`, `PPSSPPSettings`); DuckStation's and PCSX2's are only their Standing
    /// settings, as a Game's own are set in the Emulator (ADRs 0029, 0032). MesenCE's and ares's Standing settings go into
    /// their own settings files (`MesenSettings`, `AresSettings`), the Game's own on their command lines. DuckStation,
    /// MesenCE, ares and PCSX2 start from a `saveState`. Amiberry's are all for the one launch, with its disks' save images
    /// made first (`AmiberrySettings`). Ymir's go into its own settings file, with what's in its first port for this Disc
    /// (`YmirSettings`). 86Box's are named by its ROM rather than its file, so `Play.prepare` gets them from
    /// `EightySixBoxSettings` itself, and DOSBox Staging's by its ROM's subfolder from `DOSBoxStagingSettings`.
    public func arguments(
        rom: URL, platformId: Int64, settings: EmulatorSettings, saveState: URL? = nil,
        duckStation: DuckStationSettings = .init(), mesen: MesenSettings = .init(), ares: AresSettings = .init(),
        ppsspp: PPSSPPSettings = .init(), pcsx2: PCSX2Settings = .init(), amiberry: AmiberrySettings = .init(),
        ymir: YmirSettings = .init()
    ) throws -> [String] {
        switch self {
        case .amiberry:
            try amiberry.arguments(rom: rom, romName: rom.deletingPathExtension().lastPathComponent)
        case .duckStation:
            try duckStation.arguments(rom: rom, saveState: saveState)
        case .mesenCE:
            try mesen.arguments(rom: rom, platformId: platformId, settings: settings, saveState: saveState)
        case .dolphin:
            // Lower input latency for every Game, for this launch only: frames shown as soon as
            // they're ready, with their timing smoothed. Immediately Present XFB stays off: it breaks some Games. A
            // multi-disc ROM's playlist swaps to the Disc its Game asks for (ADR 0031).
            [
                "-C", "Main.Core.RushFramePresentation=True", "-C", "Main.Core.SmoothEarlyPresentation=True", "-C",
                "Main.Core.AutoDiscChange=True", "-e", rom.path(percentEncoded: false),
            ]
        case .ares:
            try ares.arguments(rom: rom, platformId: platformId, settings: settings, saveState: saveState)
        case .ymir:
            try ymir.arguments(rom: rom)
        case .melonDS:
            // No settings: it just opens the Game.
            [rom.path(percentEncoded: false)]
        case .pcsx2:
            try pcsx2.arguments(rom: rom, saveState: saveState)
        case .xemu:
            // No settings: xemu has no run-ahead, and its one latency setting, VSync, stays its own. The disc isn't saved
            // into its settings.
            ["-dvd_path", rom.path(percentEncoded: false)]
        case .ppsspp:
            // Not `--appendconfig`: PPSSPP saves the merged settings into its own ppsspp.ini.
            ["--config=\(try ppsspp.write().path(percentEncoded: false))", rom.path(percentEncoded: false)]
        default:
            [rom.path(percentEncoded: false)]
        }
    }
}

/// A folder DuckStation keeps that lives in the Data folder, under `Emulators/DuckStation/`, where its Standing settings
/// point it (ADR 0024): what must survive losing this Mac. What's rebuildable (its caches, shaders, textures, covers)
/// stays in its data root.
public enum DuckStationFolder: CaseIterable, Sendable {
    case saveStates, memoryCards, bios, gameSettings, inputProfiles, screenshots

    /// Its name in the Data folder.
    public var name: String {
        switch self {
        case .saveStates: "Save States"
        case .memoryCards: "Memory Cards"
        case .bios: "BIOS"
        case .gameSettings: "Game Settings"
        case .inputProfiles: "Input Profiles"
        case .screenshots: "Screenshots"
        }
    }

    /// The `settings.ini` section and key that place it.
    var setting: (section: String, key: String) {
        switch self {
        case .saveStates: ("Folders", "SaveStates")
        case .memoryCards: ("MemoryCards", "Directory")
        case .bios: ("BIOS", "SearchDirectory")
        case .gameSettings: ("Folders", "GameSettings")
        case .inputProfiles: ("Folders", "InputProfiles")
        case .screenshots: ("Folders", "Screenshots")
        }
    }
}

/// The DuckStation Ludeum installs and keeps (ADR 0024): `Emulators/DuckStation.app` in the Ludeum folder, made portable
/// so its data root is its own `Contents/MacOS`, where its `settings.ini` lives, and no other DuckStation shares it.
///
/// Its **Standing settings** are written before every launch Ludeum gives it: every folder worth keeping into the Data
/// folder (`DuckStationFolder`), and no checking for updates (DuckStation would replace its own bundle). The PlayStation
/// ROM folder is among its game list's folders, so a lone Disc of a set can swap to the set's others (ADR 0026).
/// Everything else in the file is DuckStation's own, fast boot and frame pacing included (ADR 0033).
///
/// A Game's own settings are DuckStation's, set in its Game Properties and kept in its per-game files in the Data
/// folder's `Game Settings`, which Ludeum doesn't write (ADR 0029).
public struct DuckStationSettings: Sendable {
    /// The DuckStation.app Ludeum installs.
    public let app: URL
    /// Its data root, holding its `settings.ini`: `Contents/MacOS`, as it's portable.
    let dataFolder: URL
    /// The Ludeum folder, whose Data folder holds what DuckStation keeps.
    let ludeum: LudeumFolder

    public init(ludeum: LudeumFolder = .standard) {
        self.init(app: ludeum.duckStationApp, ludeum: ludeum)
    }

    /// `dataFolder` stands in for the app's `Contents/MacOS`, in tests.
    init(app: URL, dataFolder: URL? = nil, ludeum: LudeumFolder) {
        self.app = app
        self.dataFolder = dataFolder ?? app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        self.ludeum = ludeum
    }

    /// Its `settings.ini`.
    var settingsFile: URL { dataFolder.appending(path: "settings.ini") }

    /// The app's executable is there.
    public var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/DuckStation").path(percentEncoded: false))
    }

    /// Its `portable.txt` is beside its executable, so its data root is its own.
    public var isPortable: Bool {
        FileManager.default.fileExists(atPath: dataFolder.appending(path: "portable.txt").path(percentEncoded: false))
    }

    /// Writes the Standing settings, then opens the ROM, from `saveState` if given (`-statefile`): `--` ends
    /// DuckStation's options. When the disc the state was saved with isn't where it was (a renamed ROM), DuckStation boots
    /// the ROM instead. Refused while the Data folder is missing.
    func arguments(rom: URL, saveState: URL? = nil) throws -> [String] {
        try writeStanding()
        return (saveState.map { ["-statefile", $0.path(percentEncoded: false)] } ?? []) + ["--", rom.path(percentEncoded: false)]
    }

    /// Writes the Standing settings into `settings.ini`, making the Data folder's DuckStation folders for it to write
    /// into. Refused while the Data folder is missing, so nothing is kept somewhere Dropbox doesn't see. The file is
    /// left alone when it already says so.
    public func writeStanding() throws {
        try ludeum.checkData()
        for folder in DuckStationFolder.allCases {
            try FileManager.default.createDirectory(at: ludeum.duckStation(folder), withIntermediateDirectories: true)
        }
        let original = try? String(contentsOf: settingsFile, encoding: .utf8)
        let updated = Self.standing(in: original ?? "", ludeum: ludeum)
        guard updated != original else { return }
        try FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
        try updated.write(to: settingsFile, atomically: true, encoding: .utf8)
    }

    /// `ini` with the Standing settings: each folder's key an absolute path into the Data folder, `[AutoUpdater]
    /// CheckAtStartup` off, and the PlayStation ROM folder in `[GameList] RecursivePaths`, beside any of DuckStation's
    /// own.
    static func standing(in ini: String, ludeum: LudeumFolder) -> String {
        var ini = ini
        for folder in DuckStationFolder.allCases {
            ini = Ini.setting(folder.setting.key, to: path(ludeum.duckStation(folder)), in: folder.setting.section, of: ini)
        }
        if let ps1 = ludeum.romFolder(platform: ROMPlatform.ps1) {
            ini = Ini.including(path(ps1), as: "RecursivePaths", in: "GameList", of: ini)
        }
        return Ini.setting("CheckAtStartup", to: "false", in: "AutoUpdater", of: ini)
    }

    /// A folder's path as DuckStation's settings write one: without a trailing `/`.
    private static func path(_ folder: URL) -> String {
        let path = folder.path(percentEncoded: false)
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// Where DuckStation keeps its per-game files.
    var gameSettingsFolder: URL { folder("GameSettings", default: "gamesettings") }

    /// The per-game file for a disc's Serial.
    func gameSettingsFile(_ serial: String) -> URL { gameSettingsFolder.appending(path: Self.fileName(serial) + ".ini") }

    /// A Serial as a file's name: `/` and `:` can't be in one.
    static func fileName(_ serial: String) -> String { String(serial.map { "/:".contains($0) ? "_" : $0 }) }

    /// One of DuckStation's folders: its settings' `[<section>] <key>` (from its data root when relative), else `name`
    /// in its data root.
    func folder(_ key: String, in section: String = "Folders", default name: String) -> URL {
        let ini = (try? String(contentsOf: settingsFile, encoding: .utf8)) ?? ""
        guard let path = Ini.value(key, in: section, of: ini), !path.isEmpty else {
            return dataFolder.appending(path: name, directoryHint: .isDirectory)
        }
        return path.hasPrefix("/")
            ? URL(filePath: path, directoryHint: .isDirectory) : dataFolder.appending(path: path, directoryHint: .isDirectory)
    }
}

/// The settings file a PPSSPP Play starts with: a copy of PPSSPP's own `ppsspp.ini` with its lowest-latency
/// display settings for every Game (PSP emulators have no run-ahead). Controls stay in PPSSPP's own
/// `controls.ini`. Changes made in PPSSPP during that Play go to the copy and are lost.
public struct PPSSPPSettings: Sendable {
    let base: URL
    let copy: URL

    public init(
        base: URL = URL.homeDirectory.appending(path: ".config/ppsspp/PSP/SYSTEM/ppsspp.ini"),
        copy: URL = LudeumFolder.standard.url.appending(path: "PPSSPP ppsspp.ini")
    ) {
        self.base = base
        self.copy = copy
    }

    /// Writes the copy and returns where it is.
    func write() throws -> URL {
        let original = (try? String(contentsOf: base, encoding: .utf8)) ?? ""
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.applying(to: original).write(to: copy, atomically: true, encoding: .utf8)
        return copy
    }

    /// `ini` with one frame in flight, low-latency presentation and no frame skipping.
    static func applying(to ini: String) -> String {
        [("InflightFrames", "1"), ("LowLatencyPresent", "True"), ("FrameSkip", "0")].reduce(ini) {
            Ini.setting($1.0, to: $1.1, in: "Graphics", of: $0)
        }
    }
}

/// Editing an emulator's `.ini` settings file as text, keeping everything else in it.
enum Ini {
    /// `ini` with `key = value` in `[section]`: replaced where it is, else added at the top of the
    /// section, else in a new section at the top.
    static func setting(_ key: String, to value: String, in section: String, of ini: String) -> String {
        let setting = "\(key) = \(value)"
        let header = "[\(section)]"
        var lines = lines(of: ini)
        var current = ""
        for (i, line) in lines.enumerated() {
            let trimmed = trimmed(line)
            if trimmed.hasPrefix("[") {
                current = trimmed
            } else if current == header, Self.key(of: trimmed) == key {
                lines[i] = setting
                return lines.joined(separator: "\n")
            }
        }
        return inserting(setting, in: section, into: lines)
    }

    /// `ini` with `key = value` in `[section]` among any others of a key that's a list, as DuckStation's are, added at
    /// the top of the section (else in a new section at the top) unless it's there already.
    static func including(_ value: String, as key: String, in section: String, of ini: String) -> String {
        values(key, in: section, of: ini).contains(value) ? ini : inserting("\(key) = \(value)", in: section, into: lines(of: ini))
    }

    /// Whether `ini` has a `[section]`.
    static func hasSection(_ section: String, in ini: String) -> Bool {
        lines(of: ini).contains { trimmed($0) == "[\(section)]" }
    }

    /// `lines` with `setting` at the top of `[section]`, else in a new section at the top, as one text.
    private static func inserting(_ setting: String, in section: String, into lines: [String]) -> String {
        var lines = lines
        if let start = lines.firstIndex(where: { trimmed($0) == "[\(section)]" }) {
            lines.insert(setting, at: start + 1)
        } else {
            lines.insert(contentsOf: ["[\(section)]", setting, ""], at: 0)
        }
        return lines.joined(separator: "\n")
    }

    /// The value of `key` in `[section]`, if it's there.
    static func value(_ key: String, in section: String, of ini: String) -> String? {
        values(key, in: section, of: ini).first
    }

    /// Every value of `key` in `[section]`, in order: more than one for a key that's a list.
    static func values(_ key: String, in section: String, of ini: String) -> [String] {
        var current = ""
        var values: [String] = []
        for line in lines(of: ini) {
            let trimmed = trimmed(line)
            if trimmed.hasPrefix("[") {
                current = trimmed
            } else if current == "[\(section)]", Self.key(of: trimmed) == key, let equals = trimmed.firstIndex(of: "=") {
                values.append(trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces))
            }
        }
        return values
    }

    /// Whether a value is true as DuckStation reads a boolean.
    static func isTrue(_ value: String) -> Bool { ["true", "yes", "on", "1"].contains(value.lowercased()) }

    /// Split at each line feed, so a line ending CRLF keeps its CR (which `trimmed` drops) and is written back as it was.
    private static func lines(of ini: String) -> [String] { ini.components(separatedBy: "\n") }

    private static func trimmed(_ line: String) -> String { line.trimmingCharacters(in: .whitespacesAndNewlines) }

    private static func key(of line: String) -> String? {
        line.split(separator: "=").first?.trimmingCharacters(in: .whitespaces)
    }
}

/// A Game's own Emulator settings. Nil means the Emulator's default.
public struct EmulatorSettings: Sendable, Equatable {
    public var runAheadFrames: Int?
    /// Nil is Auto: MesenCE picks from the ROM, favouring Game Boy Color.
    public var gameBoyModel: GameBoyModel?
    /// The speed of 86Box's Pentium II for this Game, in MHz (`EightySixBoxCPU.offered`). Nil is its fastest.
    public var cpuMegahertz: Int?
    /// The program a DOS Game starts with, its path on drive C as DOS has it (`KEEN1\KEEN1.EXE`). Nil is a DOS prompt.
    public var dosProgram: String?

    public static let runAheadRange = 0...10

    public init(runAheadFrames: Int? = nil, gameBoyModel: GameBoyModel? = nil, cpuMegahertz: Int? = nil, dosProgram: String? = nil) {
        self.runAheadFrames = runAheadFrames
        self.gameBoyModel = gameBoyModel
        self.cpuMegahertz = cpuMegahertz
        self.dosProgram = dosProgram
    }
}

/// The hardware MesenCE pretends to be when a Game Boy or Game Boy Color Game is played. It never
/// changes the Game's Platform.
public enum GameBoyModel: String, Sendable, CaseIterable {
    case gameBoy, gameBoyColor, superGameBoy

    /// Game Boy and Game Boy Color.
    public static func applies(to platformId: Int64) -> Bool { platformId == 33 || platformId == 22 }

    var mesenName: String {
        switch self {
        case .gameBoy: "Gameboy"
        case .gameBoyColor: "GameboyColor"
        case .superGameBoy: "SuperGameboy"
        }
    }
}

extension LudeumStore {
    public func emulatorSettings(_ game: GameID) throws -> EmulatorSettings {
        try db.read { db in
            let row = try Row.fetchOne(
                db, sql: "SELECT runAheadFrames, gameBoyModel, cpuMegahertz, dosProgram FROM game WHERE id = ?", arguments: [game])
            return EmulatorSettings(
                runAheadFrames: row?["runAheadFrames"],
                gameBoyModel: (row?["gameBoyModel"] as String?).flatMap(GameBoyModel.init(rawValue:)),
                cpuMegahertz: row?["cpuMegahertz"], dosProgram: row?["dosProgram"])
        }
    }

    public func setEmulatorSettings(_ game: GameID, _ settings: EmulatorSettings) throws {
        if let frames = settings.runAheadFrames, !EmulatorSettings.runAheadRange.contains(frames) {
            throw LudeumError.runAheadOutOfRange
        }
        if let megahertz = settings.cpuMegahertz, !EightySixBoxCPU.offered.contains(where: { $0.megahertz == megahertz }) {
            throw LudeumError.cpuSpeedNotOffered
        }
        try db.write { db in
            try db.execute(
                sql: "UPDATE game SET runAheadFrames = ?, gameBoyModel = ?, cpuMegahertz = ?, dosProgram = ? WHERE id = ?",
                arguments: [settings.runAheadFrames, settings.gameBoyModel?.rawValue, settings.cpuMegahertz, settings.dosProgram, game])
        }
    }
}
