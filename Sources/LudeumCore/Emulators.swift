import Foundation
import GRDB

/// The app a Platform's Games are played in.
public struct Emulator: Sendable, Equatable {
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
    /// has none, because a running MesenCE keeps the last Play's settings (ADR 0008). DuckStation
    /// and PPSSPP take settings only as a whole file, so their Plays write one first (`DuckStationSettings`,
    /// `PPSSPPSettings`); DuckStation's is its per-game file, named by `serials`' Disc 1. Only DuckStation starts from a
    /// `saveState`.
    public func arguments(
        rom: URL, platformId: Int64, settings: EmulatorSettings, serials: Serials = .notRead, saveState: URL? = nil, app: URL? = nil,
        duckStation: DuckStationSettings = .init(), ppsspp: PPSSPPSettings = .init(), pcsx2: PCSX2GameSettings = .init()
    ) throws -> [String] {
        switch self {
        case .duckStation:
            try duckStation.arguments(rom: rom, settings: settings, serials: serials, saveState: saveState, app: app)
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
            ["--doNotSaveSettings", "--emulation.runAheadFrames=\(settings.runAheadFrames ?? 0)"]
                + (GameBoyModel.applies(to: platformId) ? ["--gameboy.model=\(settings.gameBoyModel?.mesenName ?? "AutoFavorGbc")"] : [])
                + [rom.path(percentEncoded: false)]
        }
    }
}

/// A DuckStation Play's settings, merged into DuckStation's own per-game settings file for the disc, named by its
/// Serial (`gamesettings/SLUS-00551.ini`), where its Game Properties keeps them too (ADR 0021). Ludeum's win: a setting
/// the Game has is set, and one it hasn't is taken out, so DuckStation's own applies. Every Game fast boots, skipping the
/// BIOS logo and running unthrottled to its first frame, unless DuckStation's game database says that breaks it (its
/// `ForceFullBoot`, which `-fastboot` would override), and every Game has DuckStation's lowest input latency, presenting
/// each frame on time and running it as late as it can before then. The file's other settings stay, and so does what's
/// changed in DuckStation during the Play. A multi-disc Version's file is Disc 1's, unless that keeps each
/// Disc's settings apart (`UseSeparateConfigForDiscSet`), when every Disc's file is written. Every Disc's file points
/// card 1 at the ROM's memory card in the Data folder (ADR 0023). Without Disc 1's Serial, nothing is written: Play is
/// refused (`Play.Refusal.noSerial`).
public struct DuckStationSettings: Sendable {
    /// DuckStation's data folder, holding its `settings.ini`.
    let dataFolder: URL
    /// The copy of DuckStation's `settings.ini` a Play wrote for `-settings` before DuckStation dropped it (build 8843).
    let oldCopy: URL
    /// Whose Data folder holds each ROM's memory card.
    let ludeum: LudeumFolder

    public init(
        dataFolder: URL = URL.applicationSupportDirectory.appending(path: "DuckStation", directoryHint: .isDirectory),
        oldCopy: URL = LudeumFolder.standard.url.appending(path: "DuckStation settings.ini"), ludeum: LudeumFolder = .standard
    ) {
        self.dataFolder = dataFolder
        self.oldCopy = oldCopy
        self.ludeum = ludeum
    }

    /// Copies DuckStation's own card into the Data folder if it hasn't the ROM's yet, writes the settings, then opens the
    /// ROM, from `saveState` if given (`-statefile`): `--` ends DuckStation's options. When the disc the state was saved
    /// with isn't where it was (a renamed ROM), DuckStation boots the ROM instead. `app` is DuckStation's, whose game
    /// database names its own cards.
    func arguments(rom: URL, settings: EmulatorSettings, serials: Serials, saveState: URL? = nil, app: URL? = nil) throws
        -> [String]
    {
        if let first = serials.first {
            try DuckStationMemoryCards(duckStation: self).moveIn(serial: first, rom: rom, resources: app.map(GameDatabase.resources))
        }
        try write(settings, serials: serials)
        return (saveState.map { ["-statefile", $0.path(percentEncoded: false)] } ?? []) + ["--", rom.path(percentEncoded: false)]
    }

    /// Writes the Game's settings into each per-game file its Serials name, and points every Disc's card 1 at the ROM's
    /// card in the Data folder, making the folder DuckStation writes it into. Refused while the Data folder is missing,
    /// so a card is never saved somewhere Dropbox doesn't see.
    func write(_ settings: EmulatorSettings, serials: Serials) throws {
        try? FileManager.default.removeItem(at: oldCopy)
        guard let first = serials.first else { return }
        try ludeum.checkData()
        let cards = DuckStationMemoryCards(duckStation: self)
        try FileManager.default.createDirectory(at: cards.folder, withIntermediateDirectories: true)
        let card = cards.card(of: first)
        var toWrite = [first]
        let disc1 = (try? String(contentsOf: gameSettingsFile(first), encoding: .utf8)) ?? ""
        if Ini.value("UseSeparateConfigForDiscSet", in: "Main", of: disc1).map(Ini.isTrue) == true {
            for serial in serials.known where !toWrite.contains(serial) { toWrite.append(serial) }
        }
        // The other Discs' files have the card alone: DuckStation goes by Disc 1's for a disc set it knows, but by each
        // Disc's own for one it doesn't.
        for serial in serials.known.reduce(into: [first], { if !$0.contains($1) { $0.append($1) } }) {
            let url = gameSettingsFile(serial)
            let original = try? String(contentsOf: url, encoding: .utf8)
            let ini = toWrite.contains(serial) ? Self.applying(settings, to: original ?? "") : original ?? ""
            let updated = Self.pointing(at: card, in: ini)
            guard updated != original else { continue }
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

    /// One of DuckStation's folders: its settings' `[<section>] <key>` (from its data folder when relative), else `name`
    /// in its data folder.
    func folder(_ key: String, in section: String = "Folders", default name: String) -> URL {
        let ini = (try? String(contentsOf: dataFolder.appending(path: "settings.ini"), encoding: .utf8)) ?? ""
        guard let path = Ini.value(key, in: section, of: ini), !path.isEmpty else {
            return dataFolder.appending(path: name, directoryHint: .isDirectory)
        }
        return path.hasPrefix("/")
            ? URL(filePath: path, directoryHint: .isDirectory) : dataFolder.appending(path: path, directoryHint: .isDirectory)
    }

    /// `ini` with `[Main] RunaheadFrameCount` set to the Game's run-ahead, `[CDROM] ReadSpeedup` and `SeekSpeedup` to
    /// its CD read and seek speedups, each taken out where it has none, and `[BIOS] PatchFastBoot` and `FastForwardBoot`
    /// and `[Display] OptimalFramePacing` and `PreFrameSleep` on (the sleep needs the pacing).
    static func applying(_ settings: EmulatorSettings, to ini: String) -> String {
        func apply(_ value: Int?, _ key: String, in section: String, of ini: String) -> String {
            value.map { Ini.setting(key, to: "\($0)", in: section, of: ini) } ?? Ini.removing(key, in: section, of: ini)
        }
        var ini = apply(settings.runAheadFrames, "RunaheadFrameCount", in: "Main", of: ini)
        ini = apply(settings.cdReadSpeedup, "ReadSpeedup", in: "CDROM", of: ini)
        ini = apply(settings.cdSeekSpeedup, "SeekSpeedup", in: "CDROM", of: ini)
        ini = ["PatchFastBoot", "FastForwardBoot"].reduce(ini) { Ini.setting($1, to: "true", in: "BIOS", of: $0) }
        return ["OptimalFramePacing", "PreFrameSleep"].reduce(ini) { Ini.setting($1, to: "true", in: "Display", of: $0) }
    }

    /// `ini` with card 1 the one shared card at `card`, whatever DuckStation's Game Properties set it to.
    static func pointing(at card: URL, in ini: String) -> String {
        Ini.setting(
            "Card1Path", to: card.path(percentEncoded: false), in: "MemoryCards",
            of: Ini.setting("Card1Type", to: "Shared", in: "MemoryCards", of: ini))
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
        if let start = lines.firstIndex(where: { trimmed($0) == header }) {
            lines.insert(setting, at: start + 1)
        } else {
            lines.insert(contentsOf: [header, setting, ""], at: 0)
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
        var current = ""
        for line in lines(of: ini) {
            let trimmed = trimmed(line)
            if trimmed.hasPrefix("[") {
                current = trimmed
            } else if current == "[\(section)]", Self.key(of: trimmed) == key, let equals = trimmed.firstIndex(of: "=") {
                return trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
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
