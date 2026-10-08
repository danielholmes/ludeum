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
    public let compactExtension: String?
    /// How its ROMs are Archived, when they can be: nil for the rest.
    public let archiving: Archiving?
    /// Whose names its ROMs are given by Rename: Redump's for the disc Platforms it catalogues, No-Intro's for the rest.
    let naming: Naming

    /// How an Archived ROM unpacks.
    public enum Archiving: Sendable, Equatable {
        /// Everything in the archive, into a folder named after the ROM (PS2 and the disc Platforms).
        case intoFolder
        /// Its one file, named after the ROM, loose in the ROM folder (PSP, Vita, GameCube and Wii).
        case singleFile
    }

    /// The group whose names a Platform's ROMs follow (ADR 0012).
    public enum Naming: Sendable, Equatable {
        case noIntro, redump
    }

    init(
        name: String, folderName: String, readyExtensions: [String], libretroRepo: String, compactExtension: String? = nil,
        archiving: Archiving? = nil, naming: Naming = .noIntro
    ) {
        self.name = name
        self.folderName = folderName
        self.readyExtensions = readyExtensions
        self.libretroRepo = libretroRepo
        self.compactExtension = compactExtension
        self.archiving = archiving
        self.naming = naming
    }

    /// Whether a ROM whose file is `fileName` can still be Compacted: its Emulator opens an archive the file isn't yet.
    func canCompact(fileName: String) -> Bool {
        compactExtension.map { (fileName as NSString).pathExtension.lowercased() != $0 } ?? false
    }

    public static let ps2: Int64 = 8
    public static let psp: Int64 = 38
    public static let vita: Int64 = 46

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
            libretroRepo: "Nintendo_-_GameCube",
            archiving: .singleFile, naming: .redump),
        // Not `.nfs`: a Wii U eShop Wii game is a folder with a key file.
        5: .init(
            name: "Wii", folderName: "Wii", readyExtensions: ["wad", "rvz", "wbfs", "iso", "wia", "gcz", "ciso"],
            libretroRepo: "Nintendo_-_Wii",
            archiving: .singleFile, naming: .redump),
        7: .init(
            name: "PlayStation", folderName: "PS1", readyExtensions: ["m3u", "chd", "cue", "pbp", "iso", "bin", "img"],
            libretroRepo: "Sony_-_PlayStation",
            archiving: .intoFolder, naming: .redump),
        38: .init(
            name: "PlayStation Portable", folderName: "PSP", readyExtensions: ["iso", "cso", "chd", "pbp"],
            libretroRepo: "Sony_-_PlayStation_Portable",
            archiving: .singleFile, naming: .redump),
        // A `.vpk`, though no Emulator plays it yet. Not a `.zip` of the game's folder, which Vita3K also installs:
        // a `.zip` is ares's.
        46: .init(
            name: "PlayStation Vita", folderName: "Vita", readyExtensions: ["vpk"], libretroRepo: "Sony_-_PlayStation_Vita",
            archiving: .singleFile),
        8: .init(
            name: "PlayStation 2", folderName: "PS2", readyExtensions: ["iso", "chd", "cso", "zso", "gz", "cue", "bin", "mdf"],
            libretroRepo: "Sony_-_PlayStation_2",
            archiving: .intoFolder, naming: .redump),
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
            libretroRepo: "Sega_-_Mega-CD_-_Sega_CD",
            archiving: .intoFolder, naming: .redump),
        32: .init(
            name: "Sega Saturn", folderName: "Saturn", readyExtensions: ["m3u", "chd", "cue", "iso", "bin"], libretroRepo: "Sega_-_Saturn",
            archiving: .intoFolder, naming: .redump),
        150: .init(
            name: "Turbografx-16/PC Engine CD", folderName: "PC Engine CD", readyExtensions: ["m3u", "chd", "cue", "bin"],
            libretroRepo: "NEC_-_PC_Engine_CD_-_TurboGrafx-CD",
            archiving: .intoFolder, naming: .redump),
        // No Emulator yet, so nothing to Compact into.
        53: .init(
            name: "MSX2", folderName: "MSX2", readyExtensions: ["rom", "mx2", "mx1", "dsk", "cas"], libretroRepo: "Microsoft_-_MSX2"),
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
