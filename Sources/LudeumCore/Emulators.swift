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
        default: nil
        }
    }

    /// The command line for a Play. It sets every Emulator setting, with the default where the Game
    /// has none, because a running MesenCE keeps the last Play's settings (ADR 0008). DuckStation
    /// and PPSSPP take settings only as a whole file, so their Plays write one first (`DuckStationSettings`,
    /// `PPSSPPSettings`).
    public func arguments(
        rom: URL, platformId: Int64, settings: EmulatorSettings, duckStation: DuckStationSettings = .init(),
        ppsspp: PPSSPPSettings = .init(), pcsx2: PCSX2GameSettings = .init()
    ) throws -> [String] {
        switch self {
        case .duckStation:
            ["-settings", try duckStation.write(settings).path(percentEncoded: false), rom.path(percentEncoded: false)]
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

/// The settings file a DuckStation Play starts with: a copy of DuckStation's own `settings.ini`
/// with the Game's settings written over it, so its controllers, BIOS and video settings carry over.
/// Changes made in DuckStation during that Play go to the copy and are lost.
public struct DuckStationSettings: Sendable {
    let base: URL
    let copy: URL

    public init(
        base: URL = URL.applicationSupportDirectory.appending(path: "DuckStation/settings.ini"),
        copy: URL = AppSettings.appFolder.appending(path: "DuckStation settings.ini")
    ) {
        self.base = base
        self.copy = copy
    }

    /// Writes the copy and returns where it is.
    func write(_ settings: EmulatorSettings) throws -> URL {
        let original = (try? String(contentsOf: base, encoding: .utf8)) ?? ""
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.applying(settings, to: original).write(to: copy, atomically: true, encoding: .utf8)
        return copy
    }

    /// `ini` with `[Main] RunaheadFrameCount` set to the Game's run-ahead (0 by default).
    static func applying(_ settings: EmulatorSettings, to ini: String) -> String {
        Ini.setting("RunaheadFrameCount", to: "\(settings.runAheadFrames ?? 0)", in: "Main", of: ini)
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
        copy: URL = AppSettings.appFolder.appending(path: "PPSSPP ppsspp.ini")
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
        var lines = ini.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var current = ""
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                current = trimmed
            } else if current == header, trimmed.split(separator: "=").first?.trimmingCharacters(in: .whitespaces) == key {
                lines[i] = setting
                return lines.joined(separator: "\n")
            }
        }
        if let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) {
            lines.insert(setting, at: start + 1)
        } else {
            lines.insert(contentsOf: [header, setting, ""], at: 0)
        }
        return lines.joined(separator: "\n")
    }
}

/// A Game's own Emulator settings. Nil means the Emulator's default.
public struct EmulatorSettings: Sendable, Equatable {
    public var runAheadFrames: Int?
    /// Nil is Auto: MesenCE picks from the ROM, favouring Game Boy Color.
    public var gameBoyModel: GameBoyModel?

    public static let runAheadRange = 0...10

    public init(runAheadFrames: Int? = nil, gameBoyModel: GameBoyModel? = nil) {
        self.runAheadFrames = runAheadFrames
        self.gameBoyModel = gameBoyModel
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
            let row = try Row.fetchOne(db, sql: "SELECT runAheadFrames, gameBoyModel FROM game WHERE id = ?", arguments: [game])
            return EmulatorSettings(
                runAheadFrames: row?["runAheadFrames"],
                gameBoyModel: (row?["gameBoyModel"] as String?).flatMap(GameBoyModel.init(rawValue:)))
        }
    }

    public func setEmulatorSettings(_ game: GameID, _ settings: EmulatorSettings) throws {
        if let frames = settings.runAheadFrames, !EmulatorSettings.runAheadRange.contains(frames) {
            throw LudeumError.runAheadOutOfRange
        }
        try db.write { db in
            try db.execute(
                sql: "UPDATE game SET runAheadFrames = ?, gameBoyModel = ? WHERE id = ?",
                arguments: [settings.runAheadFrames, settings.gameBoyModel?.rawValue, game])
        }
    }
}

/// The game settings file every PCSX2 Play uses, in place of PCSX2's own per-game settings: Optimal
/// Frame Pacing (no frames queued for VSync), the lowest input latency PCSX2 has. PS2 emulators have no run-ahead.
public struct PCSX2GameSettings: Sendable {
    let file: URL

    public init(file: URL = AppSettings.appFolder.appending(path: "PCSX2 game settings.ini")) {
        self.file = file
    }

    /// Writes the file and returns where it is.
    func write() throws -> URL {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "[EmuCore/GS]\nVsyncQueueSize = 0\n".write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
