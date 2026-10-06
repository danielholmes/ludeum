import Foundation
import GRDB

/// A Platform that has a ROM folder: what its folder is called, what its Emulator opens, whether its ROMs can be Compacted
/// or Archived, and where libretro keeps its Box art.
public struct ROMPlatform: Sendable, Equatable {
    /// IGDB's name, used until IGDB's own is known.
    public let name: String
    /// The ROM folder's name under the ROM folders' root.
    public let folderName: String
    /// What its Emulator opens, most preferred first.
    let readyExtensions: [String]
    /// The libretro-thumbnails repo its ROMs are looked up in. The Famicom's ROMs look in NES's, and the
    /// Super Famicom's in SNES's.
    let libretroRepo: String
    /// The archive its Emulator opens directly, so its ROMs can be Compacted into it: `7z` for MesenCE and melonDS,
    /// `zip` for ares (which can't open a `.7z`). Nil where the Emulator opens neither.
    let compactExtension: String?
    /// How its ROMs are Archived, when they can be: nil for the rest.
    let archiving: Archiving?

    /// How an Archived ROM unpacks.
    enum Archiving: Sendable, Equatable {
        /// Everything in the archive, into a folder named after the ROM (PS2).
        case intoFolder
        /// Its one file, named after the ROM, loose in the ROM folder (PSP).
        case singleFile
    }

    init(
        name: String, folderName: String, readyExtensions: [String], libretroRepo: String, compactExtension: String? = nil,
        archiving: Archiving? = nil
    ) {
        self.name = name
        self.folderName = folderName
        self.readyExtensions = readyExtensions
        self.libretroRepo = libretroRepo
        self.compactExtension = compactExtension
        self.archiving = archiving
    }

    /// Whether a ROM whose file is `fileName` can still be Compacted: its Emulator opens an archive the file isn't yet.
    func canCompact(fileName: String) -> Bool {
        compactExtension.map { (fileName as NSString).pathExtension.lowercased() != $0 } ?? false
    }

    public static let ps2: Int64 = 8
    public static let psp: Int64 = 38

    /// Every Platform with a ROM folder, by IGDB platform id. One folder per Platform: Game Boy and
    /// Game Boy Color, NES and Famicom, SNES and Super Famicom each have their own.
    public static let all: [Int64: ROMPlatform] = [
        33: .init(
            name: "Game Boy", folderName: "Game Boy", readyExtensions: ["gb", "gbc", "sgb"], libretroRepo: "Nintendo_-_Game_Boy",
            compactExtension: "7z"),
        22: .init(
            name: "Game Boy Color", folderName: "Game Boy Color", readyExtensions: ["gbc", "gb"],
            libretroRepo: "Nintendo_-_Game_Boy_Color",
            compactExtension: "7z"),
        24: .init(
            name: "Game Boy Advance", folderName: "Game Boy Advance", readyExtensions: ["gba"],
            libretroRepo: "Nintendo_-_Game_Boy_Advance",
            compactExtension: "7z"),
        18: .init(
            name: "Nintendo Entertainment System", folderName: "NES", readyExtensions: ["nes", "fds", "unf", "unif"],
            libretroRepo: "Nintendo_-_Nintendo_Entertainment_System",
            compactExtension: "7z"),
        99: .init(
            name: "Family Computer", folderName: "Famicom", readyExtensions: ["nes", "fds", "unf", "unif"],
            libretroRepo: "Nintendo_-_Nintendo_Entertainment_System",
            compactExtension: "7z"),
        19: .init(
            name: "Super Nintendo Entertainment System", folderName: "SNES", readyExtensions: ["sfc", "smc", "swc", "fig"],
            libretroRepo: "Nintendo_-_Super_Nintendo_Entertainment_System",
            compactExtension: "7z"),
        58: .init(
            name: "Super Famicom", folderName: "Super Famicom", readyExtensions: ["sfc", "smc", "swc", "fig"],
            libretroRepo: "Nintendo_-_Super_Nintendo_Entertainment_System",
            compactExtension: "7z"),
        4: .init(
            name: "Nintendo 64", folderName: "N64", readyExtensions: ["z64", "n64", "v64"], libretroRepo: "Nintendo_-_Nintendo_64",
            compactExtension: "zip"),
        20: .init(
            name: "Nintendo DS", folderName: "DS", readyExtensions: ["nds"], libretroRepo: "Nintendo_-_Nintendo_DS", compactExtension: "7z"),
        21: .init(
            name: "Nintendo GameCube", folderName: "GameCube", readyExtensions: ["rvz", "iso", "gcm", "ciso", "gcz", "wbfs"],
            libretroRepo: "Nintendo_-_GameCube"),
        7: .init(
            name: "PlayStation", folderName: "PS1", readyExtensions: ["m3u", "chd", "cue", "pbp", "iso", "bin", "img"],
            libretroRepo: "Sony_-_PlayStation"),
        38: .init(
            name: "PlayStation Portable", folderName: "PSP", readyExtensions: ["iso", "cso", "chd", "pbp"],
            libretroRepo: "Sony_-_PlayStation_Portable",
            archiving: .singleFile),
        8: .init(
            name: "PlayStation 2", folderName: "PS2", readyExtensions: ["iso", "chd", "cso", "zso", "gz", "cue", "bin", "mdf"],
            libretroRepo: "Sony_-_PlayStation_2",
            archiving: .intoFolder),
        29: .init(
            name: "Sega Mega Drive/Genesis", folderName: "Mega Drive", readyExtensions: ["md", "gen", "smd", "bin"],
            libretroRepo: "Sega_-_Mega_Drive_-_Genesis",
            compactExtension: "zip"),
        64: .init(
            name: "Sega Master System/Mark III", folderName: "Master System", readyExtensions: ["sms"],
            libretroRepo: "Sega_-_Master_System_-_Mark_III",
            compactExtension: "7z"),
        35: .init(
            name: "Sega Game Gear", folderName: "Game Gear", readyExtensions: ["gg"], libretroRepo: "Sega_-_Game_Gear",
            compactExtension: "7z"),
        78: .init(
            name: "Sega CD", folderName: "Sega CD", readyExtensions: ["m3u", "chd", "cue", "iso", "bin"],
            libretroRepo: "Sega_-_Mega-CD_-_Sega_CD"),
        32: .init(
            name: "Sega Saturn", folderName: "Saturn", readyExtensions: ["m3u", "chd", "cue", "iso", "bin"], libretroRepo: "Sega_-_Saturn"
        ),
        150: .init(
            name: "Turbografx-16/PC Engine CD", folderName: "PC Engine CD", readyExtensions: ["m3u", "chd", "cue", "bin"],
            libretroRepo: "NEC_-_PC_Engine_CD_-_TurboGrafx-CD"),
    ]

    /// Platforms OpenEmu kept under one system, so a ROM from it may belong on any of them.
    static let siblingGroups: [[Int64]] = [[33, 22], [18, 99], [19, 58]]

    /// The Platforms a ROM on `id` may be Confirmed on: its sibling group in order, or just `id`.
    static func siblings(of id: Int64) -> [Int64] {
        siblingGroups.first { $0.contains(id) } ?? [id]
    }

    /// Records the Platform if the journal doesn't know it yet, so a ROM can point at it.
    static func ensureKnown(_ db: Database, _ id: Int64) throws {
        try db.execute(
            sql: "INSERT OR IGNORE INTO platform (id, name) VALUES (?, ?)", arguments: [id, all[id]?.name ?? "Platform \(id)"])
    }
}
