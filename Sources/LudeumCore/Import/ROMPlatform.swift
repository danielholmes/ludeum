import GRDB

/// A Platform that has a ROM folder: what its folder is called and what its Emulator opens.
public struct ROMPlatform: Sendable, Equatable {
    /// IGDB's name, used until IGDB's own is known.
    public let name: String
    /// The ROM folder's name under the ROM folders' root.
    public let folderName: String
    /// What its Emulator opens, most preferred first.
    let readyExtensions: [String]

    public static let ps2: Int64 = 8

    /// Every Platform with a ROM folder, by IGDB platform id. One folder per Platform: Game Boy and
    /// Game Boy Color, NES and Famicom, SNES and Super Famicom each have their own.
    public static let all: [Int64: ROMPlatform] = [
        33: .init(name: "Game Boy", folderName: "Game Boy", readyExtensions: ["gb", "gbc", "sgb"]),
        22: .init(name: "Game Boy Color", folderName: "Game Boy Color", readyExtensions: ["gbc", "gb"]),
        24: .init(name: "Game Boy Advance", folderName: "Game Boy Advance", readyExtensions: ["gba"]),
        18: .init(name: "Nintendo Entertainment System", folderName: "NES", readyExtensions: ["nes", "fds", "unf", "unif"]),
        99: .init(name: "Family Computer", folderName: "Famicom", readyExtensions: ["nes", "fds", "unf", "unif"]),
        19: .init(name: "Super Nintendo Entertainment System", folderName: "SNES", readyExtensions: ["sfc", "smc", "swc", "fig"]),
        58: .init(name: "Super Famicom", folderName: "Super Famicom", readyExtensions: ["sfc", "smc", "swc", "fig"]),
        4: .init(name: "Nintendo 64", folderName: "N64", readyExtensions: ["z64", "n64", "v64"]),
        20: .init(name: "Nintendo DS", folderName: "DS", readyExtensions: ["nds"]),
        21: .init(name: "Nintendo GameCube", folderName: "GameCube", readyExtensions: ["rvz", "iso", "gcm", "ciso", "gcz", "wbfs"]),
        7: .init(name: "PlayStation", folderName: "PS1", readyExtensions: ["m3u", "chd", "cue", "pbp", "iso", "bin", "img"]),
        38: .init(name: "PlayStation Portable", folderName: "PSP", readyExtensions: ["iso", "cso", "chd", "pbp"]),
        8: .init(name: "PlayStation 2", folderName: "PS2", readyExtensions: ["iso", "chd", "cso", "zso", "gz", "cue", "bin", "mdf"]),
        29: .init(name: "Sega Mega Drive/Genesis", folderName: "Mega Drive", readyExtensions: ["md", "gen", "smd", "bin"]),
        64: .init(name: "Sega Master System/Mark III", folderName: "Master System", readyExtensions: ["sms"]),
        35: .init(name: "Sega Game Gear", folderName: "Game Gear", readyExtensions: ["gg"]),
        78: .init(name: "Sega CD", folderName: "Sega CD", readyExtensions: ["m3u", "chd", "cue", "iso", "bin"]),
        32: .init(name: "Sega Saturn", folderName: "Saturn", readyExtensions: ["m3u", "chd", "cue", "iso", "bin"]),
        150: .init(name: "Turbografx-16/PC Engine CD", folderName: "PC Engine CD", readyExtensions: ["m3u", "chd", "cue", "bin"]),
    ]

    /// The Platform an OpenEmu system's ROM goes to when it has no Game: the system's most likely one.
    public static func defaultPlatform(system: String) -> Int64? { openEmuSystemPlatforms[system]?.first.map(Int64.init) }

    /// Records the Platform if the journal doesn't know it yet, so a ROM can point at it.
    static func ensureKnown(_ db: Database, _ id: Int64) throws {
        try db.execute(
            sql: "INSERT OR IGNORE INTO platform (id, name) VALUES (?, ?)", arguments: [id, all[id]?.name ?? "Platform \(id)"])
    }
}
