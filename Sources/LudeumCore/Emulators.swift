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

    public static let all: [Emulator] = [.mesenCE, .duckStation, .dolphin, .ares, .melonDS, .ymir, .ppsspp, .pcsx2, .xemu]

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
        default: nil
        }
    }

    /// The command line for a Play. It sets every Emulator setting, with the default where the Game
    /// has none (ADR 0008). DuckStation and PPSSPP take settings only as a whole file, so their Plays write one first
    /// (`DuckStationSettings`, `PPSSPPSettings`); DuckStation's are its Standing settings and its per-game file, named by
    /// `serials`' Disc 1. MesenCE's Standing settings go into its `settings.json` (`MesenSettings`), the Game's own on
    /// its command line. DuckStation and MesenCE start from a `saveState`.
    public func arguments(
        rom: URL, platformId: Int64, settings: EmulatorSettings, serials: Serials = .notRead, saveState: URL? = nil,
        duckStation: DuckStationSettings = .init(), mesen: MesenSettings = .init(), ppsspp: PPSSPPSettings = .init(),
        pcsx2: PCSX2GameSettings = .init()
    ) throws -> [String] {
        switch self {
        case .duckStation:
            try duckStation.arguments(rom: rom, settings: settings, serials: serials, saveState: saveState)
        case .mesenCE:
            try mesen.arguments(rom: rom, platformId: platformId, settings: settings, saveState: saveState)
        case .dolphin:
            // Lower input latency for every Game, for this launch only: frames shown as soon as
            // they're ready, with their timing smoothed. Immediately Present XFB stays off: it breaks some Games.
            [
                "-C", "Main.Core.RushFramePresentation=True", "-C", "Main.Core.SmoothEarlyPresentation=True", "-e",
                rom.path(percentEncoded: false),
            ]
        case .ares:
            // ares's run-ahead is on or off (one frame); any run-ahead frames turn it on. `--setting`
            // overrides are for this launch only: ares puts the saved values back.
            [
                "--system", platformId == 4 ? "Nintendo 64" : platformId == 78 ? "Mega CD" : "Mega Drive",
                "--setting", "General/RunAhead=\((settings.runAheadFrames ?? 0) > 0)", rom.path(percentEncoded: false),
            ]
        case .melonDS, .ymir:
            // No settings: it just opens the Game.
            [rom.path(percentEncoded: false)]
        case .pcsx2:
            // The game settings layer comes from Ludeum's file; PCSX2's own settings (controllers, BIOS) still apply.
            ["-batch", "-fastboot", "-gamecfg", try pcsx2.write().path(percentEncoded: false), "--", rom.path(percentEncoded: false)]
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
/// folder (`DuckStationFolder`), no checking for updates (DuckStation would replace its own bundle), and for every Game
/// fast boot, skipping the BIOS logo and running unthrottled to its first frame, unless DuckStation's game database
/// says that breaks it (its `ForceFullBoot`, which `-fastboot` would override), and its lowest input latency, presenting
/// each frame on time and running it as late as it can before then. The PlayStation ROM folder is among its game list's
/// folders, so a lone Disc of a set can swap to the set's others (ADR 0026). Everything else in the file is DuckStation's
/// own.
///
/// A Game's own settings go into DuckStation's per-game file for the disc, named by its Serial
/// (`<Game Settings>/SLUS-00551.ini`), where its Game Properties keeps them too (ADR 0021). Ludeum's win: a setting the
/// Game has is set, and one it hasn't is taken out, so DuckStation's own applies; the file's other settings stay, and so
/// does what's changed in DuckStation during the Play. A multi-disc Version's file is Disc 1's, unless that keeps each
/// Disc's settings apart (`UseSeparateConfigForDiscSet`), when every Disc's file is written. Without Disc 1's Serial
/// nothing is written, so a Game with settings of its own is refused (`Play.Refusal.noSerial`).
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

    /// Writes the Standing settings, then the Game's own into its per-game file, then opens the ROM, from `saveState` if
    /// given (`-statefile`): `--` ends DuckStation's options. When the disc the state was saved with isn't where it was
    /// (a renamed ROM), DuckStation boots the ROM instead. Refused while the Data folder is missing.
    func arguments(rom: URL, settings: EmulatorSettings, serials: Serials, saveState: URL? = nil) throws -> [String] {
        try writeStanding()
        try write(settings, serials: serials)
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
    /// CheckAtStartup` off, fast boot and the lowest input latency on, and the PlayStation ROM folder in `[GameList]
    /// RecursivePaths`, beside any of DuckStation's own.
    static func standing(in ini: String, ludeum: LudeumFolder) -> String {
        var ini = ini
        for folder in DuckStationFolder.allCases {
            ini = Ini.setting(folder.setting.key, to: path(ludeum.duckStation(folder)), in: folder.setting.section, of: ini)
        }
        for (section, key) in standingKeys { ini = Ini.setting(key, to: "true", in: section, of: ini) }
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

    /// The keys on for every Game, which used to go into each per-game file (the sleep needs the pacing).
    static let standingKeys = [
        ("BIOS", "PatchFastBoot"), ("BIOS", "FastForwardBoot"), ("Display", "OptimalFramePacing"), ("Display", "PreFrameSleep"),
    ]

    /// Writes the Game's own settings into each per-game file its Serials name. A Game with none, and no file yet,
    /// gets none. The other Discs' files get no settings, as DuckStation goes by Disc 1's, but lose what every Play
    /// wrote into them before ADR 0024 (Disc 1's card).
    func write(_ settings: EmulatorSettings, serials: Serials) throws {
        guard let first = serials.first else { return }
        var discs = [first]
        for serial in serials.known where !discs.contains(serial) { discs.append(serial) }
        let disc1 = (try? String(contentsOf: gameSettingsFile(first), encoding: .utf8)) ?? ""
        let separate = Ini.value("UseSeparateConfigForDiscSet", in: "Main", of: disc1).map(Ini.isTrue) == true
        for serial in discs {
            let url = gameSettingsFile(serial)
            let original = try? String(contentsOf: url, encoding: .utf8)
            let updated =
                serial == first || separate
                ? Self.applying(settings, to: original ?? "", serial: first)
                : Self.removingWhatIsStanding(from: original ?? "", serial: first)
            guard updated != original, !(original == nil && updated.isEmpty) else { continue }
            try FileManager.default.createDirectory(at: gameSettingsFolder, withIntermediateDirectories: true)
            try updated.write(to: url, atomically: true, encoding: .utf8)
        }
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

    /// `ini` with `[Main] RunaheadFrameCount` set to the Game's run-ahead, `[CDROM] ReadSpeedup` and `SeekSpeedup` to
    /// its CD read and seek speedups, each taken out where it has none, and without what Ludeum used to write into
    /// every per-game file (fast boot, the lowest latency, and card 1 as `serial`'s card in the Data folder), which is
    /// Standing now.
    static func applying(_ settings: EmulatorSettings, to ini: String, serial: String) -> String {
        func apply(_ value: Int?, _ key: String, in section: String, of ini: String) -> String {
            value.map { Ini.setting(key, to: "\($0)", in: section, of: ini) } ?? Ini.removing(key, in: section, of: ini)
        }
        var ini = removingWhatIsStanding(from: ini, serial: serial)
        ini = apply(settings.runAheadFrames, "RunaheadFrameCount", in: "Main", of: ini)
        ini = apply(settings.cdReadSpeedup, "ReadSpeedup", in: "CDROM", of: ini)
        return apply(settings.cdSeekSpeedup, "SeekSpeedup", in: "CDROM", of: ini)
    }

    /// A per-game `ini` without what every Play wrote before ADR 0024, as it wrote it: the Standing keys on, and card 1
    /// as the shared card Ludeum named `<serial>.mcd` in the Data folder (ADR 0023; Disc 1's for every Disc). A value
    /// set since in DuckStation's Game Properties (fast boot off, a card of my own, in that folder or not) is
    /// DuckStation's, and stays. Met on every Play, so the one-off command isn't the only way a file loses them.
    public static func removingWhatIsStanding(from ini: String, serial: String) -> String {
        var ini = ini
        for (section, key) in standingKeys where Ini.value(key, in: section, of: ini).map(Ini.isTrue) == true {
            ini = Ini.removing(key, in: section, of: ini)
        }
        let ludeums = "/Emulators/DuckStation/Memory Cards/" + fileName(serial) + ".mcd"
        if Ini.value("Card1Path", in: "MemoryCards", of: ini)?.hasSuffix(ludeums) == true {
            ini = Ini.removing("Card1Path", in: "MemoryCards", of: ini)
            if Ini.value("Card1Type", in: "MemoryCards", of: ini) == "Shared" {
                ini = Ini.removing("Card1Type", in: "MemoryCards", of: ini)
            }
        }
        return ini
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

    /// `ini` without `key` in `[section]`, and without the section when nothing's left in it.
    static func removing(_ key: String, in section: String, of ini: String) -> String {
        let header = "[\(section)]"
        var lines = lines(of: ini)
        var start = 0
        while let found = lines[start...].firstIndex(where: { trimmed($0) == header }) {
            let end = lines[(found + 1)...].firstIndex { trimmed($0).hasPrefix("[") } ?? lines.count
            guard let line = lines[(found + 1)..<end].firstIndex(where: { Self.key(of: trimmed($0)) == key }) else {
                start = end
                continue
            }
            lines.remove(at: line)
            if lines[(found + 1)..<(end - 1)].allSatisfy({ trimmed($0).isEmpty }) {
                // The last section keeps what follows the file's last line break.
                lines.removeSubrange(found..<(end - 1 == lines.count ? max(found + 1, lines.count - 1) : end - 1))
            }
            return lines.joined(separator: "\n")
        }
        return ini
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
    /// DuckStation's `ReadSpeedup`: 1 is off (the PlayStation's own double speed), 2–6 that many times faster, 0 as fast
    /// as it can. Nil is DuckStation's own setting.
    public var cdReadSpeedup: Int?
    /// DuckStation's `SeekSpeedup`, as `cdReadSpeedup` is its `ReadSpeedup`: 1 is off, 2–6 that many times faster, 0 as
    /// fast as it can. Nil is DuckStation's own setting.
    public var cdSeekSpeedup: Int?

    public static let runAheadRange = 0...10
    public static let cdReadSpeedupRange = 0...6
    public static let cdSeekSpeedupRange = 0...6

    /// Any setting of its own that goes into DuckStation's per-game file, which needs the Game's Serial.
    public var hasDuckStationSettings: Bool { runAheadFrames != nil || cdReadSpeedup != nil || cdSeekSpeedup != nil }

    public init(
        runAheadFrames: Int? = nil, gameBoyModel: GameBoyModel? = nil, cdReadSpeedup: Int? = nil, cdSeekSpeedup: Int? = nil
    ) {
        self.runAheadFrames = runAheadFrames
        self.gameBoyModel = gameBoyModel
        self.cdReadSpeedup = cdReadSpeedup
        self.cdSeekSpeedup = cdSeekSpeedup
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
                db, sql: "SELECT runAheadFrames, gameBoyModel, cdReadSpeedup, cdSeekSpeedup FROM game WHERE id = ?",
                arguments: [game])
            return EmulatorSettings(
                runAheadFrames: row?["runAheadFrames"],
                gameBoyModel: (row?["gameBoyModel"] as String?).flatMap(GameBoyModel.init(rawValue:)),
                cdReadSpeedup: row?["cdReadSpeedup"],
                cdSeekSpeedup: row?["cdSeekSpeedup"])
        }
    }

    public func setEmulatorSettings(_ game: GameID, _ settings: EmulatorSettings) throws {
        if let frames = settings.runAheadFrames, !EmulatorSettings.runAheadRange.contains(frames) {
            throw LudeumError.runAheadOutOfRange
        }
        if let speedup = settings.cdReadSpeedup, !EmulatorSettings.cdReadSpeedupRange.contains(speedup) {
            throw LudeumError.cdReadSpeedupOutOfRange
        }
        if let speedup = settings.cdSeekSpeedup, !EmulatorSettings.cdSeekSpeedupRange.contains(speedup) {
            throw LudeumError.cdSeekSpeedupOutOfRange
        }
        try db.write { db in
            try db.execute(
                sql: "UPDATE game SET runAheadFrames = ?, gameBoyModel = ?, cdReadSpeedup = ?, cdSeekSpeedup = ? WHERE id = ?",
                arguments: [
                    settings.runAheadFrames, settings.gameBoyModel?.rawValue, settings.cdReadSpeedup, settings.cdSeekSpeedup, game,
                ])
        }
    }
}

/// The game settings file every PCSX2 Play uses, in place of PCSX2's own per-game settings: Optimal
/// Frame Pacing (no frames queued for VSync), the lowest input latency PCSX2 has. PS2 emulators have no run-ahead.
public struct PCSX2GameSettings: Sendable {
    let file: URL

    public init(file: URL = LudeumFolder.standard.url.appending(path: "PCSX2 game settings.ini")) {
        self.file = file
    }

    /// Writes the file and returns where it is.
    func write() throws -> URL {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "[EmuCore/GS]\nVsyncQueueSize = 0\n".write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
