import Foundation
import GRDB

/// The app a Platform's Games are played in.
public struct Emulator: Sendable, Equatable {
    public let name: String
    public let bundleIdentifier: String

    public static let mesenCE = Emulator(name: "MesenCE", bundleIdentifier: "ca.mesen")

    /// The Emulator a Platform's Games are played in, if it has one.
    public static func of(platformId: Int64) -> Emulator? {
        switch platformId {
        case 18, 99, 19, 58, 33, 22: .mesenCE  // NES, Family Computer, SNES, Super Famicom, Game Boy, Game Boy Color
        default: nil
        }
    }

    /// The command line for a Play. It sets every Emulator setting, with the default where the Game
    /// has none, because a running MesenCE keeps the last Play's settings (ADR 0008).
    public func arguments(rom: URL, settings: EmulatorSettings) -> [String] {
        ["--doNotSaveSettings", "--emulation.runAheadFrames=\(settings.runAheadFrames ?? 0)", rom.path(percentEncoded: false)]
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
