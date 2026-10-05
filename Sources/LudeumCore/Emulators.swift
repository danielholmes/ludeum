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

    /// The Emulator a Platform's Games are played in, if it has one.
    public static func of(platformId: Int64) -> Emulator? {
        switch platformId {
        // NES, Family Computer, SNES, Super Famicom, Game Boy, Game Boy Color, GBA, Master System, PC Engine, PC Engine CD
        case 18, 99, 19, 58, 33, 22, 24, 64, 86, 150: .mesenCE
        case 7: .duckStation  // PlayStation
        case 21, 5: .dolphin  // GameCube, Wii
        case 4: .ares  // Nintendo 64
        case 29: .ares  // Mega Drive/Genesis
        case 78: .ares  // Sega CD
        case 20: .melonDS  // Nintendo DS
        case 32: .ymir  // Saturn
        default: nil
        }
    }

    /// The command line for a Play. It sets every Emulator setting, with the default where the Game
    /// has none, because a running MesenCE keeps the last Play's settings (ADR 0008). DuckStation
    /// takes settings only as a whole file, so its Play writes one first (`DuckStationSettings`).
    public func arguments(
        rom: URL, platformId: Int64, settings: EmulatorSettings, duckStation: DuckStationSettings = .init()
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
        default:
            ["--doNotSaveSettings", "--emulation.runAheadFrames=\(settings.runAheadFrames ?? 0)", rom.path(percentEncoded: false)]
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
        let setting = "RunaheadFrameCount = \(settings.runAheadFrames ?? 0)"
        var lines = ini.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var section = ""
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                section = trimmed
            } else if section == "[Main]", trimmed.split(separator: "=").first?.trimmingCharacters(in: .whitespaces) == "RunaheadFrameCount"
            {
                lines[i] = setting
                return lines.joined(separator: "\n")
            }
        }
        if let main = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[Main]" }) {
            lines.insert(setting, at: main + 1)
        } else {
            lines.insert(contentsOf: ["[Main]", setting, ""], at: 0)
        }
        return lines.joined(separator: "\n")
    }
}

/// A Game's own Emulator settings. Nil means the Emulator's default.
public struct EmulatorSettings: Sendable, Equatable {
    public var runAheadFrames: Int?

    public static let runAheadRange = 0...10

    public init(runAheadFrames: Int? = nil) {
        self.runAheadFrames = runAheadFrames
    }
}

extension LudeumStore {
    public func emulatorSettings(_ game: GameID) throws -> EmulatorSettings {
        try db.read { db in
            EmulatorSettings(
                runAheadFrames: try Int.fetchOne(db, sql: "SELECT runAheadFrames FROM game WHERE id = ?", arguments: [game]))
        }
    }

    public func setEmulatorSettings(_ game: GameID, _ settings: EmulatorSettings) throws {
        if let frames = settings.runAheadFrames, !EmulatorSettings.runAheadRange.contains(frames) {
            throw LudeumError.runAheadOutOfRange
        }
        try db.write { db in
            try db.execute(sql: "UPDATE game SET runAheadFrames = ? WHERE id = ?", arguments: [settings.runAheadFrames, game])
        }
    }
}
